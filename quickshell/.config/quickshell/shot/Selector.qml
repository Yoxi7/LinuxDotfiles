pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Выделение области на замороженном кадре — на каждом мониторе своё окно (порт regionSelector из iNiR).
//   ЛКМ-тянуть — область; клик — окно / найденная на картинке область под курсором
//   ПКМ в режиме «Снимок» — сразу в редактор
//   1…4 — действие, Tab — прямоугольник / обводка, F — весь экран, Esc — отмена
Scope {
    id: scope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            visible: ready
            color: "black"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "qs-shot"
            WlrLayershell.layer: WlrLayer.Overlay
            // клавиатура — только окну на мониторе с фокусом, иначе mango отдаёт её последнему созданному
            WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            property bool focused: false

            readonly property string image: Shot.tmp + "/image-" + modelData.name + ".png"
            property bool ready: false
            // монитор в раскладке mango: смещение и масштаб
            property real monX: modelData.x
            property real monY: modelData.y
            property real monScale: 1
            property var windowRegions: []     // [{ x, y, w, h, app, title }]
            property var contentRegions: []    // [{ x, y, w, h }]
            readonly property bool lasso: Shot.mode === "lasso"

            // выделение
            property real sx: 0
            property real sy: 0
            property real ex: 0
            property real ey: 0
            property bool dragging: false
            property bool moved: false
            property var points: []
            property int button: Qt.LeftButton
            readonly property real rx: Math.min(sx, ex)
            readonly property real ry: Math.min(sy, ey)
            readonly property real rw: Math.abs(ex - sx)
            readonly property real rh: Math.abs(ey - sy)
            // область под курсором (до начала перетаскивания)
            property var target: null
            property real mx: -1
            property real my: -1

            readonly property var actions: [
                { id: "copy", icon: "", name: "Снимок" },
                { id: "edit", icon: "", name: "Редактировать" },
                { id: "ocr", icon: "", name: "Текст" },
                { id: "record", icon: "", name: "Запись" }
            ]

            function regionAt(x, y) {
                const inside = r => r.x <= x && x <= r.x + r.w && r.y <= y && y <= r.y + r.h
                return contentRegions.find(inside) ?? windowRegions.find(inside) ?? null
            }

            // ── подготовка: кадр монитора + окна из mango
            Process {
                running: true
                command: ["bash", "-c",
                    'mkdir -p "$1" && grim -l 1 -o "$2" "$3" || exit 1; ' +
                    'mmsg get all-monitors 2>/dev/null | tr -d "\\n"; echo; mmsg get all-clients 2>/dev/null | tr -d "\\n"; echo',
                    "shot", Shot.tmp, win.modelData.name, win.image]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.split("\n")
                        try {
                            const mon = JSON.parse(lines[0]).monitors.find(m => m.name === win.modelData.name)
                            if (mon) { win.monX = mon.x; win.monY = mon.y; win.monScale = mon.scale || 1; win.focused = mon.active }
                        } catch (e) {}
                        try {
                            const cl = JSON.parse(lines[1]).clients
                                .filter(c => c.monitor === win.modelData.name && c.is_visible && !c.is_minimized && c.width > 0)
                                // плавающие и полноэкранные — поверх плиток, проверяются первыми
                                .sort((a, b) => (b.is_floating + b.is_fullscreen * 2) - (a.is_floating + a.is_fullscreen * 2))
                            win.windowRegions = cl.map(c => ({ x: c.x - win.monX, y: c.y - win.monY, w: c.width, h: c.height,
                                                               app: c.appid, title: c.title }))
                        } catch (e) {}
                    }
                }
                onExited: code => {
                    if (code !== 0) {
                        Quickshell.execDetached(["notify-send", "-a", "Скриншот", "-i", "dialog-error", "Скриншот не удался", "grim не смог снять экран"])
                        Shot.dismiss()
                        return
                    }
                    win.ready = true
                    finder.running = true
                }
            }

            // области на самой картинке (кнопки, картинки, блоки) — OpenCV selective search из iNiR
            Process {
                id: finder
                command: ["bash", "-c",
                    'py="$HOME/.local/state/quickshell/.venv/bin/python3"; [ -x "$py" ] || exit 0; ' +
                    'exec "$py" "$1" --image "$2" --max-width "$3" --max-height "$4" --hyprctl',
                    "find", Quickshell.shellDir + "/scripts/find_regions.py", win.image,
                    String(Math.round(win.modelData.width * win.monScale * 0.5)), String(Math.round(win.modelData.height * win.monScale * 0.5))]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = []
                        try { r = JSON.parse(text.trim() || "[]") } catch (e) { return }
                        const s = win.monScale
                        const iou = (a, b) => {
                            const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x))
                            const iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y))
                            const i = ix * iy
                            return i / (a.w * a.h + b.w * b.h - i)
                        }
                        // не дублировать окна; из пересекающихся областей оставить меньшую
                        let regs = r.map(o => ({ x: o.at[0] / s, y: o.at[1] / s, w: o.size[0] / s, h: o.size[1] / s }))
                                    .filter(a => !win.windowRegions.some(w => iou(a, w) > 0.1))
                                    .sort((a, b) => a.w * a.h - b.w * b.h)
                        const keep = []
                        for (const a of regs) if (!keep.some(k => iou(a, k) > 0)) keep.push(a)
                        win.contentRegions = keep
                    }
                }
            }

            // ── действие над выделенной областью
            function snip() {
                let x = rx, y = ry, w = rw, h = rh
                if (w < 2 || h < 2) { Shot.dismiss(); return }
                x = Math.max(0, x); y = Math.max(0, y)
                w = Math.min(w, width - x); h = Math.min(h, height - y)
                let action = Shot.action
                if (action === "copy" && button === Qt.RightButton) action = "edit"

                const s = monScale
                const crop = Math.round(w * s) + "x" + Math.round(h * s) + "+" + Math.round(x * s) + "+" + Math.round(y * s)
                const size = Math.round(w * s) + "×" + Math.round(h * s)
                switch (action) {
                case "copy":
                    Quickshell.execDetached(["bash", "-c",
                        'mkdir -p "$3" && f="$3/$(date +"$4").png" && magick "$1" -crop "$2" +repage "$f" && wl-copy -t image/png < "$f" ' +
                        '&& notify-send -a "Скриншот" -i "$f" "Скриншот скопирован" "$5 · $(basename "$f")"',
                        "shot", image, crop, Shot.saveDir, Shot.nameFormat, size])
                    break
                case "edit":
                    editCrop.command = ["magick", image, "-crop", crop, "+repage", Shot.tmp + "/edit.png"]
                    editCrop.running = true
                    return                      // закроется, когда кадр для редактора будет готов
                case "ocr":
                    Quickshell.execDetached(["bash", "-c",
                        't="$(magick "$1" -crop "$2" +repage png:- | tesseract - - -l rus+eng 2>/dev/null | sed -e "s/[[:space:]]*$//" -e "/./,\\$!d")"; ' +
                        'if [ -n "$t" ]; then printf "%s" "$t" | wl-copy; notify-send -a "OCR" -i edit-copy "Текст скопирован" "$(printf "%s" "$t" | head -c 200)"; ' +
                        'else notify-send -a "OCR" -i dialog-warning "Текст не найден"; fi',
                        "ocr", image, crop])
                    break
                case "record": {
                    const geo = Math.round(monX + x) + "," + Math.round(monY + y) + " " + Math.round(w) + "x" + Math.round(h)
                    const full = w >= width - 1 && h >= height - 1
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-record"].concat(full ? ["--output", modelData.name] : ["--region", geo],
                                                                              Shot.sound ? ["--sound"] : []))
                    break
                }
                }
                Shot.dismiss()
            }
            function snipFullscreen() {
                sx = 0; sy = 0; ex = width; ey = height
                button = Qt.LeftButton
                snip()
            }
            function pickColor() {
                Shot.dismiss()
                Quickshell.execDetached(["bash", "-c",
                    'sleep 0.3; c=$(hyprpicker -a -f hex) && [ -n "$c" ] && notify-send -a "Пипетка" "Цвет скопирован" "$c"'])
            }

            Process {
                id: editCrop
                onExited: code => {
                    if (code === 0) Shot.openEditor(Shot.tmp + "/edit.png", win.modelData.name)
                    else Shot.dismiss()
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    const n = e.key - Qt.Key_1
                    if (e.key === Qt.Key_Escape) Shot.dismiss()
                    else if (n >= 0 && n < win.actions.length) { Shot.action = win.actions[n].id; Shot.remember() }
                    else if (e.key === Qt.Key_Tab) { Shot.mode = win.lasso ? "rect" : "lasso"; Shot.remember() }
                    else if (e.key === Qt.Key_F) win.snipFullscreen()
                    else return
                    e.accepted = true
                }

                // замороженный кадр
                Image {
                    anchors.fill: parent
                    source: win.ready ? "file://" + win.image : ""
                    cache: false
                    smooth: false
                }

                // затемнение вокруг выделения (рамка-«рамка» шире экрана)
                Rectangle {
                    visible: !win.lasso
                    x: win.rx - border.width
                    y: win.ry - border.width
                    width: win.rw + border.width * 2
                    height: win.rh + border.width * 2
                    color: "transparent"
                    border { width: Math.max(win.width, win.height) * 2; color: Qt.rgba(0, 0, 0, 0.45) }
                }
                Rectangle {
                    visible: win.lasso
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
                // рамка выделения
                Rectangle {
                    visible: !win.lasso && win.rw > 0
                    x: win.rx; y: win.ry; width: win.rw; height: win.rh
                    color: "transparent"
                    border { width: 2; color: Theme.primary }
                }
                // размер
                Rectangle {
                    visible: !win.lasso && win.dragging && win.rw > 0
                    x: Math.min(win.rx + win.rw - width, win.width - width - 8)
                    y: win.ry + win.rh + 8 + height > win.height ? win.ry + win.rh - height - 8 : win.ry + win.rh + 8
                    width: sizeText.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Text {
                        id: sizeText
                        anchors.centerIn: parent
                        text: Math.round(win.rw * win.monScale) + " × " + Math.round(win.rh * win.monScale)
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                    }
                }
                // перекрестье
                Rectangle { visible: !win.lasso && win.mx >= 0; x: win.mx; width: 1; height: parent.height; color: Theme.primary; opacity: 0.25 }
                Rectangle { visible: !win.lasso && win.my >= 0; y: win.my; height: 1; width: parent.width; color: Theme.primary; opacity: 0.25 }

                // обводка
                Canvas {
                    id: lassoCanvas
                    anchors.fill: parent
                    visible: win.lasso
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const p = win.points
                        if (p.length < 2) return
                        ctx.lineJoin = "round"; ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.primary
                        ctx.lineWidth = 3
                        ctx.beginPath()
                        ctx.moveTo(p[0].x, p[0].y)
                        for (let i = 1; i < p.length; i++) ctx.lineTo(p[i].x, p[i].y)
                        ctx.stroke()
                    }
                }

                // окна и найденные области — подсказки для клика
                component Target: Rectangle {
                    id: t
                    required property var modelData
                    property bool isWindow: false
                    readonly property bool hot: win.target === modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    radius: isWindow ? 12 : 6
                    color: hot ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                    border { width: hot ? 3 : 1.5; color: isWindow ? Theme.primary : Theme.accent }
                    opacity: win.moved ? 0 : hot ? 1 : isWindow ? 0.5 : 0.3
                    Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                }
                Repeater {
                    model: win.lasso ? [] : win.windowRegions
                    Target {
                        id: wt
                        isWindow: true
                        // подпись: значок и приложение
                        Rectangle {
                            x: 10; y: 10
                            width: lbl.implicitWidth + 20 + 22
                            height: 28
                            radius: 14
                            color: Qt.rgba(0, 0, 0, 0.65)
                            border { width: 1; color: Theme.rim }
                            Image {
                                id: ico
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                width: 18; height: 18
                                sourceSize { width: 36; height: 36 }
                                source: Quickshell.iconPath(DesktopEntries.heuristicLookup(wt.modelData.app)?.icon ?? wt.modelData.app, "application-x-executable")
                            }
                            Text {
                                id: lbl
                                anchors { left: ico.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                text: DesktopEntries.heuristicLookup(wt.modelData.app)?.name ?? wt.modelData.app
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                            }
                        }
                    }
                }
                Repeater {
                    model: win.lasso ? [] : win.contentRegions
                    Target {}
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.CrossCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: e => {
                        win.button = e.button
                        win.sx = win.ex = e.x
                        win.sy = win.ey = e.y
                        win.dragging = true
                        win.moved = false
                        win.points = [Qt.point(e.x, e.y)]
                    }
                    onPositionChanged: e => {
                        win.mx = e.x; win.my = e.y
                        if (!win.dragging) { win.target = win.lasso ? null : win.regionAt(e.x, e.y); return }
                        if (Math.abs(e.x - win.sx) + Math.abs(e.y - win.sy) > 3) win.moved = true
                        win.ex = e.x; win.ey = e.y
                        if (win.lasso) {
                            const p = win.points
                            p.push(Qt.point(e.x, e.y))
                            win.points = p
                            lassoCanvas.requestPaint()
                        }
                    }
                    onReleased: e => {
                        win.dragging = false
                        if (!win.moved) {
                            // клик — по окну / области под курсором
                            const t = win.regionAt(e.x, e.y)
                            if (!t) return
                            win.sx = t.x; win.sy = t.y; win.ex = t.x + t.w; win.ey = t.y + t.h
                        } else if (win.lasso) {
                            const pad = 10, xs = win.points.map(p => p.x), ys = win.points.map(p => p.y)
                            win.sx = Math.min(...xs) - pad; win.sy = Math.min(...ys) - pad
                            win.ex = Math.max(...xs) + pad; win.ey = Math.max(...ys) + pad
                        }
                        win.snip()
                    }
                    onExited: { win.mx = -1; win.my = -1; win.target = null }
                }

                // ── панель снизу
                Glass {
                    id: bar
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: win.dragging ? -height : 28 }
                    width: tools.implicitWidth + 16
                    height: 56
                    radius: 28
                    color: Theme.glassStrong
                    opacity: win.dragging ? 0 : 1
                    Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Theme.dFast } }

                    MouseArea { anchors.fill: parent; hoverEnabled: true }   // не начинать выделение с панели

                    component Btn: Rectangle {
                        id: b
                        property string icon
                        property string label
                        property bool on: false
                        property color tint: Theme.text
                        signal clicked
                        width: label ? row.implicitWidth + 28 : 40
                        height: 40
                        radius: 20
                        anchors.verticalCenter: parent?.verticalCenter
                        color: on ? Theme.selected : m.containsMouse ? Theme.strong : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        Row {
                            id: row
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: b.icon
                                color: b.on ? Theme.base : b.tint
                                font { family: Theme.iconFont; pixelSize: 15 }
                            }
                            Text {
                                visible: b.label !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: b.label
                                color: b.on ? Theme.base : Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: b.on ? Font.DemiBold : Font.Medium }
                            }
                        }
                        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
                    }
                    component Sep: Rectangle { width: 1; height: 24; color: Theme.border; anchors.verticalCenter: parent?.verticalCenter }

                    Row {
                        id: tools
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: win.actions
                            Btn {
                                required property var modelData
                                icon: modelData.icon
                                label: modelData.name
                                on: Shot.action === modelData.id
                                tint: modelData.id === "record" && Shot.recording ? Theme.danger : Theme.text
                                onClicked: { Shot.action = modelData.id; Shot.remember() }
                            }
                        }
                        Btn {
                            visible: Shot.action === "record"
                            icon: Shot.sound ? "" : ""
                            on: Shot.sound
                            onClicked: Shot.sound = !Shot.sound
                        }
                        Sep {}
                        Btn { icon: ""; on: !win.lasso; onClicked: { Shot.mode = "rect"; Shot.remember() } }
                        Btn { icon: "\u{f0297}"; on: win.lasso; onClicked: { Shot.mode = "lasso"; Shot.remember() } }
                        Sep {}
                        Btn { icon: ""; onClicked: win.snipFullscreen() }
                        Btn { icon: ""; onClicked: win.pickColor() }
                        Btn { icon: ""; tint: Theme.muted; onClicked: Shot.dismiss() }
                    }
                }
            }
        }
    }
}
