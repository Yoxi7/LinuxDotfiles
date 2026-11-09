import QtQuick
import Quickshell
import qs

Text {
    SystemClock { id: clock; precision: SystemClock.Minutes }
    text: clock.date.toLocaleString(Qt.locale("ru_RU"), "ddd d MMM  HH:mm")
    color: Theme.text
    font { family: Theme.font; pixelSize: Theme.fontSize; weight: Font.Medium }
    anchors.verticalCenter: parent?.verticalCenter

    // клик — календарь под часами
    MouseArea {
        anchors { fill: parent; margins: -6 }
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const p = mapToItem(null, parent.width / 2, 0)
            Modal.toggleAt("calendar", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
