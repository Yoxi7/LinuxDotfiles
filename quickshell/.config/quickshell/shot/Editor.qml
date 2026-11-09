pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Редактор скриншота (порт AnnotationEditor из iNiR): карандаш, прямоугольник, стрелка, текст, маркер.
// Готово (Enter / Ctrl+S) — сохранить в ~/Pictures/Screenshots и скопировать; Ctrl+Z — отменить; Esc — выбросить.
PanelWindow {
    id: root
    screen: Quickshell.screens.find(s => s.name === Shot.editorScreen) ?? null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-shot-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string tool: "pen"            // pen | rect | arrow | text | highlight
    property color stroke: Theme.danger
    property real strokeWidth: 4
    property var strokes: []               // готовые фигуры
    property var texts: []                 // подписи
    property var history: []               // порядок: "shape" | "text"
    property var current: null             // фигура, которую сейчас рисуют
    readonly property string out: Shot.tmp + "/annotated.png"

    readonly property var palette: [Theme.danger, Theme.warning, Theme.success, Theme.primary, Theme.accent, "#ffffff", "#000000"]
    readonly property var tools: [
        { id: "pen", icon: "" }, { id: "rect", icon: "" }, { id: "arrow", icon: "" },
        { id: "text", icon: "" }, { id: "highlight", icon: "" }
    ]

    function close() { Shot.editorPath = "" }
    function push(kind) { history = history.concat([kind]) }
    function commit(s) { strokes = strokes.concat([s]); push("shape") }
    function addText(x, y) {
        texts = texts.concat([{ x: x, y: y - 6, text: "", color: String(stroke), size: Math.max(16, strokeWidth * 5) }])
        push("text")
    }
    function undo() {
        if (!history.length) return
        const h = history.slice(), last = h.pop()
        history = h
        if (last === "shape") strokes = strokes.slice(0, -1)
        else texts = texts.slice(0, -1)
    }

    // точки ломаной для фигуры
    function pointsFor(s) {
        if (!s || !s.pts.length) return []
        if (s.tool === "pen" || s.tool === "highlight") return s.pts
        const a = s.pts[0], b = s.pts[s.pts.length - 1]
        if (s.tool === "rect")
            return [Qt.point(a.x, a.y), Qt.point(b.x, a.y), Qt.point(b.x, b.y), Qt.point(a.x, b.y), Qt.point(a.x, a.y)]
        // стрелка
        const dx = b.x - a.x, dy = b.y - a.y, len = Math.max(1, Math.hypot(dx, dy))
        const ux = dx / len, uy = dy / len, head = Math.min(14 + s.width * 3, len * 0.4), ang = 0.5
        const lx = b.x - head * (ux * Math.cos(ang) - uy * Math.sin(ang)), ly = b.y - head * (uy * Math.cos(ang) + ux * Math.sin(ang))
        const rx = b.x - head * (ux * Math.cos(ang) + uy * Math.sin(ang)), ry = b.y - head * (uy * Math.cos(ang) - ux * Math.sin(ang))
        return [Qt.point(a.x, a.y), Qt.point(b.x, b.y), Qt.point(lx, ly), Qt.point(b.x, b.y), Qt.point(rx, ry)]
    }

    function save() {
        keys.forceActiveFocus()                 // убрать курсор из поля текста
        if (img.status !== Image.Ready) return
        canvas.grabToImage(r => {
            if (!r.saveToFile(root.out)) {
                Quickshell.execDetached(["notify-send", "-a", "Скриншот", "-i", "dialog-error", "Не удалось сохранить правку"])
                return
            }
            Quickshell.execDetached(["bash", "-c",
                'mkdir -p "$2" && f="$2/$(date +"$3").png" && mv "$1" "$f" && wl-copy -t image/png < "$f" ' +
                '&& notify-send -a "Скриншот" -i "$f" "Скриншот с правками скопирован" "$(basename "$f")"',
                "save", root.out, Shot.saveDir, Shot.nameFormat])
            root.close()
        }, Qt.size(img.sourceSize.width, img.sourceSize.height))
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const ctrl = e.modifiers & Qt.ControlModifier
            if (e.key === Qt.Key_Escape) root.close()
            else if (ctrl && e.key === Qt.Key_Z) root.undo()
            else if ((ctrl && e.key === Qt.Key_S) || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.save()
            else return
            e.accepted = true
        }

        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }

        Column {
            anchors.centerIn: parent
            spacing: 18
            opacity: img.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }

            // холст: картинка + разметка — именно он сохраняется
            Item {
                id: canvas
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property real iw: img.sourceSize.width
                readonly property real ih: img.sourceSize.height
                readonly property real fit: iw > 0 && ih > 0 ? Math.min(root.width * 0.84 / iw, root.height * 0.74 / ih, 1) : 1
                width: iw > 0 ? Math.round(iw * fit) : 480
                height: ih > 0 ? Math.round(ih * fit) : 320

                Image {
                    id: img
                    anchors.fill: parent
                    source: Shot.editorPath ? "file://" + Shot.editorPath : ""
                    cache: false
                    smooth: true
                    mipmap: true
                }

                Repeater {
                    model: root.strokes
                    Shape {
                        id: sh
                        required property var modelData
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        opacity: modelData.tool === "highlight" ? 0.4 : 1
                        ShapePath {
                            strokeColor: sh.modelData.color
                            strokeWidth: sh.modelData.width
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline { path: root.pointsFor(sh.modelData) }
                        }
                    }
                }

                // текущая фигура — Canvas, чтобы не пересобирать Shape на каждое движение
                Canvas {
                    id: live
                    anchors.fill: parent
                    renderStrategy: Canvas.Threaded
                    property var s: root.current
                    onSChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const p = root.pointsFor(s)
                        if (p.length < 2) return
                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                        ctx.lineWidth = s.width
                        ctx.strokeStyle = s.color
                        ctx.globalAlpha = s.tool === "highlight" ? 0.4 : 1
                        ctx.beginPath()
                        ctx.moveTo(p[0].x, p[0].y)
                        for (let i = 1; i < p.length; i++) ctx.lineTo(p[i].x, p[i].y)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
                    property point last
                    onPressed: e => {
                        if (root.tool === "text") { root.addText(e.x, e.y); return }
                        last = Qt.point(e.x, e.y)
                        root.current = { tool: root.tool, color: String(root.stroke),
                                         width: root.tool === "highlight" ? root.strokeWidth * 4 : root.strokeWidth,
                                         pts: [Qt.point(e.x, e.y)] }
                    }
                    onPositionChanged: e => {
                        const c = root.current
                        if (!c) return
                        if (Math.hypot(e.x - last.x, e.y - last.y) < 2.5) return
                        last = Qt.point(e.x, e.y)
                        c.pts = c.tool === "pen" || c.tool === "highlight" ? c.pts.concat([last]) : [c.pts[0], last]
                        root.current = Object.assign({}, c)
                    }
                    onReleased: {
                        if (root.current && root.current.pts.length > 1) root.commit(root.current)
                        root.current = null
                    }
                }

                // подписи (поверх области рисования, чтобы их можно было править)
                Repeater {
                    model: root.texts
                    TextInput {
                        required property var modelData
                        required property int index
                        x: modelData.x; y: modelData.y
                        color: modelData.color
                        font { family: Theme.font; pixelSize: modelData.size; weight: Font.DemiBold }
                        text: modelData.text
                        onTextChanged: root.texts[index].text = text
                        selectByMouse: true
                        cursorVisible: activeFocus
                        Component.onCompleted: if (text === "") forceActiveFocus()
                        Keys.onEscapePressed: keys.forceActiveFocus()
                        onAccepted: keys.forceActiveFocus()           // Enter завершает ввод подписи, не сохраняет снимок
                        Keys.onReturnPressed: e => { keys.forceActiveFocus(); e.accepted = true }
                        Keys.onEnterPressed: e => { keys.forceActiveFocus(); e.accepted = true }
                    }
                }
            }

            // панель
            Glass {
                anchors.horizontalCenter: parent.horizontalCenter
                width: bar.implicitWidth + 20
                height: 56
                radius: 28
                color: Theme.glassStrong

                component Btn: Rectangle {
                    id: b
                    property string icon
                    property bool on: false
                    property bool primary: false
                    property real rotate: 0
                    signal clicked
                    width: 40; height: 40; radius: 20
                    anchors.verticalCenter: parent?.verticalCenter
                    color: on || primary ? Theme.selected : m.containsMouse ? Theme.strong : "transparent"
                    opacity: enabled ? 1 : 0.35
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    Text {
                        anchors.centerIn: parent
                        text: b.icon
                        rotation: b.rotate
                        color: b.on || b.primary ? Theme.base : Theme.text
                        font { family: Theme.iconFont; pixelSize: 15 }
                    }
                    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
                }
                component Sep: Rectangle { width: 1; height: 24; color: Theme.border; anchors.verticalCenter: parent?.verticalCenter }

                Row {
                    id: bar
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: root.tools
                        Btn {
                            required property var modelData
                            icon: modelData.icon
                            rotate: modelData.id === "arrow" ? 45 : 0
                            on: root.tool === modelData.id
                            onClicked: root.tool = modelData.id
                        }
                    }
                    Sep {}
                    Item { width: 4; height: 1 }
                    Repeater {
                        model: root.palette
                        Item {
                            id: sw
                            required property var modelData
                            width: 30; height: 40
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                anchors.centerIn: parent
                                width: Qt.colorEqual(root.stroke, sw.modelData) ? 26 : 20
                                height: width
                                radius: width / 2
                                color: sw.modelData
                                border { width: Qt.colorEqual(root.stroke, sw.modelData) ? 3 : 1; color: Qt.colorEqual(root.stroke, sw.modelData) ? Theme.text : Theme.border }
                                Behavior on width { NumberAnimation { duration: Theme.dFast } }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stroke = sw.modelData }
                        }
                    }
                    Item { width: 6; height: 1 }
                    Sep {}
                    Item { width: 8; height: 1 }
                    Slider {
                        width: 90
                        anchors.verticalCenter: parent.verticalCenter
                        value: (root.strokeWidth - 1) / 15
                        onMoved: v => root.strokeWidth = 1 + Math.round(v * 15)
                    }
                    Text {
                        width: 26
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.strokeWidth
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                    }
                    Item { width: 6; height: 1 }
                    Sep {}
                    Btn { icon: ""; enabled: root.history.length > 0; onClicked: root.undo() }
                    Btn { icon: ""; primary: true; onClicked: root.save() }
                    Btn { icon: ""; onClicked: root.close() }
                }
            }
        }
    }
}
