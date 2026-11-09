pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Кто сейчас использует микрофон, экран и камеру — по потокам PipeWire.
//   mic    — потоки записи звука (Stream/Input/Audio)
//   screen — потоки, читающие видео не с камеры (демонстрация экрана, запись)
//   camera — потоки видео с ролью «Camera»
// Элемент: { name, pid, binary, detail }
Singleton {
    id: root

    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream)
    readonly property var micNodes: streams.filter(n => n.type === PwNodeType.AudioInStream)
    readonly property var videoNodes: streams.filter(n => (n.type & PwNodeType.VideoSink) === PwNodeType.VideoSink)

    PwObjectTracker { objects: root.micNodes.concat(root.videoNodes) }

    function info(n) {
        const p = n.properties ?? {}
        // имя клиента часто служебное («WEBRTC VoiceEngine», «Chromium input») — тогда берём имя программы
        const raw = p["application.name"] || p["node.name"] || n.description || n.name || "?"
        const bin = p["application.process.binary"] || ""
        const generic = /voiceengine|chromium|chrome|electron|alsa|pipewire|pulse|audio stream|^node$/i.test(raw)
        return {
            name: generic && bin ? bin.replace(/^./, c => c.toUpperCase()) : raw,
            pid: parseInt(p["application.process.id"]) || 0,
            binary: p["application.process.binary"] || "",
            detail: p["media.name"] || "",
            role: p["media.role"] || ""
        }
    }
    function unique(list) {
        const seen = new Set(), out = []
        for (const i of list) {
            const k = i.name + ":" + i.pid
            if (!seen.has(k)) { seen.add(k); out.push(i) }
        }
        return out
    }

    readonly property var mic: unique(micNodes.map(info))
    readonly property var screen: unique(videoNodes.map(info).filter(i => i.role !== "Camera"))
    readonly property var camera: unique(videoNodes.map(info).filter(i => i.role === "Camera"))
    readonly property int count: mic.length + screen.length + camera.length
}
