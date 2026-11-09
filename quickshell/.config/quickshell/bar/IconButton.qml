import QtQuick
import qs

Text {
    id: root
    property string icon
    signal clicked
    signal rightClicked

    text: icon
    color: Theme.text
    font { family: Theme.iconFont; pixelSize: 16 }
    anchors.verticalCenter: parent?.verticalCenter
    opacity: mouse.containsMouse ? 0.75 : 1

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
