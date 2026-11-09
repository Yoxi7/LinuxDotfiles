import QtQuick
import Quickshell
import qs

// Кнопка помощника: ЛКМ — окно чата, ПКМ — очистить разговор. Пульсирует, пока помощник отвечает;
// точка — пришёл ответ, пока окно было закрыто.
Item {
    id: root
    implicitWidth: 22
    implicitHeight: 22
    anchors.verticalCenter: parent?.verticalCenter

    Text {
        id: glyph
        anchors.centerIn: parent
        text: "\u{f0674}"
        color: Ai.busy ? Theme.primary : mouse.containsMouse ? Theme.text : Theme.muted
        font { family: Theme.iconFont; pixelSize: 17 }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        SequentialAnimation on opacity {
            running: Ai.busy
            loops: Animation.Infinite
            onRunningChanged: if (!running) glyph.opacity = 1
            NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
        }
    }
    Rectangle {
        visible: Ai.unread > 0
        anchors { right: parent.right; top: parent.top; rightMargin: 1; topMargin: 1 }
        width: 7; height: 7; radius: 3.5
        color: Theme.primary
        border { width: 1; color: Qt.rgba(0, 0, 0, 0.6) }
    }
    Tip { id: tip }
    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -5
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onContainsMouseChanged: tip.request(containsMouse ? root : null, "Помощник · ПКМ — очистить")
        onClicked: e => {
            if (e.button === Qt.RightButton) { Ai.clear(); return }
            Modal.toggleAt("assistant", -1, QsWindow.window?.screen ?? null)
        }
    }
}
