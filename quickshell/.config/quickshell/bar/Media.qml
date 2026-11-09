import QtQuick
import Quickshell
import qs

// Текущий трек через cider-ctl (последний активный плеер — Яндекс Музыка / Cider).
// ЛКМ — окно плеера, СКМ — пауза/играть, ПКМ — следующий, колесо — громкость плеера.
Item {
    id: root
    readonly property string label: Player.label.length > 48 ? Player.label.slice(0, 47) + "…" : Player.label
    visible: label !== ""
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 9
        anchors.verticalCenter: parent.verticalCenter

        Cover { size: 22; radius: 6; anchors.verticalCenter: parent.verticalCenter; showPause: true }
        Text {
            text: root.label
            color: Player.playing ? Theme.text : Theme.muted
            font { family: Theme.font; pixelSize: 13 }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: e => {
            if (e.button === Qt.RightButton) Player.next()
            else if (e.button === Qt.MiddleButton) Player.toggle()
            else {
                const p = mapToItem(null, width / 2, 0)
                Modal.toggleAt("player", p.x + 10, QsWindow.window?.screen ?? null)
            }
        }
        onWheel: w => Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/cider-vol", w.angleDelta.y > 0 ? "up" : "down"])
    }
}
