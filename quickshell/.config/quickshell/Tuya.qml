pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Выключатели Tuya по локальной сети. Помощник ~/tuya-local/tuya-bridge.py живёт как дочерний процесс оболочки:
// строки JSON на stdin/stdout, ни веб-сервера, ни systemd-сервиса.
//   → {"cmd":"list"}  ← {"type":"devices","devices":[{id,name,online,switches:[{dp,on}]}]}
//   → {"cmd":"set","id","dp","value"}  ← {"type":"set","ok":bool,"error"}
Singleton {
    id: root
    property var devices: []
    property bool loading: false
    property string error: ""
    property bool watching: false       // панель открыта — опрашиваем раз в 20 секунд
    readonly property int onCount: devices.reduce((a, d) => a + d.switches.filter(s => s.on).length, 0)
    readonly property int total: devices.reduce((a, d) => a + d.switches.length, 0)

    property var pending: []            // команды, пришедшие до запуска помощника
    function send(msg) {
        const line = JSON.stringify(msg) + "\n"
        if (bridge.running) bridge.write(line)
        else { pending = pending.concat([line]); bridge.running = true }
    }

    function refresh() { loading = true; send({ cmd: "list" }) }
    function set(id, dp, value) {
        devices = devices.map(d => d.id !== id ? d : Object.assign({}, d, { switches: d.switches.map(s => s.dp === dp ? { dp: s.dp, on: value } : s) }))
        send({ cmd: "set", id: id, dp: dp, value: value })
    }
    function allOff() {
        for (const d of devices) for (const s of d.switches) if (s.on) set(d.id, s.dp, false)
    }

    Process {
        id: bridge
        command: [Quickshell.env("HOME") + "/tuya-local/.venv/bin/python", Quickshell.env("HOME") + "/tuya-local/tuya-bridge.py"]
        stdinEnabled: true
        onStarted: { for (const l of root.pending) write(l); root.pending = [] }
        onExited: { root.loading = false; restart.start() }
        stdout: SplitParser {
            onRead: line => {
                let m
                try { m = JSON.parse(line) } catch (e) { return }
                if (m.type === "devices") { root.devices = m.devices; root.error = ""; root.loading = false }
                else if (m.type === "set") { if (!m.ok) { root.error = "Не удалось переключить: " + (m.error || "нет ответа"); root.refresh() } }
                else if (m.type === "error") { root.error = m.error; root.loading = false }
            }
        }
    }
    // помощник упал — поднимем при следующем обращении; не крутимся впустую
    Timer { id: restart; interval: 1000 }
    Timer { interval: 20000; repeat: true; running: root.watching; onTriggered: root.refresh() }
    Timer { interval: 300000; repeat: true; running: !root.watching; onTriggered: root.refresh() }
}
