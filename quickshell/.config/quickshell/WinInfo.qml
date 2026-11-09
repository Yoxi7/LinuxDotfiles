pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Сведения об окне в фокусе: от mango (`mmsg get focusing-client`) и из /proc (процесс).
// Обновляется раз в секунду, пока открыто окно сведений (users > 0).
Singleton {
    id: root

    property int users: 0
    property var client: ({})              // ответ mango
    property var proc: ({})                // { exe, cmd, cwd, rss, cpu, threads, elapsed, state, user }

    function refresh() { if (!reader.running) reader.running = true }

    Timer {
        interval: 1000
        repeat: true
        running: root.users > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        command: ["bash", "-c", `
c=$(mmsg get focusing-client 2>/dev/null)
echo "C $c"
pid=$(printf '%s' "$c" | jq -r '.pid // empty')
if [ -n "$pid" ] && [ -d /proc/$pid ]; then
  echo "E $(readlink /proc/$pid/exe 2>/dev/null)"
  echo "M $(tr '\\0' ' ' </proc/$pid/cmdline 2>/dev/null | cut -c1-300)"
  echo "W $(readlink /proc/$pid/cwd 2>/dev/null)"
  echo "P $(ps -o rss=,pcpu=,nlwp=,etimes=,stat=,user= -p $pid 2>/dev/null)"
fi`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                let c = {}
                for (const line of text.split("\n")) {
                    const k = line.charAt(0), v = line.slice(2)
                    if (k === "C") { try { c = JSON.parse(v) } catch (e) {} }
                    else if (k === "E") o.exe = v
                    else if (k === "M") o.cmd = v.trim()
                    else if (k === "W") o.cwd = v
                    else if (k === "P") {
                        const f = v.trim().split(/\s+/)
                        o.rss = parseInt(f[0]) * 1024; o.cpu = parseFloat(f[1]); o.threads = parseInt(f[2])
                        o.elapsed = parseInt(f[3]); o.state = f[4]; o.user = f[5]
                    }
                }
                root.client = c
                root.proc = o
            }
        }
    }
}
