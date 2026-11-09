pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Эмодзи: поиск по английским названиям и ключевым словам, категории, недавние.
// Выбор — в буфер и сразу печатается в окно, где был фокус (wtype). Shift+Enter / ПКМ — только в буфер.
//   ←→↑↓ — выбор, Enter — вставить, Tab / Shift+Tab — категории, Esc — закрыть
ModalWindow {
    id: root
    name: "emoji"
    cardWidth: 556
    cardHeight: 560

    property string query: ""
    property int group: recent.length ? -1 : 0       // -1 — недавние
    property var all: []                            // [[эмодзи, описание, группа]]
    readonly property var recent: Session.recentEmoji.split(" ").filter(e => e !== "")

    readonly property var groups: [
        { icon: "🕘", name: "Недавние" }, { icon: "😀", name: "Смайлы" }, { icon: "👋", name: "Люди" },
        { icon: "🐵", name: "Природа" }, { icon: "🍇", name: "Еда" }, { icon: "🌍", name: "Путешествия" },
        { icon: "🎃", name: "Активности" }, { icon: "👓", name: "Предметы" }, { icon: "🏧", name: "Символы" },
        { icon: "🏁", name: "Флаги" }, { icon: "✨", name: "Новые" }
    ]

    readonly property var shown: {
        const q = query.trim().toLowerCase()
        if (q) {
            const scored = []
            for (const x of all) {
                const t = x[1].toLowerCase()
                const s = t.startsWith(q) ? 0 : (" " + t).includes(" " + q) ? 1 : t.includes(q) ? 2 : -1
                if (s >= 0) scored.push([s, x])
            }
            return scored.sort((a, b) => a[0] - b[0]).map(p => p[1])
        }
        if (group < 0) return recent.map(e => all.find(x => x[0] === e) ?? [e, "", -1])
        return all.filter(x => x[2] === group)
    }
    readonly property var current: shown[grid.currentIndex] ?? null

    FileView {
        path: Quickshell.shellDir + "/data/emoji.json"
        blockLoading: true
        onLoaded: root.all = JSON.parse(text())
    }

    function pick(e, typeIt) {
        if (!e) return
        Session.recentEmoji = [e].concat(recent.filter(x => x !== e)).slice(0, 40).join(" ")
        Modal.close()
        Quickshell.execDetached(["bash", "-c", typeIt
            ? 'printf "%s" "$1" | wl-copy; sleep 0.15; wtype "$1"'
            : 'printf "%s" "$1" | wl-copy', "emoji", e])
    }
    function setGroup(g) { group = g; query = ""; input.text = ""; grid.currentIndex = 0 }

    onKeyPressed: e => {
        const shift = e.modifiers & Qt.ShiftModifier
        if (e.key === Qt.Key_Right) grid.moveCurrentIndexRight()
        else if (e.key === Qt.Key_Left) grid.moveCurrentIndexLeft()
        else if (e.key === Qt.Key_Down) grid.moveCurrentIndexDown()
        else if (e.key === Qt.Key_Up) grid.moveCurrentIndexUp()
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.pick(root.current?.[0], !shift)
        else if (e.key === Qt.Key_Tab) setGroup(group + 1 > 9 ? -1 : group + 1)
        else if (e.key === Qt.Key_Backtab) setGroup(group - 1 < -1 ? 9 : group - 1)
        else return
        e.accepted = true
    }
    Connections {
        target: Demo
        function onQueryChanged() { input.text = Demo.query; root.query = Demo.query; grid.currentIndex = 0 }
        function onEmojiGroupChanged() { root.setGroup(Demo.emojiGroup) }
    }

    // поиск
    Rectangle {
        id: field
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
        height: 46
        radius: 14
        color: Theme.weak
        border { width: 1; color: input.activeFocus ? Theme.primary : Theme.strong }
        Text {
            id: lens
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: ""
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 16 }
        }
        TextInput {
            id: input
            anchors { left: lens.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            focus: true
            color: Theme.text
            selectionColor: Theme.primary
            font { family: Theme.font; pixelSize: 16 }
            onTextChanged: { root.query = text; grid.currentIndex = 0 }
            Text {
                visible: !input.text
                text: "Поиск эмодзи (по-английски: fire, heart, cat…)"
                color: Theme.faint
                font: input.font
            }
        }
    }

    // категории
    Row {
        id: tabs
        anchors { top: field.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
        spacing: 2
        Repeater {
            model: root.groups
            Rectangle {
                id: tab
                required property var modelData
                required property int index
                readonly property int g: index - 1
                readonly property bool on: !root.query && root.group === g
                width: 46; height: 38; radius: 12
                color: on ? Theme.strong : tm.containsMouse ? Theme.weak : "transparent"
                border { width: on ? 1 : 0; color: Theme.rim }
                Text {
                    anchors.centerIn: parent
                    text: tab.modelData.icon
                    font { family: "Noto Color Emoji"; pixelSize: 20 }
                    opacity: tab.on || tm.containsMouse ? 1 : 0.55
                }
                Rectangle {
                    visible: tab.on
                    anchors { bottom: parent.bottom; bottomMargin: 3; horizontalCenter: parent.horizontalCenter }
                    width: 14; height: 3; radius: 1.5
                    color: Theme.primary
                }
                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setGroup(tab.g) }
            }
        }
    }

    Text {
        id: sectionTitle
        anchors { top: tabs.bottom; topMargin: 10; left: parent.left; leftMargin: 20 }
        text: root.query ? "Найдено: " + root.shown.length : root.groups[root.group + 1].name
        color: Theme.muted
        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.8 }
    }

    GridView {
        id: grid
        anchors { top: sectionTitle.bottom; topMargin: 8; bottom: footer.top; bottomMargin: 6; left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14 }
        cellWidth: Math.floor(width / 11)
        cellHeight: cellWidth
        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        highlight: Rectangle { radius: 12; color: Theme.strong; border { width: 1; color: Theme.primary } }
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            Text {
                anchors.centerIn: parent
                text: cell.modelData[0]
                font { family: "Noto Color Emoji"; pixelSize: 26 }
            }
            MouseArea {
                id: cm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: grid.currentIndex = cell.index
                onClicked: e => root.pick(cell.modelData[0], e.button === Qt.LeftButton)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: grid.count === 0
            text: root.group < 0 && !root.query ? "Тут появятся недавние эмодзи" : "Ничего не нашлось"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 14 }
        }
    }

    // выбранный: крупно + название
    Rectangle {
        id: footer
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 14 }
        height: 58
        radius: 16
        color: Theme.weak
        border { width: 1; color: Theme.rimSoft }
        Text {
            id: big
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: root.current?.[0] ?? ""
            font { family: "Noto Color Emoji"; pixelSize: 32 }
        }
        Column {
            anchors { left: big.right; leftMargin: 12; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width
                text: root.current?.[1] ? root.current[1].split(" ").slice(0, 6).join(" ") : ""
                elide: Text.ElideRight
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                text: root.current?.[1] ? root.current[1].split(" ").slice(6).join(" ") : ""
                elide: Text.ElideRight
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        Text {
            id: hint
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: "Enter — вставить\nShift+Enter — в буфер"
            horizontalAlignment: Text.AlignRight
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11 }
        }
    }
}
