import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

Text {
    property real maxWidth: 400
    readonly property var toplevel: ToplevelManager.activeToplevel
    text: toplevel?.title ?? ""
    width: Math.min(implicitWidth, maxWidth)
    elide: Text.ElideRight
    color: Theme.text
    font { family: Theme.font; pixelSize: Theme.fontSize }
    anchors.verticalCenter: parent?.verticalCenter

    // клик — сведения об окне под заголовком
    MouseArea {
        anchors { fill: parent; margins: -6 }
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const p = mapToItem(null, 0, 0)
            Modal.toggleAt("wininfo", p.x + 10 + Math.min(parent.width / 2, 200), QsWindow.window?.screen ?? null)
        }
    }
}
