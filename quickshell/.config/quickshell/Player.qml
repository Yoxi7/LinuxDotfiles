pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Плеер через cider-ctl: он сам помнит последний активный плеер (Яндекс Музыка / Cider),
// поэтому плеер не указываем. Метаданные — раз в секунду (вызов занимает ~3 мс),
// позиция между опросами досчитывается локально.
Singleton {
    id: root
    readonly property string ctl: Quickshell.env("HOME") + "/.local/bin/cider-ctl"

    property bool available: false
    property string player: ""            // yandex | cider
    property string title: ""
    property string artist: ""
    property string album: ""
    property string art: ""
    property bool playing: false
    property bool liked: false
    property real duration: 0             // секунды
    property real position: 0
    property real volume: 0
    property double stamp: 0              // когда пришла позиция

    readonly property string playerName: player === "yandex" ? "Яндекс Музыка" : player === "cider" ? "Cider" : player
    readonly property string label: !available ? "" : artist && title ? artist + " — " + title : title || artist

    // позиция «сейчас» для прогресс-бара; tick обновляет привязки раз в секунду
    property int tick: 0
    readonly property real livePosition: {
        tick
        const p = position + (playing ? (Date.now() - stamp) / 1000 : 0)
        return duration > 0 ? Math.min(duration, p) : p
    }

    function command(args) {
        Quickshell.execDetached([ctl].concat(args))
        refreshSoon.restart()
    }
    function toggle() { command(["play-pause"]) }
    function toggleLike() {
        liked = !liked
        command(["like", liked ? "on" : "off"])
    }
    function next() { command(["next"]) }
    // перемотка в секунды от начала трека; позиция сразу обновляется локально
    function seek(sec) {
        position = Math.max(0, Math.min(duration, sec))
        stamp = Date.now()
        command(["seek", position.toFixed(1)])
    }
    function previous() { command(["previous"]) }
    // ползунок шлёт значения часто — сам вызов не чаще раза в 80 мс
    function setVolume(v) {
        volume = Math.max(0, Math.min(1, v))
        volSet.restart()
    }
    // osd: true — показать OSD, когда придёт значение (вызов из cider-vol через IPC)
    function refreshVolume(osd) {
        volProc.osd = osd
        volProc.running = true
    }

    Process {
        id: meta
        command: [root.ctl, "metadata"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) {}
                const i = d?.info
                if (!d || d.status !== "ok" || !i) { root.available = false; return }
                root.player = d.player ?? ""
                root.title = i.name ?? ""
                root.artist = i.artistName ?? ""
                root.album = i.albumName ?? ""
                root.art = i.artwork?.url ?? ""
                root.playing = i.isPlaying ?? false
                root.liked = Boolean(i.inFavorites ?? i.isLiked ?? false)
                root.duration = (i.durationInMillis ?? 0) / 1000
                root.position = i.currentPlaybackTime ?? 0
                root.stamp = Date.now()
                root.available = root.title !== "" || root.artist !== ""
            }
        }
    }

    Process {
        id: volProc
        property bool osd: false
        command: [root.ctl, "volume"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text)
                if (isNaN(v)) return
                root.volume = v
                if (volProc.osd) Osd.show("player")
            }
        }
    }

    Timer {
        // идёт музыка — раз в секунду; пауза — реже; плеера нет или игра — совсем редко
        interval: Notifs.gaming ? 8000 : !root.available ? 5000 : root.playing ? 1000 : 3000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { root.tick++; if (!meta.running) meta.running = true }
    }
    Timer { id: volSet; interval: 80; onTriggered: Quickshell.execDetached([root.ctl, "volume", root.volume.toFixed(3)]) }
    Timer { id: refreshSoon; interval: 250; onTriggered: if (!meta.running) meta.running = true }
    Component.onCompleted: refreshVolume(false)
}
