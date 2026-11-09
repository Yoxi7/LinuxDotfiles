pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Группы обоев: набор папок и файлов, мониторы и таймер. По таймеру группа сама меняет обои на своих мониторах
// (случайно / по списку / по дате). Работает, пока запущена оболочка. Хранится в ~/.local/state/qs-lite-wallgroups.json.
//   группа: { id, name, outputs: ["DP-3", …] (пусто — все), sources: [папка | файл], order: random|name|date,
//             interval: минуты, enabled, pos: сколько уже показано, next: когда менять (мс), last: путь последней }
Singleton {
    id: root

    property var groups: []
    property var assign: ({})                  // монитор → id группы: у монитора выбирается группа, а не наоборот
    readonly property string home: Quickshell.env("HOME")
    readonly property string stateFile: home + "/.local/state/qs-lite-wallgroups.json"
    readonly property var intervals: [{ m: 1, label: "1 мин" }, { m: 5, label: "5 мин" }, { m: 15, label: "15 мин" }, { m: 30, label: "30 мин" },
                                      { m: 60, label: "1 час" }, { m: 180, label: "3 часа" }, { m: 720, label: "12 часов" }, { m: 1440, label: "Сутки" }]
    readonly property var orders: [{ id: "random", label: "Случайно" }, { id: "name", label: "По имени" }, { id: "date", label: "Сначала новые" }]

    function uid() { return Date.now().toString(36) + Math.floor(Math.random() * 46656).toString(36) }
    function save() { file.setText(JSON.stringify({ groups: groups, assign: assign })) }
    function byId(id) { return groups.find(g => g.id === id) ?? null }
    function commit(list) { groups = list; save() }

    function create(name, outputs, sources) {
        const g = { id: uid(), name: name || "Группа " + (groups.length + 1), sources: sources ?? [], order: "random", interval: 30,
                    enabled: true, pos: 0, next: Date.now() + 30 * 60000, last: "" }
        groups = groups.concat([g])
        if (outputs && outputs.length) for (const m of outputs) setMonitor(m, g.id)
        save()
        return g.id
    }
    function patch(id, p) {
        commit(groups.map(g => {
            if (g.id !== id) return g
            const n = Object.assign({}, g, p)
            if (p.interval !== undefined || (p.enabled === true && !g.enabled)) n.next = Date.now() + n.interval * 60000
            return n
        }))
    }
    function remove(id) {
        const a = Object.assign({}, assign)
        for (const m in a) if (a[m] === id) delete a[m]
        assign = a
        commit(groups.filter(g => g.id !== id))
    }
    // выбрать группу монитору ("" — монитор не участвует); таймер группы не сбрасывается
    function setMonitor(mon, gid) {
        const a = Object.assign({}, assign)
        if (gid === "") delete a[mon]; else a[mon] = gid
        assign = a
        save()
    }
    function monitorsOf(id) { return Object.keys(assign).filter(m => assign[m] === id) }
    function addSource(id, path) {
        const g = byId(id)
        if (g && g.sources.indexOf(path) < 0) patch(id, { sources: g.sources.concat([path]) })
    }
    function removeSource(id, path) { const g = byId(id); if (g) patch(id, { sources: g.sources.filter(s => s !== path) }) }
    function isBusy() { return scan.running }
    function secondsLeft(g) { return Math.max(0, Math.round((g.next - Date.now()) / 1000)) }

    // ── смена обоев
    // поставить конкретную картинку на мониторы группы (настройки показа — из пикера)
    function applyTo(g, pick) {
        if (monitorsOf(g.id).length === 0) return            // группа без мониторов ничего не меняет
        const a = [root.home + "/.local/bin/wallpick", "--anim", Session.wallAnim, "--resize", Session.wallResize]
        if (Session.wallResize === "crop") a.push("--gravity", Session.wallGravity)
        if (Session.wallResize === "fit" || Session.wallResize === "no") a.push("--fill", Session.wallFill + "ff")
        a.push("--outputs", monitorsOf(g.id).join(","))
        a.push(pick)
        Quickshell.execDetached(a)
    }
    function applyNow(id, path) {
        const g = byId(id); if (!g) return
        applyTo(g, path)
        commit(groups.map(x => x.id === id ? Object.assign({}, x, { last: path, next: Date.now() + x.interval * 60000 }) : x))
    }
    property var queue: []
    function rotate(id) { if (queue.indexOf(id) < 0) queue = queue.concat([id]); pump() }
    function pump() {
        if (scan.running || queue.length === 0) return
        const g = byId(queue[0]); queue = queue.slice(1)
        if (!g) { pump(); return }
        scan.gid = g.id
        // файлы из папок (на один уровень) + отдельные файлы; «время изменения \t путь»
        scan.command = ["bash", "-c",
            'for s in "$@"; do if [ -d "$s" ]; then find -L "$s" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.bmp" -o -iname "*.gif" \\) -printf "%T@\\t%p\\n"; ' +
            'elif [ -f "$s" ]; then printf "%s\\t%s\\n" "$(stat -c %Y "$s")" "$s"; fi; done'].concat(["bash"], g.sources)
        scan.running = true
    }
    Process {
        id: scan
        property string gid: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const g = root.byId(scan.gid)
                if (!g) return
                let files = text.split("\n").filter(l => l).map(l => { const i = l.indexOf("\t"); return { t: Number(l.slice(0, i)), p: l.slice(i + 1) } })
                const seen = {}
                files = files.filter(f => seen[f.p] ? false : (seen[f.p] = true))
                if (files.length === 0) { root.patch(g.id, { next: Date.now() + g.interval * 60000 }); return }
                let pick
                if (g.order === "random") {
                    const pool = files.length > 1 ? files.filter(f => f.p !== g.last) : files
                    pick = pool[Math.floor(Math.random() * pool.length)].p
                } else {
                    files.sort(g.order === "date" ? (a, b) => b.t - a.t || (a.p < b.p ? -1 : 1) : (a, b) => a.p.toLowerCase() < b.p.toLowerCase() ? -1 : 1)
                    pick = files[g.pos % files.length].p
                }
                root.applyTo(g, pick)
                root.commit(root.groups.map(x => x.id === g.id ? Object.assign({}, x, { pos: x.pos + 1, last: pick, next: Date.now() + x.interval * 60000 }) : x))
            }
        }
        onExited: root.pump()
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: {
            for (const g of root.groups) if (g.enabled && g.sources.length && monitorsOf(g.id).length && g.next <= Date.now()) root.rotate(g.id)
        }
    }

    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.groups = (d.groups ?? []).map(g => Object.assign({ sources: [], order: "random", interval: 30, enabled: true, pos: 0, next: 0, last: "" }, g))
                const a = d.assign ?? {}
                if (!d.assign) {                       // старый формат: у группы были мониторы — переносим к мониторам (пусто = все)
                    const all = Quickshell.screens.map(x => x.name)
                    for (const g of root.groups) for (const m of (g.outputs?.length ? g.outputs : all)) if (!a[m]) a[m] = g.id
                }
                root.assign = a
            } catch (e) {}
        }
    }
}
