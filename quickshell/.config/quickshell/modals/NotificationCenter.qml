pragma ComponentBehavior: Bound
import QtQuick
import qs

// Центр уведомлений: история по приложениям, «очистить всё», «не беспокоить»
ModalWindow {
    id: root
    name: "notifications"
    dropdown: true
    cardWidth: 420
    cardHeight: Math.min(760, header.height + Math.max(flick.contentHeight, 80) + 44)

    // группы по appName, новые сверху
    readonly property var groups: {
        const map = new Map()
        for (const n of Notifs.history) {
            const k = n.appName || "Уведомления"
            if (!map.has(k)) map.set(k, [])
            map.get(k).push(n)
        }
        return Array.from(map, ([app, items]) => ({ app: app, items: items }))
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        height: 30

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Уведомления"
            color: Theme.text
            font { family: Theme.font; pixelSize: 17; weight: Font.DemiBold }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14
            Text {
                text: Session.dnd ? "  не беспокоить" : "  все"
                color: Session.dnd ? Theme.warning : Theme.muted
                font { family: Theme.iconFont; pixelSize: 12 }
                MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Session.dnd = !Session.dnd }
            }
            Text {
                visible: Notifs.count > 0
                text: "очистить"
                color: clearMouse.containsMouse ? Theme.danger : Theme.muted
                font { family: Theme.font; pixelSize: 12 }
                MouseArea { id: clearMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() }
            }
        }
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 14; topMargin: 10 }
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: flick.width
            spacing: 12

            Repeater {
                model: root.groups
                Column {
                    id: group
                    required property var modelData
                    width: list.width
                    spacing: 6
                    Text {
                        text: group.modelData.app + (group.modelData.items.length > 1 ? "  ·  " + group.modelData.items.length : "")
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                        leftPadding: 4
                    }
                    Repeater {
                        model: group.modelData.items
                        NotifCard {
                            required property var modelData
                            notif: modelData
                            width: group.width
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors { centerIn: flick }
        visible: Notifs.count === 0
        text: "Пусто"
        color: Theme.faint
        font { family: Theme.font; pixelSize: 14 }
    }
}
