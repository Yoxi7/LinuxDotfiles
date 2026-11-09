pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs

// Лаунчер: DesktopEntries (без парсинга .desktop руками), ↑/↓ — выбор, Enter — запуск
ModalWindow {
    id: root
    name: "launcher"
    cardWidth: 560
    cardHeight: 520

    property string query: ""
    readonly property var apps: {
        const q = query.trim().toLowerCase()
        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay)
        if (q === "")
            return all.slice().sort((a, b) => a.name.localeCompare(b.name))
        const scored = []
        for (const a of all) {
            const name = a.name.toLowerCase()
            let s = name.startsWith(q) ? 0
                : name.split(/\s+/).some(w => w.startsWith(q)) ? 1
                : name.includes(q) ? 2
                : (a.genericName ?? "").toLowerCase().includes(q) ? 3
                : a.keywords.some(k => k.toLowerCase().includes(q)) ? 4
                // по имени программы: «wdisplays» найдёт «Displays»
                : (a.id ?? "").toLowerCase().includes(q) || (a.execString ?? "").toLowerCase().includes(q) ? 5
                : (a.comment ?? "").toLowerCase().includes(q) ? 6
                : -1
            if (s >= 0) scored.push([s, a])
        }
        return scored.sort((x, y) => x[0] - y[0] || x[1].name.localeCompare(y[1].name)).map(x => x[1])
    }

    function launch(entry) {
        if (!entry) return
        Modal.close()
        entry.execute()
    }

    onKeyPressed: e => {
        if (e.key === Qt.Key_Down) { list.incrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Up) { list.decrementCurrentIndex(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { launch(apps[list.currentIndex]); e.accepted = true }
    }
    Connections {
        target: Demo
        function onQueryChanged() { input.text = Demo.query; root.query = Demo.query; list.currentIndex = 0 }
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
            id: glass
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: ""
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 16 }
        }
        TextInput {
            id: input
            anchors { left: glass.right; leftMargin: 12; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            focus: true
            color: Theme.text
            selectionColor: Theme.primary
            font { family: Theme.font; pixelSize: 16 }
            onTextChanged: { root.query = text; list.currentIndex = 0 }

            Text {
                visible: !input.text
                text: "Приложения…"
                color: Theme.faint
                font: input.font
            }
        }
    }

    ListView {
        id: list
        anchors { top: field.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 10 }
        clip: true
        model: root.apps
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        highlight: Rectangle { radius: 12; color: Theme.strong }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: 52

            IconImage {
                id: appIcon
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                implicitSize: 32
                asynchronous: true
                source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
            }
            Column {
                anchors { left: appIcon.right; leftMargin: 14; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width
                    text: row.modelData.name
                    elide: Text.ElideRight
                    color: row.ListView.isCurrentItem ? Theme.primary : Theme.text
                    font { family: Theme.font; pixelSize: 15; weight: Font.Medium }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.modelData.genericName || row.modelData.comment || ""
                    elide: Text.ElideRight
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: list.currentIndex = row.index
                onClicked: root.launch(row.modelData)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "Ничего не найдено"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 14 }
        }
    }
}
