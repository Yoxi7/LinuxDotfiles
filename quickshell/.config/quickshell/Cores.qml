pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Каждое ядро (как в htop): загрузка, частота, температура — прямо из ядра Linux, без утилит:
//   /proc/stat                                        — загрузка (разница тиков между опросами)
//   /sys/devices/system/cpu/cpuN/cpufreq/cpuinfo_avg_freq — реальная средняя частота (APERF/MPERF)
//   k10temp в /sys/class/hwmon                         — Tctl и Tccd (у AMD нет датчика на каждое ядро)
// Опрос раз в 100 мс и только пока блок с ядрами на экране (users > 0).
// Загрузка в /proc/stat идёт тиками по 10 мс — за 100 мс это шаг 10 %, поэтому сглаживаем (EMA).
Singleton {
    id: root

    property int users: 0                 // сколько блоков сейчас показывают ядра
    readonly property bool active: users > 0

    property int count: 0
    property var load: []                 // 0…1, сглаженная
    property var freq: []                 // МГц
    property real tctl: 0
    property real tccd: 0
    readonly property real avgLoad: load.length ? load.reduce((a, b) => a + b, 0) / load.length : 0
    readonly property real maxFreq: freq.length ? Math.max(...freq) : 0

    property var prev: []                 // [idle, total] по ядрам с прошлого опроса
    property string hwmon: ""             // каталог k10temp

    Timer {
        interval: 100
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            stat.reload()
            for (let i = 0; i < freqFiles.count; i++) freqFiles.objectAt(i)?.reload()
            if (root.hwmon) { t1.reload(); t3.reload() }
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        blockLoading: true
        printErrors: false
        onLoaded: {
            const lines = text().split("\n").filter(l => /^cpu\d+ /.test(l))
            const next = [], load = root.load.slice()
            for (let i = 0; i < lines.length; i++) {
                const f = lines[i].split(/\s+/).slice(1).map(Number)
                const idle = f[3] + (f[4] || 0), total = f.slice(0, 8).reduce((a, b) => a + b, 0)
                next.push([idle, total])
                const p = root.prev[i]
                if (p && total > p[1]) {
                    const v = 1 - (idle - p[0]) / (total - p[1])
                    load[i] = load[i] === undefined ? v : load[i] * 0.55 + v * 0.45
                }
            }
            root.prev = next
            root.load = load
            if (root.count !== lines.length) root.count = lines.length
        }
    }

    Instantiator {
        id: freqFiles
        model: root.count
        delegate: FileView {
            required property int index
            path: "/sys/devices/system/cpu/cpu" + index + "/cpufreq/cpuinfo_avg_freq"
            printErrors: false
            onLoaded: {
                const f = root.freq.slice()
                f[index] = parseInt(text()) / 1000
                root.freq = f
            }
        }
    }

    // каталог k10temp (номер hwmon меняется от загрузки к загрузке)
    Process {
        running: true
        command: ["bash", "-c", "dirname \"$(grep -l '^k10temp$' /sys/class/hwmon/*/name | head -n 1)\""]
        stdout: StdioCollector { onStreamFinished: root.hwmon = text.trim() === "." ? "" : text.trim() }
    }
    FileView { id: t1; path: root.hwmon ? root.hwmon + "/temp1_input" : ""; printErrors: false; onLoaded: root.tctl = parseInt(text()) / 1000 }
    FileView { id: t3; path: root.hwmon ? root.hwmon + "/temp3_input" : ""; printErrors: false; onLoaded: root.tccd = parseInt(text()) / 1000 }
}
