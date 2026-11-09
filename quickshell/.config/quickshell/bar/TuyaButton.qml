import QtQuick
import Quickshell
import qs

// Выключатели Tuya: ЛКМ — панель, ПКМ — выключить всё. Значок ярче, пока что-то включено.
Item {
    id: root
    implicitWidth: 22
    implicitHeight: 22
    anchors.verticalCenter: parent?.verticalCenter

    Text {
        anchors.centerIn: parent
        text: "\u{f0335}"
        color: Tuya.onCount > 0 ? Theme.primary : mouse.containsMouse ? Theme.text : Theme.muted
        font { family: Theme.iconFont; pixelSize: 16 }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
    }
    Rectangle {
        visible: Tuya.onCount > 0
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -2; bottomMargin: -2 }
        width: 7; height: 7; radius: 4
        color: Theme.primary
    }
    Tip { id: tip }
    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -5
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onContainsMouseChanged: tip.request(containsMouse ? root : null,
            Tuya.error !== "" && Tuya.total === 0 ? Tuya.error
            : "Свет: включено " + Tuya.onCount + " из " + Tuya.total + "\nКлик — панель · ПКМ — выключить всё")
        onClicked: e => {
            if (e.button === Qt.RightButton) Tuya.allOff()
            else Modal.toggleAt("tuya", -1, QsWindow.window?.screen ?? null)
        }
    }
}
