pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs

// Быстрое переключение вывода звука по кругу между отмеченными устройствами (наушники ⇄ колонки).
// Устройства отмечаются в окне «Звук» (кнопка ⇄ на строке); хранятся по имени узла PipeWire (Session.audioCycle).
// Если ничего не отмечено — переключается по всем доступным устройствам вывода.
Singleton {
    id: root
    readonly property var marked: { try { return JSON.parse(Session.audioCycle) } catch (e) { return [] } }
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    PwObjectTracker { objects: root.sinks }
    readonly property var cycle: { const m = sinks.filter(n => marked.indexOf(n.name) >= 0); return m.length >= 2 ? m : (marked.length === 0 ? sinks : m) }
    readonly property var current: Pipewire.defaultAudioSink
    readonly property bool available: cycle.length >= 2
    readonly property var next: {
        if (cycle.length < 2) return null
        const i = cycle.indexOf(current)
        return cycle[(i + 1) % cycle.length]
    }
    function isMarked(n) { return marked.indexOf(n.name) >= 0 }
    function toggleMark(n) {
        const m = marked.slice()
        const i = m.indexOf(n.name)
        if (i >= 0) m.splice(i, 1); else m.push(n.name)
        Session.audioCycle = JSON.stringify(m)
    }
    function label(n) { return n?.description || n?.nickname || n?.name || "?" }
    function swap() {
        const to = next
        if (!to) { Quickshell.execDetached(["notify-send", "-a", "Звук", "Нечего переключать", "Отметьте минимум два устройства вывода в окне «Звук» (кнопка ⇄ на строке)"]); return }
        Pipewire.preferredDefaultAudioSink = to
        Quickshell.execDetached(["notify-send", "-a", "Звук", "-h", "string:x-canonical-private-synchronous:audio-swap", "Вывод звука", label(to)])
    }
}
