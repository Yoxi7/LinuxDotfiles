import QtQuick
import Quickshell
import qs

// Уведомления: число в истории, клик — центр уведомлений, ПКМ — «не беспокоить»
Item {
    anchors.verticalCenter: parent?.verticalCenter

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        Text {
            // игра открыта — геймпад: всплывашки выключены
            text: Notifs.gaming ? "\u{f0eb5}" : Session.dnd ? "" : ""
            color: Notifs.gaming ? Theme.primary : Session.dnd ? Theme.faint : Notifs.count > 0 ? Theme.primary : Theme.muted
            font { family: Theme.iconFont; pixelSize: 15 }
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: Notifs.count > 0
            text: Notifs.count
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: e => {
            if (e.button === Qt.RightButton) { Session.dnd = !Session.dnd; return }
            const p = mapToItem(null, width / 2, 0); Modal.toggleAt("notifications", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
