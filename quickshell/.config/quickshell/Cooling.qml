pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Железо и охлаждение через CoolerControl (coolercontrold, 127.0.0.1:11987).
//   показания CPU / GPU / вентиляторов — раз в 2 с (POST /status, только последняя точка)
//   история за 2 минуты — для графиков в окне «Система»
//   профили вентиляторов — GET /profiles; переключение ставит профиль на все каналы,
//   которые уже идут по какому-то профилю (помпа на фиксированных оборотах и неуправляемые не трогаются)
// Токен — в coolercontrol.token рядом (chmod 600); в аргументы curl он не попадает (заголовок из stdin).
// Нет демона или токена — available = false, бар берёт CPU из SysInfo.
Singleton {
    id: root

    readonly property string api: "http://127.0.0.1:11987"
    readonly property string tokenFile: Quickshell.shellDir + "/coolercontrol.token"
    readonly property int historyLength: 60          // 60 × 2 с = 2 минуты

    property bool available: false

    // CPU
    property string cpuName: ""
    property real cpuTemp: 0          // Tctl
    property real cpuCcd: 0           // Tccd1
    property real cpuLoad: 0
    property real cpuPower: 0
    property int cpuFreq: 0           // средняя, МГц
    // GPU
    property string gpuName: ""
    property real gpuTemp: 0
    property real gpuHotspot: 0
    property real gpuLoad: 0
    property real gpuPower: 0
    property int gpuFreq: 0
    property int gpuMemFreq: 0
    property int gpuFanRpm: 0
    // вентиляторы с оборотами: [{ name, label, rpm, duty, profile }]
    property var fans: []

    // история: [{ cpuTemp, cpuLoad, gpuTemp, gpuLoad }]
    property var history: []

    // профили (без «Unmanaged»): [{ uid, name }]; managed — каналы с профилем: [{ device, channel, profile }]
    property var profiles: []
    property var managed: []
    readonly property string currentProfile: {
        const set = [...new Set(managed.map(m => m.profile))]
        return set.length === 1 ? set[0] : ""
    }
    property string switching: ""     // uid профиля, который сейчас ставится

    property var devices: ({})        // uid → { type, name, labels }

    // ── запросы: bash + curl, заголовок авторизации из файла через process substitution
    function curlCmd(method, path, body) {
        return ["bash", "-c",
            'curl -sf --max-time 4 -X "$2" -H @<(printf "Authorization: Bearer %s" "$(cat "$1")") ' +
            '-H "Content-Type: application/json" ${4:+--data "$4"} "$3"',
            "cc", tokenFile, method, api + path, body ?? ""]
    }

    function setProfile(uid) {
        if (managed.length === 0 || switching) return
        switching = uid
        // адреса и тело — позиционными аргументами (в имени канала могут быть пробелы и кавычки)
        const urls = managed.map(m => `${api}/devices/${encodeURIComponent(m.device)}/settings/${encodeURIComponent(m.channel)}/profile`)
        setter.command = ["bash", "-c",
            'tok=$(cat "$1"); body=$(printf \'{"profile_uid":"%s"}\' "$2"); shift 2; ' +
            'for u in "$@"; do curl -sf --max-time 4 -X PUT -H "Authorization: Bearer $tok" -H "Content-Type: application/json" --data "$body" "$u" || exit 1; done',
            "cc", tokenFile, uid].concat(urls)
        setter.running = true
    }

    Process {
        id: setter
        onExited: (code) => {
            if (code !== 0) console.warn("cooling: не удалось сменить профиль, код", code)
            root.switching = ""
            settingsProc.running = true
        }
    }

    // устройства: имена и подписи каналов (раз при старте)
    Process {
        id: devicesProc
        running: true
        command: root.curlCmd("GET", "/devices")
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) { return }
                const m = {}
                for (const x of d.devices ?? []) {
                    const labels = {}
                    for (const [k, v] of Object.entries(x.info?.channels ?? {})) labels[k] = v.label ?? k
                    m[x.uid] = { type: x.type, name: x.name, labels: labels }
                    if (x.type === "CPU") root.cpuName = x.name.replace(/^AMD |^Intel\(R\) Core\(TM\) /, "").replace(/ \d+-Core Processor$/, "")
                    if (x.type === "GPU") root.gpuName = x.name.replace(/^NVIDIA GeForce /, "")
                }
                root.devices = m
                profilesProc.running = true
            }
        }
    }

    Process {
        id: profilesProc
        command: root.curlCmd("GET", "/profiles")
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.profiles = JSON.parse(text).profiles.filter(p => p.uid !== "0").map(p => ({ uid: p.uid, name: p.name }))
                } catch (e) { return }
                settingsProc.running = true
            }
        }
    }

    // какие каналы идут по профилю — по всем устройствам с вентиляторами
    Process {
        id: settingsProc
        command: ["bash", "-c",
            'H="Authorization: Bearer $(cat "$1")"; shift; for u in "$@"; do ' +
            'printf "%s\\t" "$u"; curl -sf --max-time 4 -H "$H" "' + root.api + '/devices/$u/settings"; echo; done',
            "cc", root.tokenFile].concat(Object.keys(root.devices))
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0 || tab === line.length - 1) continue
                    let s = null
                    try { s = JSON.parse(line.slice(tab + 1)) } catch (e) { continue }
                    for (const c of s.settings ?? [])
                        if (c.profile_uid && c.profile_uid !== "0")
                            out.push({ device: line.slice(0, tab), channel: c.channel_name, profile: c.profile_uid })
                }
                root.managed = out
            }
        }
    }

    // показания
    Process {
        id: statusProc
        command: root.curlCmd("POST", "/status", '{"all":false}')
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) {}
                if (!d) { root.available = false; return }
                root.parse(d)
                root.available = true
            }
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!statusProc.running) statusProc.running = true
    }
    // демон перезапускали / первый запуск не удался — перечитать устройства и профили
    Timer {
        interval: 30000; running: !root.available || root.profiles.length === 0; repeat: true
        onTriggered: devicesProc.running = true
    }

    function parse(d) {
        const fans = []
        for (const x of d.devices ?? []) {
            const st = x.status_history?.[x.status_history.length - 1]
            if (!st) continue
            const dev = devices[x.uid] ?? { type: x.type ?? "", labels: {} }
            const temps = st.temps ?? [], channels = st.channels ?? []
            const temp = n => (temps.find(t => t.name === n)?.temp ?? 0)
            const ch = n => channels.find(c => c.name === n) ?? {}
            if (dev.type === "CPU") {
                cpuTemp = temp("temp1"); cpuCcd = temp("temp3")
                cpuLoad = ch("CPU Load").duty ?? 0; cpuPower = ch("power0").watts ?? 0; cpuFreq = ch("CPU Freq Avg").freq ?? 0
            } else if (dev.type === "GPU") {
                gpuTemp = temp("GPU Temp"); gpuHotspot = temp("GPU Temp Hotspot")
                gpuLoad = ch("GPU Load").duty ?? 0; gpuPower = ch("GPU Power").watts ?? 0
                gpuFreq = ch("freq_graphics").freq ?? 0; gpuMemFreq = ch("freq_memory").freq ?? 0
                gpuFanRpm = ch("fan1").rpm ?? 0
            } else {
                // вентиляторы материнки: только реально крутящиеся
                for (const c of channels)
                    if (c.rpm !== undefined && c.rpm > 0) {
                        const m = managed.find(m => m.device === x.uid && m.channel === c.name)
                        fans.push({ name: c.name, label: dev.labels[c.name] ?? c.name, rpm: c.rpm, duty: c.duty ?? 0,
                                    profile: m ? (profiles.find(p => p.uid === m.profile)?.name ?? "") : "" })
                    }
            }
        }
        root.fans = fans
        const h = history.concat([{ cpuTemp: cpuTemp, cpuLoad: cpuLoad, gpuTemp: gpuTemp, gpuLoad: gpuLoad }])
        history = h.length > historyLength ? h.slice(h.length - historyLength) : h
    }
}
