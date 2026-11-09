import QtQuick
import Quickshell
import qs

// Идёт помодоро: оставшееся время; клик — органайзер в пункте управления
Item {
    id: root
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f051b}"
            color: Theme.primary
            font { family: Theme.iconFont; pixelSize: 14 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Pomodoro.label
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
        }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Session.ccTab = 1
            const p = mapToItem(null, width / 2, 0)
            Modal.toggleAt("control", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
