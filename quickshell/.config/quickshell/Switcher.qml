pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Alt+Tab: окна всех мониторов в порядке последнего фокуса (MRU).
// mango: ALT,Tab → ipc switcher next; ALT+SHIFT,Tab → prev. Выбор подтверждает отпускание Alt
// (его ловит окно переключателя — у него клавиатура), Enter или клик; Esc — отмена.
Singleton {
    id: root

    property bool open: false
    property string monitor: ""       // где показывать — монитор окна в фокусе
    property bool shown: false        // окно уже есть (держит клавиатуру), но прозрачное, пока снимаются превью
    property int index: 0
    property var items: []            // клиенты mango в порядке MRU
    property var mru: []              // id окон, последний фокус — первым
    property real stamp: 0            // обновились превью
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-overview"
    property var procs: ({})          // pid → { cmd, args, cwd, idle } для окон терминалов
    readonly property var termRe: /alacritty|kitty|foot|wezterm|konsole|ghostty|xterm|terminal|scratch-term/i
    property int pendingStep: 0       // нажали ещё раз, пока список грузится

    function next() { step(1) }
    function prev() { step(-1) }
    function step(d) {
        if (open) {
            if (items.length) index = (index + d + items.length) % items.length
            return
        }
        if (loader.running) { pendingStep += d; return }
        pendingStep = d
        loader.running = true
    }
    function commit() {
        if (!open) return
        const c = items[index]
        open = false
        shown = false
        if (c) Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + c.id])
    }
    function cancel() { open = false; shown = false }

    // список окон на момент открытия
    Process {
        id: loader
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let cl = []
                try { cl = JSON.parse(text).clients } catch (e) { return }
                cl = cl.filter(c => c.tags.length > 0 || c.is_minimized)
                const rank = id => { const i = root.mru.indexOf(id); return i < 0 ? 1e6 + id : i }
                cl.sort((a, b) => (b.is_focused - a.is_focused) || (rank(a.id) - rank(b.id)))
                root.items = cl
                root.monitor = (Demo.active && Demo.screenName !== "") ? Demo.screenName : (cl.find(c => c.is_focused)?.monitor ?? cl[0]?.monitor ?? "")
                if (!cl.length) return
                root.index = ((root.pendingStep > 0 ? 1 : -1) + cl.length) % cl.length
                if (cl.length === 1) root.index = 0
                root.shown = false
                root.open = true
                showTimer.restart()
                // превью видимых окон (кэш общий с обзором тегов); окно переключателя пока прозрачное,
                // поэтому в снимки не попадает
                const vis = cl.filter(c => c.is_visible && !c.is_minimized && c.width > 0)
                thumbs.command = ["bash", "-c", 'mkdir -p "$1"; ' +
                    vis.map(c => `grim -s 0.3 -g "${c.x},${c.y} ${c.width}x${c.height}" "$1/${c.id}.png" &`).join(" ") + " wait",
                    "thumbs", root.thumbDir]
                thumbs.running = true
                // что запущено в терминалах
                const pids = cl.filter(c => root.termRe.test(c.appid) && c.pid > 0).map(c => String(c.pid))
                root.procs = ({})
                if (pids.length) { procLoader.command = [Quickshell.env("HOME") + "/.local/bin/qs-procs"].concat(pids); procLoader.running = true }
            }
        }
    }
    Process {
        id: procLoader
        stdout: StdioCollector {
            onStreamFinished: { try { root.procs = JSON.parse(text) } catch (e) {} }
        }
    }
    Process {
        id: thumbs
        onExited: { root.stamp = Date.now(); root.shown = true }
    }
    Timer { id: showTimer; interval: 350; onTriggered: root.shown = true }

    // история фокуса
    Process {
        id: watcher
        running: Mango.isMango
        command: ["mmsg", "watch", "focusing-client"]
        stdout: SplitParser {
            onRead: line => {
                let c = null
                try { c = JSON.parse(line) } catch (e) { return }
                if (!c || !c.id) return
                root.mru = [c.id].concat(root.mru.filter(x => x !== c.id)).slice(0, 100)
            }
        }
        onExited: if (Mango.isMango) restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: watcher.running = true }
}
