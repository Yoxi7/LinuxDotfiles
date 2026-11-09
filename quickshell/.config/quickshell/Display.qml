pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Яркость мониторов по DDC/CI (ddcutil) и ночной свет (wlsunset).
//
// Важно: на NVIDIA каждый обмен по DDC/I2C подвешивает вывод изображения (~200–500 мс фриза mango).
// Поэтому ddcutil зовём как можно реже:
//   • список мониторов и последние значения — в ~/.cache/qs-lite/ddc.json; при открытии меню DDC не трогаем;
//   • пока тянут ползунок — меняется только интерфейс; на монитор уходит одна команда после отпускания
//     (commit) и только для изменившихся мониторов, в ускоренном режиме (--noverify, --sleep-multiplier);
//   • detect / чтение — только если кэша нет или запись не удалась.
Singleton {
    id: root

    property var monitors: []              // [{ bus, model, output }]
    property var values: ({})              // шина → 0…100
    property var sent: ({})                // шина → значение, которое уже на мониторе
    readonly property real average: {
        const v = monitors.map(m => values[m.bus]).filter(x => x !== undefined)
        return v.length ? v.reduce((a, b) => a + b, 0) / v.length / 100 : 0
    }
    readonly property bool busy: sender.running || detect.running || reader.running

    // имена выходов mango по модели монитора (DDC знает модель, а не разъём)
    readonly property var outputs: ({ "OLED G27P6": "DP-3", "VG279QM": "DP-1", "Q32G1WG4": "DP-2" })

    // интерфейс: значение меняется сразу, на монитор — только в commit()
    function set(bus, v) {
        const vals = Object.assign({}, values)
        vals[bus] = Math.round(Math.max(0, Math.min(1, v)) * 100)
        values = vals
    }
    function setAll(v) {
        const vals = Object.assign({}, values)
        for (const m of monitors) vals[m.bus] = Math.round(Math.max(0, Math.min(1, v)) * 100)
        values = vals
    }
    function commit() { if (!sender.running) flush() }

    function flush() {
        const buses = monitors.map(m => String(m.bus)).filter(b => values[b] !== undefined && values[b] !== sent[b])
        if (!buses.length) return
        const s = Object.assign({}, sent)
        for (const b of buses) s[b] = values[b]
        sent = s
        sender.command = ["bash", "-c",
            'fail=0; while [ $# -gt 0 ]; do ddcutil --bus "$1" setvcp 10 "$2" --noverify --sleep-multiplier 0.1 >/dev/null 2>&1 || fail=1; shift 2; done; exit $fail', "wr"]
            .concat(...buses.map(b => [b, String(values[b])]))
        sender.running = true
    }
    Process {
        id: sender
        onExited: code => {
            if (code !== 0) { root.save(); detect.running = true; return }   // шины сменились — найти заново
            root.save()
            root.flush()                                                     // пока писали, двинули ещё
        }
    }

    // ── кэш
    readonly property string cachePath: Quickshell.env("HOME") + "/.cache/qs-lite/ddc.json"
    function save() { cache.setText(JSON.stringify({ monitors: monitors, values: sent }) + "\n") }
    FileView {
        id: cache
        path: root.cachePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.monitors = d.monitors ?? []
                root.sent = d.values ?? ({})
                root.values = Object.assign({}, root.sent)
            } catch (e) {}
            if (!root.monitors.length || Object.keys(root.sent).length < root.monitors.length) detect.running = true
        }
        onLoadFailed: detect.running = true
    }

    // ── поиск мониторов и чтение (редко: только без кэша или после ошибки)
    Process {
        id: detect
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const mons = []
                let cur = null
                for (const line of text.split("\n")) {
                    const b = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(line)
                    if (b) { cur = { bus: parseInt(b[1]), model: "", output: "" }; mons.push(cur); continue }
                    const m = /Monitor:\s+[^:]*:([^:]+):/.exec(line)
                    if (m && cur) { cur.model = m[1].trim(); cur.output = root.outputs[cur.model] ?? "" }
                }
                root.monitors = mons.sort((a, b) => (b.output === "DP-3") - (a.output === "DP-3"))
                if (mons.length) reader.running = true
            }
        }
    }
    Process {
        id: reader
        command: ["bash", "-c", 'for b in "$@"; do echo "$b $(ddcutil --bus "$b" getvcp 10 --brief 2>/dev/null)"; done', "rd"]
                 .concat(root.monitors.map(m => String(m.bus)))
        stdout: StdioCollector {
            onStreamFinished: {
                const vals = Object.assign({}, root.values), s = Object.assign({}, root.sent)
                for (const line of text.split("\n")) {
                    const m = /^(\d+) VCP 10 C (\d+) (\d+)/.exec(line)
                    if (!m) continue
                    s[m[1]] = vals[m[1]] = Math.round(parseInt(m[2]) * 100 / Math.max(1, parseInt(m[3])))
                }
                root.values = vals
                root.sent = s
                root.save()
            }
        }
    }

    // ── ночной свет: тёплая температура постоянно (день и ночь почти равны)
    readonly property bool nightLight: Session.nightLight
    function setNightLight(on) { Session.nightLight = on }
    function setNightTemp(t) { Session.nightTemp = Math.round(t / 100) * 100 }
    Process {
        id: sunset
        running: Session.nightLight
        // Hyprland: родной hyprsunset (цветовая матрица композитора), иначе wlsunset
        command: Mango.isHypr ? ["hyprsunset", "-t", String(Session.nightTemp)]
                              : ["wlsunset", "-t", String(Session.nightTemp), "-T", String(Session.nightTemp + 1),
                                 "-S", "06:00", "-s", "18:00", "-d", "60"]
    }
    // температуру меняют ползунком — перезапуск после паузы
    Connections {
        target: Session
        function onNightTempChanged() { if (Session.nightLight) restartSunset.restart() }
    }
    Timer { id: restartSunset; interval: 400; onTriggered: { sunset.running = false; sunset.running = true } }
    // процесс прошлой сессии оболочки мог остаться сиротой (ppid 1) и держать жёлтый экран при выключенном свете — гасим
    Component.onCompleted: if (!Session.nightLight) strayKill.running = true
    Process { id: strayKill; command: ["sh", "-c", "pkill -x hyprsunset; pkill -x wlsunset; true"] }
}
