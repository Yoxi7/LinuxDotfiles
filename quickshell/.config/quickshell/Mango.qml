pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Раскладка клавиатуры из mango: один `mmsg watch` на все бары
Singleton {
    id: root
    // только в сессии mango (в niri mmsg нет — не крутим перезапуски впустую)
    // Hyprland: команда mmsg — наша прослойка (~/.local/bin/mmsg), отдаёт те же JSON из hyprctl
    readonly property bool isHypr: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    readonly property bool isMango: isHypr || (Quickshell.env("MANGO_INSTANCE_SIGNATURE") ?? "") !== ""
                                    || (Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").startsWith("mango")
    // у каждого монитора свои 10 столов: DP-3 → 1–10, DP-1 → 11–20, DP-2 → 21–30, HDMI-A-1 (мини) → 31–40 (~/.config/hypr/conf/ws.lua)
    readonly property var wsBase: ({ "DP-3": 0, "DP-1": 10, "DP-2": 20, "HDMI-A-1": 30 })
    function view(monitorName, n) {
        if (isHypr) Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + ((wsBase[monitorName] ?? 0) + n) + " })"])
        else Quickshell.execDetached(["mmsg", "dispatch", "view," + n + ",0"])
    }
    property string layout: ""
    // OSD раскладки: показывается при смене (не при старте) на ~0.9 с
    property bool osd: false              // окно существует
    property bool osdShown: false         // окно видно (уходит плавно)
    property bool started: false
    function showOsd(): void {
        osdGone.stop()
        osd = true
        osdShown = true
        osdHide.restart()
    }
    onLayoutChanged: {
        if (!started) { started = true; return }
        showOsd()
    }
    readonly property string layoutName: {
        const l = layout.toLowerCase()
        if (l.startsWith("russian")) return "Русская"
        if (l.startsWith("english")) return "English"
        return layout
    }
    readonly property string layoutShort: {
        const l = layout.toLowerCase()
        if (l.startsWith("russian")) return "RU"
        if (l.startsWith("english")) return "EN"
        return layout.slice(0, 2).toUpperCase()
    }

    // мониторы mango: имя → { layout (имя раскладки), symbol, tag, count (окон на теге) }
    property var monitors: ({})
    readonly property var layoutNames: ({ T: "tile", S: "scroller", G: "grid", M: "monocle", K: "deck", CT: "center_tile",
        RT: "right_tile", VS: "vertical_scroller", VT: "vertical_tile", VG: "vertical_grid", VK: "vertical_deck",
        DW: "dwindle", F: "fair", VF: "vertical_fair" })
    Process {
        id: monWatch
        running: root.isMango
        command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser {
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                const m = {}
                for (const x of d.monitors ?? []) {
                    const tag = x.active_tags?.[0] ?? 1
                    m[x.name] = { layout: root.layoutNames[x.layout_symbol] ?? x.layout_symbol, symbol: x.layout_symbol,
                                  tag: tag, count: x.tags?.find(t => t.index === tag)?.client_count ?? 0,
                                  counts: (x.tags ?? []).map(t => t.client_count) }
                }
                root.monitors = m
            }
        }
        onExited: if (root.isMango) monRestart.start()
    }
    Timer { id: monRestart; interval: 2000; onTriggered: monWatch.running = true }

    function switchLayout(): void {
        Quickshell.execDetached(["mmsg", "dispatch", "switch_keyboard_layout"])
    }

    Process {
        id: watcher
        running: root.isMango
        command: ["mmsg", "watch", "keyboardlayout"]
        stdout: SplitParser {
            onRead: line => {
                try { root.layout = JSON.parse(line).layout } catch (e) {}
            }
        }
        // mango перезапустился / mmsg упал — переподключаемся
        onExited: if (root.isMango) restart.start()
    }
    Timer { id: osdHide; interval: 900; onTriggered: { root.osdShown = false; osdGone.restart() } }
    Timer { id: osdGone; interval: Theme.dExit + 40; onTriggered: root.osd = false }
    Timer {
        id: restart
        interval: 2000
        onTriggered: watcher.running = true
    }
}
