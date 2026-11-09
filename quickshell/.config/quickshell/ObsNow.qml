pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// «Сейчас играет» для OBS: пишет ~/obs-music/now.js (его читает ~/obs-music/index.html — браузерный источник OBS).
// Обложка копируется в ~/obs-music/cover.img, потому что плеер отдаёт временный файл. Пишем при смене трека/паузе и раз в 4 секунды (позиция).
Singleton {
    id: root
    readonly property string dir: Quickshell.env("HOME") + "/obs-music"
    property int coverVer: 0
    property string coverUrl: ""

    readonly property string key: Player.title + "|" + Player.artist + "|" + Player.art
    onKeyChanged: syncCover()

    function syncCover() {
        const a = Player.art
        if (a.indexOf("file://") === 0) { copier.src = decodeURIComponent(a.slice(7)); copier.running = true }
        else { coverUrl = a; write() }
    }
    Process {
        id: copier
        property string src: ""
        command: ["cp", "-f", src, root.dir + "/cover.img"]
        onExited: { root.coverVer++; root.coverUrl = "cover.img?v=" + root.coverVer; root.write() }
    }

    function write() {
        const o = { available: Player.available, playing: Player.playing, title: Player.title, artist: Player.artist, album: Player.album,
                    cover: coverUrl, duration: Player.duration, position: Player.livePosition, at: Date.now() }
        file.setText("window.NOW = " + JSON.stringify(o) + ";\n")
    }
    FileView { id: file; path: root.dir + "/now.js" }

    Connections { target: Player; function onPlayingChanged() { root.write() } function onAvailableChanged() { root.write() } }
    Timer { interval: 4000; repeat: true; running: Player.available; onTriggered: root.write() }
}
