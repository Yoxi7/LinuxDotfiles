import QtQuick
import qs

// Ползунок 0…1 без QtQuick.Controls: клик / перетаскивание / колесо
Item {
    id: root
    property real value: 0
    property bool dim: false
    signal moved(real v)
    signal released                       // отпустили / прокрутили — для дорогих применений (DDC)
    implicitHeight: 22

    function set(v) { root.moved(Math.max(0, Math.min(1, v))) }

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6
        radius: 3
        color: Theme.strong
        Rectangle {
            width: parent.width * Math.min(1, root.value)
            height: parent.height
            radius: 3
            color: root.dim ? Theme.faint : Theme.primary
        }
    }
    Rectangle {
        x: track.width * Math.min(1, root.value) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 8
        color: Theme.text
        visible: mouse.containsMouse || mouse.pressed
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: e => root.set(e.x / width)
        onPositionChanged: e => { if (pressed) root.set(e.x / width) }
        onReleased: root.released()
        onWheel: w => { root.set(root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05)); root.released() }
    }
}
