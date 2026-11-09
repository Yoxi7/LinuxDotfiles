pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Раскладка бара: что показывать, в каком порядке и в каких «островах».
// Хранится в bar-layout.json рядом с конфигом; правится из окна «Настроить бар» или вручную (подхватывается на лету).
//   зона — массив id; «+id» — тот же остров, что и предыдущий элемент:
//   { "left": ["tags", "+layout", "title"], "center": ["launcher", "+clock", "+kbd"], "right": ["weather", "media"] }
Singleton {
    id: root

    readonly property string path: Quickshell.shellDir + "/bar-layout.json"
    readonly property var zones: ["left", "center", "right"]
    readonly property var zoneNames: ({ left: "Слева", center: "По центру", right: "Справа" })

    // все элементы, которые умеет бар
    readonly property var catalog: [
        { id: "tags", label: "Рабочие столы", icon: "\uf00a", note: "10 рабочих столов; колесо мыши переключает" },
        { id: "layout", label: "Раскладка окон", icon: "\u{f056e}", note: "плитка, монокль или сетка; число окон" },
        { id: "title", label: "Заголовок окна", icon: "\uf120", note: "клик — сведения об окне" },
        { id: "launcher", label: "Меню приложений", icon: "\uf303", note: "ПКМ — обзор рабочих столов" },
        { id: "clock", label: "Часы", icon: "\uf017", note: "клик — календарь" },
        { id: "kbd", label: "Раскладка клавиатуры", icon: "\uf11c", note: "RU / EN, клик — переключить" },
        { id: "recording", label: "Запись экрана", icon: "\uf03d", note: "только пока идёт запись" },
        { id: "pomodoro", label: "Помодоро", icon: "\u{f051b}", note: "только пока идёт таймер" },
        { id: "weather", label: "Погода", icon: "\u{f0590}", note: "клик — прогноз" },
        { id: "media", label: "Плеер", icon: "\uf001", note: "клик — плеер, колесо — громкость" },
        { id: "stats", label: "CPU / GPU / память", icon: "\uf2db", note: "клик — окно «Система»" },
        { id: "tray", label: "Системный трей", icon: "\uf2d2", note: "значки фоновых приложений" },
        { id: "tuya", label: "Свет (Tuya)", icon: "\u{f0335}", note: "выключатели; ПКМ — выключить всё" },
        { id: "audioswap", label: "Вывод звука", icon: "\uf025", note: "наушники ⇄ колонки одним кликом" },
        { id: "ai", label: "ИИ-помощник", icon: "\u{f0674}", note: "чат с Claude; пульсирует, пока отвечает" },
        { id: "periph", label: "Батареи устройств", icon: "\u{f037d}", note: "заряд мыши, клавиатуры и геймпада" },
        { id: "net", label: "Сеть", icon: "\u{f0200}", note: "проводная / Wi-Fi; клик — окно сети" },
        { id: "bell", label: "Уведомления", icon: "\uf0f3", note: "ПКМ — «не беспокоить»" },
        { id: "status", label: "Статус и звук", icon: "\uf028", note: "сеть, Bluetooth, звук; клик — панель управления" }
    ]
    readonly property var defaults: ({
        primary: {
            left: ["tags", "+layout", "title"],
            center: ["launcher", "+clock", "+kbd"],
            right: ["recording", "pomodoro", "weather", "media", "stats", "periph", "net", "tuya", "audioswap", "ai", "tray", "bell", "status"]
        },
        secondary: { left: ["tags", "title"], center: ["clock"], right: [] }
    })

    property var layout: JSON.parse(JSON.stringify(defaults))
    property var bars: ({})

    function registerBar(screenName, barObj) {
        const m = Object.assign({}, bars)
        m[screenName] = barObj
        bars = m
    }
    function unregisterBar(screenName, barObj) {
        const m = Object.assign({}, bars)
        if (m[screenName] === barObj) { delete m[screenName]; bars = m }
    }
    function widgetCenterX(screenName, id) {
        const b = bars[screenName]
        return b && typeof b.widgetCenterX === "function" ? b.widgetCenterX(id) : -1
    }
    function triggerTray(screenName, query, button) {
        const b = bars[screenName] ?? bars[Theme.primaryMonitor]
        if (b && typeof b.triggerTray === "function") return b.triggerTray(query, button)
        return "err: панель не найдена для монитора " + screenName
    }

    function info(id) { return catalog.find(c => c.id === id) ?? { id: id, label: id, icon: "\uf128", note: "" } }
    function bare(s) { return s.charAt(0) === "+" ? s.slice(1) : s }
    function hasId(id) { return catalog.some(c => c.id === bare(id)) }
    function normScope(scope) { return scope === "secondary" ? "secondary" : "primary" }
    function normZone(zone) { return zones.indexOf(zone) >= 0 ? zone : "right" }

    // острова зоны: [[id, id], …]
    function islands(scope, zone) {
        const out = []
        for (const s of (layout[scope]?.[zone] ?? [])) {
            if (s.charAt(0) === "+" && out.length) out[out.length - 1].push(s.slice(1))
            else out.push([bare(s)])
        }
        return out
    }
    function list(scope, zone) { return layout[scope]?.[zone] ?? [] }
    function used(scope) {
        const out = []
        for (const z of ["left", "center", "right"]) for (const s of list(scope, z)) out.push(bare(s))
        return out
    }
    function pool(scope) { const u = used(scope); return catalog.filter(c => u.indexOf(c.id) < 0) }
    function findWidget(scope, id) {
        const sc = normScope(scope), bid = bare(id ?? "")
        for (const z of zones) {
            const a = list(sc, z)
            for (let i = 0; i < a.length; i++)
                if (bare(a[i]) === bid)
                    return { scope: sc, zone: z, index: i, raw: a[i], joined: a[i].charAt(0) === "+" }
        }
        return null
    }

    // ── правки (из окна настройки и IPC/MCP)
    function commit(scope, zone, arr) {
        const l = JSON.parse(JSON.stringify(layout))
        l[scope] = l[scope] ?? { left: [], center: [], right: [] }
        l[scope][zone] = arr
        // первый элемент зоны не может «присоединяться» к предыдущему
        if (arr.length && arr[0].charAt(0) === "+") arr[0] = arr[0].slice(1)
        layout = l
        save()
    }
    function move(scope, zone, i, d) {
        const a = list(scope, zone).slice(), j = i + d
        if (j < 0 || j >= a.length) return
        // «в одном острове» принадлежит позиции, а не элементу: порядок меняется, острова остаются как были
        const ji = a[i].charAt(0) === "+", jj = a[j].charAt(0) === "+"
        const ei = bare(a[i]), ej = bare(a[j])
        a[i] = (ji ? "+" : "") + ej
        a[j] = (jj ? "+" : "") + ei
        commit(scope, zone, a)
    }
    function toggleJoin(scope, zone, i) {
        if (i === 0) return
        const a = list(scope, zone).slice()
        a[i] = a[i].charAt(0) === "+" ? a[i].slice(1) : "+" + a[i]
        commit(scope, zone, a)
    }
    function remove(scope, zone, i) {
        const a = list(scope, zone).slice()
        a.splice(i, 1)
        // следующий элемент, который «присоединялся» к удалённому, становится началом острова
        if (a[i] && a[i].charAt(0) === "+" && (i === 0 || a[i - 1] === undefined)) a[i] = a[i].slice(1)
        commit(scope, zone, a)
    }
    function moveZone(scope, zone, i, toZone) {
        if (toZone === zone) return
        const id = bare(list(scope, zone)[i])
        remove(scope, zone, i)
        commit(scope, toZone, list(scope, toZone).concat([id]))
    }
    function add(scope, id, zone) { addOrMoveWidget(scope, id, zone, -1, false) }
    function reset(scope) {
        const l = JSON.parse(JSON.stringify(layout))
        if (scope === "all") {
            l.primary = JSON.parse(JSON.stringify(defaults.primary))
            l.secondary = JSON.parse(JSON.stringify(defaults.secondary))
        } else {
            const sc = normScope(scope)
            l[sc] = JSON.parse(JSON.stringify(defaults[sc]))
        }
        layout = l
        save()
    }

    // ── высокоуровневые операции по id виджета для IPC и MCP
    function addOrMoveWidget(scope, id, toZone, index, join) {
        const sc = normScope(scope), z = normZone(toZone), bid = bare(id ?? "")
        if (!hasId(bid)) return "err: неизвестный виджет бара «" + bid + "»"
        const l = JSON.parse(JSON.stringify(layout))
        l[sc] = l[sc] ?? { left: [], center: [], right: [] }
        for (const zn of zones) {
            const a = (l[sc][zn] ?? []).slice()
            for (let i = a.length - 1; i >= 0; i--) {
                if (bare(a[i]) === bid) {
                    a.splice(i, 1)
                    if (a[i] && a[i].charAt(0) === "+" && i === 0) a[i] = a[i].slice(1)
                }
            }
            l[sc][zn] = a
        }
        const target = (l[sc][z] ?? []).slice()
        const pos = (index !== undefined && index >= 0 && index <= target.length) ? index : target.length
        const token = (join && pos > 0 ? "+" : "") + bid
        target.splice(pos, 0, token)
        if (target.length && target[0].charAt(0) === "+") target[0] = target[0].slice(1)
        l[sc][z] = target
        layout = l
        save()
        return "ok: " + bid + " → " + sc + "." + z + "[" + pos + "]" + (token.charAt(0) === "+" ? " (слит с предыдущим)" : "")
    }
    function removeWidget(scope, id) {
        const sc = normScope(scope), bid = bare(id ?? "")
        const f = findWidget(sc, bid)
        if (!f) return "err: виджет «" + bid + "» не размещён на панели (" + sc + ")"
        remove(sc, f.zone, f.index)
        return "ok: убран " + bid + " из " + sc + "." + f.zone
    }
    function moveWidget(scope, id, delta) {
        const sc = normScope(scope), bid = bare(id ?? "")
        const f = findWidget(sc, bid)
        if (!f) return "err: виджет «" + bid + "» не найден на панели (" + sc + ")"
        const a = list(sc, f.zone).slice()
        const d = parseInt(delta) || 0
        const j = Math.max(0, Math.min(a.length - 1, f.index + d))
        if (j === f.index) return "ok: " + bid + " уже на краю зоны " + f.zone
        const step = j > f.index ? 1 : -1
        for (let k = f.index; k !== j; k += step) move(sc, f.zone, k, step)
        return "ok: " + bid + " перемещён в " + sc + "." + f.zone + "[" + j + "]"
    }
    function setWidgetJoin(scope, id, mode) {
        const sc = normScope(scope), bid = bare(id ?? "")
        const f = findWidget(sc, bid)
        if (!f) return "err: виджет «" + bid + "» не найден на панели (" + sc + ")"
        if (f.index === 0) return "err: первый элемент зоны не может быть слит с предыдущим"
        const m = String(mode ?? "toggle").toLowerCase()
        const want = m === "on" || m === "true" || m === "1" ? true : m === "off" || m === "false" || m === "0" ? false : !f.joined
        const a = list(sc, f.zone).slice()
        a[f.index] = (want ? "+" : "") + bid
        commit(sc, f.zone, a)
        return "ok: " + bid + (want ? " объединён с предыдущим островом" : " выделен в отдельный остров")
    }
    function setZoneItems(scope, zone, spec) {
        const sc = normScope(scope), z = normZone(zone)
        let raw = []
        try {
            const parsed = JSON.parse(spec)
            if (Array.isArray(parsed)) raw = parsed.map(String)
        } catch (e) {
            raw = String(spec ?? "").split(/[\s,]+/).filter(Boolean)
        }
        const clean = []
        const seen = new Set()
        for (const tok of raw) {
            const j = tok.charAt(0) === "+"
            const b = bare(tok)
            if (!hasId(b) || seen.has(b)) continue
            seen.add(b)
            clean.push((j && clean.length > 0 ? "+" : "") + b)
        }
        const l = JSON.parse(JSON.stringify(layout))
        l[sc] = l[sc] ?? { left: [], center: [], right: [] }
        for (const other of zones) {
            if (other === z) continue
            const a = (l[sc][other] ?? []).filter(x => !seen.has(bare(x)))
            if (a.length && a[0].charAt(0) === "+") a[0] = a[0].slice(1)
            l[sc][other] = a
        }
        l[sc][z] = clean
        layout = l
        save()
        return "ok: " + sc + "." + z + " = [" + clean.join(", ") + "]"
    }

    // ── файл
    function save() { file.setText(JSON.stringify(layout, null, 2) + "\n") }
    Timer { id: reloadTimer; interval: 120; onTriggered: file.reload() }
    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reloadTimer.restart()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                // поддерживаем только известные элементы; недостающие зоны берём из умолчаний
                const known = new Set(root.catalog.map(c => c.id))
                const out = {}
                for (const sc of ["primary", "secondary"]) {
                    out[sc] = {}
                    for (const z of root.zones) {
                        const src = d[sc]?.[z] ?? root.defaults[sc][z]
                        out[sc][z] = src.filter(s => typeof s === "string" && known.has(root.bare(s)))
                    }
                }
                // то же содержимое — не пересоздаём бар (иначе он мигает при каждом касании файла)
                if (JSON.stringify(out) !== JSON.stringify(root.layout)) root.layout = out
            } catch (e) { /* файл дописывается — оставляем текущую раскладку */ }
        }
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) root.save() }
    }
}
