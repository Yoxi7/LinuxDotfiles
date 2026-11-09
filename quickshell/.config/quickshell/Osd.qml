pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// OSD: сам ловит изменения громкости/mute в PipeWire — хоть от бинда (wpctl),
// хоть от колеса в баре, хоть из pavucontrol. Окно OSD живёт только 1.5 с.
// Громкость плеера (Яндекс Музыка / Cider) меняет cider-vol, он же дёргает
// `qs -c lite ipc call osd player` — у плеера своя громкость, PipeWire её не видит.
Singleton {
    id: root
    property bool visible: false          // окно существует
    property bool shown: false            // окно видно (уходит плавно, потом разгружается)
    property string kind: "volume"        // volume | mic | player
    property bool ready: false            // не показывать OSD при старте

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real value: kind === "player" ? Player.volume : kind === "mic" ? (source?.audio?.volume ?? 0) : (sink?.audio?.volume ?? 0)
    readonly property bool muted: kind === "player" ? false : kind === "mic" ? (source?.audio?.muted ?? false) : (sink?.audio?.muted ?? false)

    function show(k) {
        if (!ready) return
        kind = k
        gone.stop()
        visible = true
        shown = true
        hide.restart()
    }

    PwObjectTracker { objects: [root.sink, root.source].filter(x => x) }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.show("volume") }
        function onMutedChanged() { root.show("volume") }
    }
    Connections {
        target: root.source?.audio ?? null
        function onMutedChanged() { root.show("mic") }
    }
    Timer { id: hide; interval: 1500; onTriggered: { root.shown = false; gone.restart() } }
    Timer { id: gone; interval: Theme.dExit + 40; onTriggered: root.visible = false }
    Timer { interval: 2000; running: true; onTriggered: root.ready = true }
}
