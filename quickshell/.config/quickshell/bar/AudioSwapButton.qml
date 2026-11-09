import QtQuick
import Quickshell
import qs

// Кнопка переключения вывода звука: ЛКМ — следующее устройство из отмеченных (наушники ⇄ колонки), ПКМ — окно «Звук».
// Значок показывает, куда звук идёт сейчас.
Item {
    id: root
    implicitWidth: 22
    implicitHeight: 22
    anchors.verticalCenter: parent?.verticalCenter
    readonly property string cur: ((AudioTools.current?.description ?? "") + " " + (AudioTools.current?.name ?? "")).toLowerCase()
    readonly property string icon: /bluez|bluetooth|headset|headphone|наушник|quadro/.test(cur) ? "" : /hdmi|displayport/.test(cur) ? "" : ""

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: mouse.containsMouse ? Theme.text : Theme.muted
        font { family: Theme.iconFont; pixelSize: 15 }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
    }
    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: -3; bottomMargin: -3 }
        text: ""
        color: Theme.primary
        font { family: Theme.iconFont; pixelSize: 8 }
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
            AudioTools.available ? "Сейчас: " + AudioTools.label(AudioTools.current) + "\nКлик — " + AudioTools.label(AudioTools.next) + " · ПКМ — все устройства"
                                 : "Отметьте устройства для переключения: ПКМ — окно «Звук»")
        onClicked: e => {
            if (e.button === Qt.RightButton) Modal.toggleAt("audio", -1, QsWindow.window?.screen ?? null)
            else AudioTools.swap()
        }
    }
}
