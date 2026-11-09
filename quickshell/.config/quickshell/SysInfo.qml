pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU / RAM / температура CPU раз в 5 с: один короткий `cat`, без демонов
Singleton {
    id: root
    property int cpu: 0
    property int mem: 0
    property int temp: 0
    property real memUsed: 0               // ГиБ
    property real memTotal: 0
    property string tempFile: ""
    property var last: null

    // датчик k10temp (Tctl): номер hwmon меняется между загрузками — ищем по имени
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = k10temp ] && echo $h/temp1_input && break; done"]
        stdout: StdioCollector { onStreamFinished: root.tempFile = text.trim() }
    }

    // чтение /proc прямо из процесса оболочки (FileView) — без запуска sh/grep/cat
    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
        onLoaded: {
            const c = text().split("\n")[0].split(/\s+/).slice(1).map(Number)
            const idle = c[3] + c[4], total = c.reduce((a, b) => a + b, 0)
            if (root.last) {
                const dt = total - root.last.total
                if (dt > 0) root.cpu = Math.round(100 * (1 - (idle - root.last.idle) / dt))
            }
            root.last = { idle: idle, total: total }
        }
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
        printErrors: false
        onLoaded: {
            const t = text()
            const kb = k => Number((t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")) || [0, 0])[1])
            const tot = kb("MemTotal"), avail = kb("MemAvailable")
            if (tot) {
                root.mem = Math.round(100 * (1 - avail / tot))
                root.memUsed = (tot - avail) / 1048576
                root.memTotal = tot / 1048576
            }
        }
    }
    FileView {
        id: tempF
        path: root.tempFile
        blockLoading: true
        printErrors: false
        onLoaded: { const t = Number(text()); if (t) root.temp = Math.round(t / 1000) }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { statFile.reload(); memFile.reload(); if (root.tempFile) tempF.reload() }
    }

}
