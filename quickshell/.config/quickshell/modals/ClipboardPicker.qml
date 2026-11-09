pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Widgets
import qs

// История буфера (cliphist): поиск, фильтр «всё / текст / картинки», превью картинок.
// Enter / клик — скопировать, Shift+Del — удалить запись, Tab — следующий фильтр.
// «Скрыть» (Ctrl+H) — всё содержимое размыто; строка раскрывается, пока на ней курсор. Запоминается.
// Превью раскодируются только для видимых строк в $XDG_RUNTIME_DIR/qs-clip (tmpfs, чистится при выходе).
ModalWindow {
    id: root
    name: "clipboard"
    cardWidth: 680
    cardHeight: 600

    property var entries: []               // [{ line, id, text, image, meta }]
    property string query: ""
    property string kind: "all"            // all | text | image
    readonly property string thumbs: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-clip"
    readonly property bool hide: Session.clipHide || Session.privacy

    readonly property var shown: {
        const q = query.trim().toLowerCase()
        return entries.filter(e => (kind === "all" || (kind === "image") === e.image)
                                   && (q === "" || e.text.toLowerCase().includes(q)))
    }

    // строка cliphist: «id<TAB>превью»; картинки: «[[ binary data 77 KiB png 1015x778 ]]»
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$1"; find "$1" -type f -mmin +720 -delete; cliphist list | head -n 500', "clip", root.thumbs]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    const body = line.slice(tab + 1)
                    const m = /^\[\[ binary data (.+?) (\w+) (\d+x\d+) \]\]$/.exec(body)
                    out.push({ line: line, id: line.slice(0, tab), text: m ? "" : body, image: !!m,
                               meta: m ? m[2].toUpperCase() + "  ·  " + m[3].replace("x", "×") + "  ·  " + m[1] : "" })
                }
                root.entries = out
            }
        }
    }

    function copy(e) {
        if (!e) return
        Modal.close()
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist decode | wl-copy', "clip", e.line])
    }
    function remove(e) {
        if (!e) return
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | cliphist delete', "clip", e.line])
        const i = list.currentIndex
        entries = entries.filter(x => x !== e)
        list.currentIndex = Math.min(i, shown.length - 1)
    }
    function cycleKind() { kind = kind === "all" ? "text" : kind === "text" ? "image" : "all"; list.currentIndex = 0 }

    onKeyPressed: e => {
        if (e.key === Qt.Key_Down) { list.incrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.decrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_PageDown) { list.currentIndex = Math.min(list.count - 1, list.currentIndex + 6); e.accepted = true }
        else if (e.key === Qt.Key_PageUp) { list.currentIndex = Math.max(0, list.currentIndex - 6); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { copy(shown[list.currentIndex]); e.accepted = true }
        else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) { remove(shown[list.currentIndex]); e.accepted = true }
        else if (e.key === Qt.Key_Tab) { cycleKind(); e.accepted = true }
        else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_H) { Session.clipHide = !Session.clipHide; e.accepted = true }
    }
    Connections {
        target: Demo
        function onQueryChanged() { input.text = Demo.query; root.query = Demo.query; list.currentIndex = 0 }
        function onClipKindChanged() { root.kind = Demo.clipKind; list.currentIndex = 0 }
    }

    // поиск
    Rectangle {
        id: field
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
        height: 46
        radius: 14
        color: Theme.weak
        border { width: 1; color: input.activeFocus ? Theme.border : Theme.strong }

        Text {
            id: clipIcon
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: "\u{f014c}"
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 17 }
        }
        TextInput {
            id: input
            anchors { left: clipIcon.right; leftMargin: 12; right: counter.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            focus: true
            color: Theme.text
            selectionColor: Theme.accent
            font { family: Theme.font; pixelSize: 16 }
            onTextChanged: { root.query = text; list.currentIndex = 0 }
            Keys.onTabPressed: root.cycleKind()
            Text {
                visible: !input.text
                text: "Буфер обмена…"
                color: Theme.faint
                font: input.font
            }
        }
        Text {
            id: counter
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: root.shown.length
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
    }

    // фильтр
    Row {
        id: chips
        anchors { top: field.bottom; topMargin: 10; left: parent.left; leftMargin: 14 }
        spacing: 6
        Repeater {
            model: [["all", "Всё"], ["text", "Текст"], ["image", "Картинки"]]
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: root.kind === modelData[0]
                width: chipText.implicitWidth + 24
                height: 28
                radius: 14
                color: on ? Theme.selected : chipMouse.containsMouse ? Theme.strong : Theme.weak
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData[1]
                    color: chip.on ? Theme.base : Theme.text
                    font { family: Theme.font; pixelSize: 12; weight: chip.on ? Font.DemiBold : Font.Normal }
                }
                MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.kind = chip.modelData[0]; list.currentIndex = 0 } }
            }
        }
    }
    // «Скрыть»: размывает содержимое записей (текст и картинки)
    Rectangle {
        id: hideBtn
        anchors { verticalCenter: chips.verticalCenter; right: parent.right; rightMargin: 14 }
        height: 28
        width: hideRow.implicitWidth + 24
        radius: 14
        color: root.hide ? Theme.selected : hideMouse.containsMouse ? Theme.strong : Theme.weak
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Row {
            id: hideRow
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hide ? "\uf070" : "\uf06e"
                color: root.hide ? Theme.base : Theme.text
                font { family: Theme.iconFont; pixelSize: 12 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Скрыть"
                color: root.hide ? Theme.base : Theme.text
                font { family: Theme.font; pixelSize: 12; weight: root.hide ? Font.DemiBold : Font.Normal }
            }
        }
        MouseArea { id: hideMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Session.clipHide = !Session.clipHide }
    }
    Text {
        anchors { verticalCenter: chips.verticalCenter; right: hideBtn.left; rightMargin: 14 }
        text: root.hide ? "Наведи курсор, чтобы увидеть  ·  Enter — копировать  ·  Ctrl+H" : "Enter — копировать  ·  Shift+Del — удалить  ·  Tab — фильтр"
        color: Theme.faint
        font { family: Theme.font; pixelSize: 11 }
    }

    ListView {
        id: list
        anchors { top: chips.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 10 }
        clip: true
        model: root.shown
        spacing: 4
        cacheBuffer: 200
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        highlight: Rectangle { radius: 14; color: Theme.strong; border { width: 1; color: Theme.rimSoft } }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var e: modelData
            readonly property string thumb: root.thumbs + "/" + e.id + ".png"
            width: list.width
            height: e.image ? 84 : Math.max(46, preview.implicitHeight + 24)
            // содержимое видно, если режим «Скрыть» выключен или на строке курсор
            readonly property bool revealed: !root.hide || rowMouse.containsMouse
            property real veil: revealed ? 0 : 1
            Behavior on veil { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
            component Veil: MultiEffect {
                blurEnabled: true
                blur: row.veil
                blurMax: 48
                saturation: -row.veil * 0.6
                brightness: -row.veil * 0.1
            }

            // картинка: раскодировать в tmpfs, если ещё нет
            Process {
                id: decode
                running: row.e.image
                command: ["sh", "-c", '[ -s "$2" ] || { printf "%s" "$1" | cliphist decode > "$2.tmp" && mv "$2.tmp" "$2"; }', "clip", row.e.line, row.thumb]
                onExited: img.source = "file://" + row.thumb
            }
            ClippingRectangle {
                id: imgBox
                visible: row.e.image
                layer.enabled: row.veil > 0.01
                layer.effect: Veil {}
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 120; height: 68
                radius: 10
                color: Theme.weak
                Image {
                    id: img
                    anchors.fill: parent
                    sourceSize { width: 240; height: 136 }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
            }
            Text {
                visible: row.e.image
                anchors { left: imgBox.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: row.e.meta
                color: row.ListView.isCurrentItem ? Theme.text : Theme.muted
                font { family: Theme.font; pixelSize: 13 }
            }

            Text {
                id: preview
                visible: !row.e.image
                layer.enabled: row.veil > 0.01
                layer.effect: Veil {}
                anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: row.e.text
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
                color: row.ListView.isCurrentItem ? Theme.text : Qt.rgba(1, 1, 1, 0.82)
                font { family: Theme.font; pixelSize: 14 }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: list.currentIndex = row.index
                onClicked: e => e.button === Qt.RightButton ? root.remove(row.e) : root.copy(row.e)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: root.entries.length ? "Ничего не найдено" : "Пусто"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 14 }
        }
    }
}
