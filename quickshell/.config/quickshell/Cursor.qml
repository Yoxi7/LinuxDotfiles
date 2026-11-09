pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Глобальная позиция курсора (координаты раскладки mango) — для «гироскопа» стекла:
// блики на кромках поворачиваются к курсору, как в iOS к наклону телефона.
// Ни mango, ни Hyprland не шлют событий о курсоре, поэтому опрос: 20 раз/с, пока мышь двигается,
// 4 раза/с, когда стоит. Во время игры (окно игры открыто) опрос выключен.
Singleton {
    id: root
    property real x: -1
    property real y: -1
    readonly property bool active: Mango.isMango && (!Notifs.gaming || Demo.active)
    property int still: 0                   // сколько опросов подряд курсор стоял
    signal moved

    function setPos(px, py) {
        still = 0
        x = px
        y = py
        moved()
    }

    function apply(text) {
        let p = null
        try { p = JSON.parse(text) } catch (e) { return }
        if (Math.abs(p.x - root.x) < 0.5 && Math.abs(p.y - root.y) < 0.5) { root.still++; return }
        root.still = 0
        root.x = p.x
        root.y = p.y
        root.moved()
    }

    // mango: короткий процесс mmsg
    Process {
        id: poll
        command: ["mmsg", "get", "cursorpos"]
        stdout: StdioCollector { onStreamFinished: root.apply(text) }
    }

    // Hyprland: запрос прямо в его командный сокет (то же, что делает hyprctl), без запуска процессов:
    // ~0,015 мс на запрос против ~25 мс на hyprctl
    property string reply: ""
    Socket {
        id: hypr
        path: Mango.isHypr ? Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock" : ""
        parser: SplitParser { onRead: line => root.reply += line }
        onConnectedChanged: {
            if (connected) { root.reply = ""; write("j/cursorpos"); flush() }
            else if (root.reply !== "") { const r = root.reply; root.reply = ""; root.apply(r) }
        }
    }
    Timer {
        running: root.active
        repeat: true
        interval: root.still > 10 ? 250 : 50
        onTriggered: {
            if (Mango.isHypr) { if (!hypr.connected) hypr.connected = true }
            else if (!poll.running) poll.running = true
        }
    }
}
