import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs

// Громкость системы: колесо — ±5%, СКМ — mute, ПКМ — окно выбора звуковых устройств
Item {
    id: root
    anchors.verticalCenter: parent?.verticalCenter
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real volume: sink?.audio?.volume ?? 0

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        Text {
            text: root.muted ? "" : root.volume > 0.5 ? "" : root.volume > 0 ? "" : ""
            color: root.muted ? Theme.faint : Theme.text
            font { family: Theme.iconFont; pixelSize: 16 }
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: Math.round(root.volume * 100) + "%"
            color: root.muted ? Theme.faint : Theme.text
            font { family: Theme.font; pixelSize: 13 }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        // ЛКМ уходит острову (быстрые настройки), СКМ — mute
        acceptedButtons: Qt.MiddleButton | Qt.RightButton
        onClicked: e => {
            if (e.button === Qt.RightButton) Modal.toggleAt("audio", -1, QsWindow.window?.screen ?? null)
            else if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
        }
        onWheel: w => {
            if (!root.sink?.audio) return
            const v = root.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05)
            root.sink.audio.volume = Math.max(0, Math.min(1, v))
        }
    }
}
