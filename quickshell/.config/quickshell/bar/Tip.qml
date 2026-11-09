import QtQuick
import Quickshell
import qs

// Подсказка под элементом бара: показывается через 450 мс наведения, клики не мешает.
//   Tip { id: tip }  …  tip.request(item, "текст") при наведении, tip.request(null) — убрать
PopupWindow {
    id: tip
    property Item target: null
    property string text: ""
    property bool shown: false

    function request(item, text) {
        if (!item) { delay.stop(); shown = false; return }
        target = item
        tip.text = text
        if (!shown) delay.restart()
    }
    Timer { id: delay; interval: 450; onTriggered: tip.shown = true }

    anchor.item: target
    anchor.rect.x: target ? target.width / 2 - width / 2 : 0
    anchor.rect.y: target ? target.height + 14 : 0
    implicitWidth: label.implicitWidth + 24
    implicitHeight: label.implicitHeight + 14
    visible: shown && target !== null && text !== ""
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Qt.rgba(0.05, 0.05, 0.07, 0.94)
        border { width: 1; color: Theme.border }
        Text {
            id: label
            anchors.centerIn: parent
            text: tip.text
            color: Theme.text
            lineHeight: 1.15
            font { family: Theme.font; pixelSize: 12 }
        }
    }
}
