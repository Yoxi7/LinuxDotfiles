import QtQuick
import Quickshell
import qs

// Погода в баре: значок + температура. ЛКМ — подробности, ПКМ — обновить.
Item {
    visible: Weather.loaded
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 7
        anchors.verticalCenter: parent.verticalCenter
        Text {
            text: Weather.icon
            renderType: Text.NativeRendering
            color: Weather.iconColor
            font { family: Theme.iconFont; pixelSize: 16 }
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: Weather.fmt(Weather.temp)
            color: Weather.failed ? Theme.muted : Theme.text
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
            if (e.button === Qt.RightButton) { Weather.update(); return }
            const p = mapToItem(null, width / 2, 0); Modal.toggleAt("weather", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
