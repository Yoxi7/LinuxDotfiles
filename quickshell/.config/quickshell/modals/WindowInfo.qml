pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Сведения об окне: клик по заголовку в баре. Клик по значению — копирует его.
// Внизу: закрыть окно, плавающее/плитка, завершить процесс (подтверждение вторым кликом).
ModalWindow {
    id: root
    name: "wininfo"
    dropdown: true
    cardWidth: 460
    cardHeight: col.implicitHeight + 32

    readonly property var c: WinInfo.client
    readonly property var p: WinInfo.proc
    readonly property var entry: DesktopEntries.heuristicLookup(c.appid ?? "")
    property string copied: ""
    property bool armed: false

    Component.onCompleted: WinInfo.users++
    Component.onDestruction: WinInfo.users--

    function copy(v) {
        if (!v) return
        Quickshell.execDetached(["wl-copy", String(v)])
        copied = String(v)
        copyReset.restart()
    }
    Timer { id: copyReset; interval: 1200; onTriggered: root.copied = "" }

    function bytes(n) {
        if (!n) return "—"
        return n >= 1073741824 ? (n / 1073741824).toFixed(2) + " ГиБ" : (n / 1048576).toFixed(0) + " МиБ"
    }
    function dur(s) {
        if (!s && s !== 0) return "—"
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + " д " : "") + (h ? h + " ч " : "") + (m || (!d && !h) ? m + " мин" : "")
    }
    readonly property var flags: {
        const f = []
        const names = { is_floating: "плавающее", is_fullscreen: "во весь экран", is_maximized: "развёрнуто",
                        is_minimized: "свёрнуто", is_scratchpad: "скретчпад", is_global: "на всех рабочих столах",
                        is_overlay: "поверх", is_urgent: "требует внимания", is_fakefullscreen: "псевдополноэкранный режим",
                        is_group: "в группе", is_swallowing: "поглотило другое окно", is_swallowedby: "поглощено другим окном" }
        for (const k in names) if (c[k]) f.push(names[k])
        return f.length ? f.join(" · ") : "обычное (плитка)"
    }

    component Row2: Item {
        id: r
        property string label
        property string value
        property bool mono: false
        visible: value !== "" && value !== "undefined"
        width: parent?.width ?? 0
        height: visible ? Math.max(28, val.implicitHeight + 10) : 0
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: rowMouse.containsMouse ? Theme.strong : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }
        Text {
            id: lab
            anchors { left: parent.left; leftMargin: 10; top: parent.top; topMargin: 7 }
            width: 104
            text: r.label
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            id: val
            anchors { left: lab.right; right: parent.right; rightMargin: 10; top: parent.top; topMargin: 6 }
            text: root.copied === r.value && r.value !== "" ? "скопировано" : r.value
            color: root.copied === r.value && r.value !== "" ? Theme.success : Theme.text
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            font { family: r.mono ? "MedeoMono Nerd Font Mono" : Theme.font; pixelSize: r.mono ? 11 : 13; features: ({ "tnum": 1 }) }
        }
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.copy(r.value) }
    }

    component Act: Rectangle {
        id: act
        property string label
        property color tint: Theme.text
        property bool wide: false
        signal clicked
        height: 34
        radius: 10
        color: am.pressed ? Theme.border : am.containsMouse ? Theme.strong : Theme.weak
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: act.label
            color: act.tint
            font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
        }
        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12

        // шапка: значок, имя приложения, заголовок
        Item {
            width: col.width
            height: 56
            Image {
                id: ico
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 48; height: 48
                sourceSize { width: 96; height: 96 }
                source: Quickshell.iconPath(root.entry?.icon ?? root.c.appid ?? "", "application-x-executable")
            }
            Column {
                anchors { left: ico.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.entry?.name ?? root.c.appid ?? "Нет окна"
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.c.title ?? ""
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
        }

        // окно
        Glass {
            width: col.width
            height: winCol.implicitHeight + 12
            radius: 12
            color: Qt.rgba(0, 0, 0, 0.22)
            sheen: false
            interactive: false
            fresnel: 0.5
            rimColor: Qt.rgba(1, 1, 1, 0.07)
            glintColor: Qt.rgba(1, 1, 1, 0.55)
            rimWidth: 1
            Column {
                id: winCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Row2 { label: "App ID"; value: root.c.appid ?? ""; mono: true }
                Row2 { label: "Протокол"; value: root.c.is_xwayland === undefined ? "" : root.c.is_xwayland ? "XWayland (X11)" : "Wayland" }
                Row2 { label: "Монитор"; value: root.c.monitor ?? "" }
                Row2 { label: "Рабочий стол"; value: (root.c.tags ?? []).length ? (root.c.tags ?? []).join(", ") : (root.c.is_scratchpad ? "скретчпад" : "") }
                Row2 {
                    label: "Геометрия"
                    value: root.c.width !== undefined ? root.c.width + " × " + root.c.height + "  @  " + root.c.x + ", " + root.c.y : ""
                }
                Row2 { label: "Состояние"; value: root.c.id !== undefined ? root.flags : "" }
                Row2 { label: "ID окна mango"; value: root.c.id !== undefined ? String(root.c.id) : "" }
            }
        }

        // процесс
        Glass {
            width: col.width
            height: procCol.implicitHeight + 12
            visible: root.p.exe !== undefined || root.p.cmd !== undefined || root.c.pid !== undefined
            radius: 12
            color: Qt.rgba(0, 0, 0, 0.22)
            sheen: false
            interactive: false
            fresnel: 0.5
            rimColor: Qt.rgba(1, 1, 1, 0.07)
            glintColor: Qt.rgba(1, 1, 1, 0.55)
            rimWidth: 1
            Column {
                id: procCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                Row2 { label: "PID"; value: root.c.pid !== undefined ? String(root.c.pid) : "" }
                Row2 { label: "Программа"; value: root.p.exe ?? ""; mono: true }
                Row2 { label: "Команда"; value: root.p.cmd ?? ""; mono: true }
                Row2 { label: "Папка"; value: root.p.cwd ?? ""; mono: true }
                Row2 { label: "Память"; value: root.p.rss ? root.bytes(root.p.rss) : "" }
                Row2 { label: "CPU"; value: root.p.cpu !== undefined ? root.p.cpu.toFixed(1) + " %   ·   потоков " + root.p.threads : "" }
                Row2 { label: "Время работы"; value: root.p.elapsed !== undefined ? root.dur(root.p.elapsed) : "" }
                Row2 { label: "Пользователь"; value: root.p.user ?? "" }
                Row2 { label: "Файл запуска (.desktop)"; value: root.entry?.execString ?? ""; mono: true }
            }
        }

        // действия
        Row {
            width: col.width
            spacing: 8
            readonly property real w: (col.width - 16) / 3
            Act {
                width: parent.w
                label: "Закрыть окно"
                onClicked: { Quickshell.execDetached(["mmsg", "dispatch", "killclient"]); Modal.close() }
            }
            Act {
                width: parent.w
                label: root.c.is_floating ? "В плитку" : "В плавающее"
                onClicked: { Quickshell.execDetached(["mmsg", "dispatch", "togglefloating"]); WinInfo.refresh() }
            }
            Act {
                width: parent.w
                label: root.armed ? "Точно завершить?" : "Завершить процесс"
                tint: Theme.danger
                onClicked: {
                    if (root.armed) { Quickshell.execDetached(["kill", "-9", String(root.c.pid)]); Modal.close() }
                    else { root.armed = true; disarm.restart() }
                }
                Timer { id: disarm; interval: 2500; onTriggered: root.armed = false }
            }
        }
    }
}
