pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Widgets
import qs

// Пикер обоев с файловым менеджером:
//   слева — закреплённые папки, места, недавние; сверху — назад/вперёд/вверх, путь по сегментам, звезда (закрепить),
//   поиск (просто печатай), размер превью, сортировка.
//   Enter — поставить / открыть папку, Backspace — стереть поиск или вверх, Alt+←/→ — история, Ctrl+D — закрепить,
//   ЛКМ по картинке — просмотр, ПКМ — сразу поставить; ПКМ по папке — закрепить / открепить.
// Превью — из кэша wallpick (если файл в его корне), иначе оригинал в размере превью; cache: false — RAM не копится.
ModalWindow {
    id: root
    name: "wallpapers"
    cardWidth: 1560
    resizable: true
    minW: 900
    minH: 600
    cardHeight: 940

    readonly property string home: Quickshell.env("HOME")
    readonly property string base: home + "/Изображения/Wallpapers"      // корень кэша превью wallpick
    readonly property string thumbs: home + "/.cache/wallpick"
    readonly property var zooms: [{ w: 176, h: 112 }, { w: 252, h: 160 }, { w: 352, h: 216 }, { w: 520, h: 320 }, { w: 780, h: 470 }]

    function zoomBy(d) { Session.wallZoom = Math.max(0, Math.min(4, Session.wallZoom + d)) }
    property string dir: Session.wallDir || (home + "/Pictures")
    property string query: ""
    property var back: []
    property var fwd: []
    property var places: []                 // [{ path, label, icon }] — существующие

    // ───────── просмотр: ЛКМ по картинке — увеличенный, внутри кнопки «Установить» / «Сохранить»
    property var preview: null            // { online, name, index, path | thumb+url+provider+id, w, h, rating, size, full }
    readonly property bool previewOpen: preview !== null
    captureEscape: sortMenuOpen || groupPath !== "" || helpOpen || triage || previewOpen || source !== "" || query !== ""

    function openLocalPreview(i) {
        if (i < 0 || i >= folder.count || folder.get(i, "fileIsDir")) return
        preview = { online: false, index: i, path: folder.get(i, "filePath"), name: folder.get(i, "fileName"),
                    size: folder.get(i, "fileSize") }
        grid.currentIndex = i
    }
    function openOnlinePreview(i) {
        if (i < 0 || i >= resultsModel.count) return
        const r = resultsModel.get(i)
        preview = { online: true, index: i, thumb: r.thumb, url: r.url, provider: r.provider, id: r.id, w: r.w, h: r.h,
                    rating: r.rating, name: r.provider + " #" + r.id, full: "" }
        onlineCurrent = i
        ensureVisible(i)
        fullProc.command = [Quickshell.env("HOME") + "/.local/bin/wall-online", "preview", r.provider, r.id, r.url]
        fullProc.running = false
        fullProc.running = true
        if (i >= resultsModel.count - 6) more()              // листаем к концу — подгружаем следующие
    }
    function stepPreview(d) {
        if (!preview) return
        if (preview.online) { openOnlinePreview(Math.max(0, Math.min(resultsModel.count - 1, preview.index + d))); return }
        let i = preview.index + d
        while (i >= 0 && i < folder.count && folder.get(i, "fileIsDir")) i += d
        if (i >= 0 && i < folder.count) openLocalPreview(i)
    }
    function previewApply() {
        if (!preview) return
        if (preview.online) fetchItem({ id: preview.id, provider: preview.provider, url: preview.url }, true)
        else apply(preview.path, preview.name)
    }
    function previewSave() {
        if (preview?.online) fetchItem({ id: preview.id, provider: preview.provider, url: preview.url }, false)
    }
    // апскейл (upscayl-ncnn на видеокарте): локальный файл или онлайн-картинка → ~/Pictures/wp/upscaled
    property string upModel: "upscayl-standard-4x"
    readonly property var upModels: [["Универсальная", "upscayl-standard-4x"], ["Аниме / арт", "digital-art-4x"],
        ["Чёткая", "ultrasharp-4x"], ["Максимум деталей", "high-fidelity-4x"]]
    property bool upApply: true
    readonly property bool upBusy: upProc.running
    function upscale(apply) {
        if (!preview || upProc.running) return
        upApply = apply
        const p = preview
        // онлайн: сначала скачать оригинал, потом апскейл
        const h = Quickshell.env("HOME")
        const script = p.online
            ? 'src=$(' + h + '/.local/bin/wall-online get "$1" "$2" "$3" | python3 -c "import sys,json;print(json.load(sys.stdin).get(\'path\',\'\'))"); ' + h + '/.local/bin/wall-upscale "$4" "$src" "$5"'
            : h + '/.local/bin/wall-upscale "$4" "$3" "$5"'
        const target = String(Math.max(...Quickshell.screens.map(s => s.width * (s.devicePixelRatio || 1))))
        upProc.label = p.name
        upProc.command = ["bash", "-c", script, "up", p.provider ?? "", p.id ?? "", p.online ? p.url : p.path, upModel, target]
        upProc.running = true
    }
    Process {
        id: upProc
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text.trim().split("\n").pop()) } catch (e) {}
                if (!d || !d.path) { root.error = d?.error || "Апскейл не удался"; root.toast(root.error); return }
                if (root.upApply) root.apply(d.path, "апскейл")
                else root.toast("Апскейл сохранён в ~/Pictures/wp/upscaled")
            }
        }
    }
    Process {
        id: fullProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.path && root.preview?.online) root.preview = Object.assign({}, root.preview, { full: d.path })
                } catch (e) {}
            }
        }
    }

    // текущие обои мониторов (awww query): имя выхода → путь
    property var currentWalls: ({})
    function refreshWalls() { if (!wallsProc.running) wallsProc.running = true }
    Process {
        id: wallsProc
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const line of text.split("\n")) {
                    const r = /^: ([^:]+): .*image: (.+)$/.exec(line.trim().replace(/^:?\s*/, ": "))
                    if (r) m[r[1]] = r[2].trim()
                }
                root.currentWalls = m
            }
        }
    }
    Component.onCompleted: refreshWalls()
    Timer { id: wallsRefresh; interval: 1600; onTriggered: root.refreshWalls() }
    // выбранные мониторы: пусто — все
    function targetsHas(name) { return Session.wallOutputs === "" || Session.wallOutputs.split(",").indexOf(name) >= 0 }
    function toggleTarget(name) {
        const all = Quickshell.screens.map(s => s.name)
        let cur = Session.wallOutputs === "" ? all.slice() : Session.wallOutputs.split(",").filter(n => all.indexOf(n) >= 0)
        const i = cur.indexOf(name)
        if (i >= 0) { if (cur.length > 1) cur.splice(i, 1) } else cur.push(name)
        cur = all.filter(n => cur.indexOf(n) >= 0)
        Session.wallOutputs = cur.length === all.length ? "" : cur.join(",")
    }
    function onlyTarget(name) { Session.wallOutputs = name }

    // раскладка онлайн-ленты «кирпичиками»: колонки, картинки в исходных пропорциях
    property int onlineCurrent: -1
    property var colHeights: []
    property real masonryHeight: 0
    readonly property real masonryW: onlineFlick.width
    readonly property int mCols: Math.max(1, Math.floor(masonryW / [210, 290, 400, 580, 840][Session.wallZoom]))
    readonly property real mColW: masonryW / mCols
    function tileHeight(w, h) {
        const aspect = Session.wallAspect ? Math.max(0.45, Math.min(2.4, (w || 16) / (h || 9))) : 1.6
        return Math.round((mColW - 10) / aspect + 10)
    }
    function place(item) {                      // к самой короткой колонке
        let c = 0
        for (let i = 1; i < colHeights.length; i++) if (colHeights[i] < colHeights[c]) c = i
        const ph = tileHeight(item.w, item.h)
        const out = { px: c * mColW, py: colHeights[c], pw: mColW, ph: ph }
        colHeights[c] += ph
        masonryHeight = Math.max(...colHeights)
        return out
    }
    function layoutAll() {
        colHeights = new Array(mCols).fill(0)
        for (let i = 0; i < resultsModel.count; i++) {
            const o = place(resultsModel.get(i))
            resultsModel.set(i, Object.assign({}, resultsModel.get(i), o))
        }
        masonryHeight = colHeights.length ? Math.max(...colHeights) : 0
    }
    onMColsChanged: Qt.callLater(layoutAll)
    onMColWChanged: Qt.callLater(layoutAll)
    Connections { target: Session; function onWallAspectChanged() { Qt.callLater(root.layoutAll) } }
    function ensureVisible(i) {
        if (i < 0 || i >= resultsModel.count) return
        const r = resultsModel.get(i)
        if (r.py < onlineFlick.contentY) onlineFlick.contentY = Math.max(0, r.py - 8)
        else if (r.py + r.ph > onlineFlick.contentY + onlineFlick.height)
            onlineFlick.contentY = Math.min(masonryHeight - onlineFlick.height, r.py + r.ph - onlineFlick.height + 8)
    }

    // онлайн-библиотека (wall-online): "" — локальные папки
    property string source: ""
    ListModel { id: resultsModel }          // { id, provider, thumb, url, w, h, rating } — дописывается без сброса прокрутки
    readonly property int resultCount: resultsModel.count
    property var seenIds: ({})
    property string seed: ""                // порядок «случайных» не меняется между страницами
    property bool exhausted: false          // источник больше ничего не даёт
    property bool loading: false
    property string error: ""
    property int page: 1
    property string lastQuery: ""
    readonly property var sources: [
        { id: "wallhaven", label: "Wallhaven", icon: "\uf03e" },
        { id: "konachan", label: "Konachan", icon: "\uf03e" },
        { id: "yandere", label: "Yande.re", icon: "\uf03e" },
        { id: "danbooru", label: "Danbooru", icon: "\uf03e" }
    ]
    readonly property bool hasKey: keyFile.text().trim() !== ""
    readonly property var sorts: [{ id: "random", label: "Случайные" }, { id: "new", label: "Новые" }, { id: "top", label: "Лучшие" }]

    FileView {
        id: keyFile
        path: Quickshell.shellDir + "/wallhaven.key"
        blockLoading: true
        printErrors: false
    }
    function toggleRating(r) {
        let cur = Session.wallRatings.split("")
        const i = cur.indexOf(r)
        if (i >= 0) { if (cur.length > 1) cur.splice(i, 1) } else cur.push(r)
        Session.wallRatings = "sqe".split("").filter(c => cur.indexOf(c) >= 0).join("")
        search(true)
    }
    function openSource(id) {
        source = id
        query = ""
        clearResults()
        error = ""
        search(true)
    }
    // поиск идёт по очереди: новый запрос не убивает текущий, а ждёт его (иначе выдача терялась)
    property bool searchQueued: false
    property bool queuedReset: false
    function search(reset) {
        if (!source) return
        if (searchProc.running) { searchQueued = true; queuedReset = queuedReset || reset; return }
        runSearch(reset)
    }
    function runSearch(reset) {
        if (reset) {
            page = 1
            exhausted = false
            seed = Math.random().toString(36).slice(2, 10)
            clearResults()
        }
        error = ""
        loading = true
        lastQuery = query
        searchProc.command = [Quickshell.env("HOME") + "/.local/bin/wall-online", "search", source, query, String(page),
                              Session.wallRatings, Session.wallOnSort, "1920x1080", root.seed, Session.wallRatio]
        searchProc.running = true
    }
    function clearResults() { resultsModel.clear(); seenIds = ({}); colHeights = new Array(mCols).fill(0); masonryHeight = 0; onlineCurrent = -1 }
    // подгрузка вперёд: когда до конца осталось меньше двух экранов-рядов; страниц не больше 20
    function more() {
        if (loading || exhausted || resultCount === 0 || page >= 20) return
        page++
        search(false)
    }
    // скачать: apply=true — сразу поставить на рабочий стол, иначе только сохранить в ~/Pictures/wp/online
    // ── очередь загрузок: можно тыкать ПКМ по десяткам обоев подряд — качаются по три параллельно
    property var dlBusy: ({})                // id → "save" | "apply": в очереди или качается
    property var dlDone: ({})                // id → true: сохранено (до закрытия окна)
    property var dlQueue: []                 // [{ id, provider, url, apply, label }]
    property int dlActive: 0
    readonly property int dlPending: dlQueue.length + dlActive
    property int dlTotal: 0                  // сколько поставили в очередь за серию — для счётчика
    function fetchItem(item, apply) {
        if (dlBusy[item.id] || dlDone[item.id] && !apply) return
        const b = Object.assign({}, dlBusy); b[item.id] = apply ? "apply" : "save"; dlBusy = b
        const job = { id: item.id, provider: item.provider, url: item.url, apply: apply, label: item.provider + " #" + item.id }
        dlQueue = apply ? [job].concat(dlQueue) : dlQueue.concat([job])      // «Установить» — вне очереди
        dlTotal++
        pumpDl()
    }
    function pumpDl() {
        for (let i = 0; i < dlWorkers.count && dlQueue.length > 0; i++) {
            const w = dlWorkers.objectAt(i)
            if (w && !w.running) { const job = dlQueue[0]; dlQueue = dlQueue.slice(1); dlActive++; w.start(job) }
        }
    }
    function dlFinished(job, path, error) {
        dlActive--
        const b = Object.assign({}, dlBusy); delete b[job.id]; dlBusy = b
        if (path) {
            const d = Object.assign({}, dlDone); d[job.id] = true; dlDone = d
            if (job.apply) apply(path, job.label)
        } else error = error || "Не удалось скачать " + job.label
        if (error) { root.error = error }
        if (dlPending === 0) { dlTotal = 0; if (!error) toast("Сохранено в ~/Pictures/wp/online") }
        pumpDl()
    }
    Instantiator {
        id: dlWorkers
        model: 3
        delegate: Process {
            id: w
            property var job: null
            function start(j) { job = j; command = [Quickshell.env("HOME") + "/.local/bin/wall-online", "get", j.provider, j.id, j.url]; running = true }
            stdout: StdioCollector {
                onStreamFinished: {
                    let d = null
                    try { d = JSON.parse(text) } catch (e) {}
                    const j = w.job; w.job = null
                    root.dlFinished(j, d?.path ?? "", d?.error ?? "")
                }
            }
            onExited: code => { if (w.job) { const j = w.job; w.job = null; root.dlFinished(j, "", "") } }      // упал, ничего не напечатав
        }
        onObjectAdded: root.pumpDl()
    }
    Process {
        id: searchProc
        property int got: 0
        stdout: SplitParser {
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.item) {
                    // картинки появляются по мере готовности превью
                    if (!root.seenIds[d.item.id]) {
                        root.seenIds[d.item.id] = true
                        if (root.colHeights.length !== root.mCols) root.colHeights = new Array(root.mCols).fill(0)
                        resultsModel.append(Object.assign({}, d.item, root.place(d.item)))
                        searchProc.got++
                    }
                } else if (d.error) {
                    root.error = d.error
                }
            }
        }
        stderr: StdioCollector { id: searchErr }
        onStarted: got = 0
        onExited: code => {
            root.loading = false
            if (searchProc.got === 0 && code === 0 && root.resultCount > 0) root.exhausted = true   // страница ничего нового не дала
            if (root.resultCount === 0 && !root.error)
                root.error = code !== 0 ? "Источник не ответил" + (searchErr.text.trim() ? ": " + searchErr.text.trim().split("\n").pop().slice(0, 140) : "")
                                        : "Ничего не нашлось"
            if (root.searchQueued) {
                root.searchQueued = false
                const r = root.queuedReset
                root.queuedReset = false
                root.runSearch(r)
            }
        }
    }
    readonly property var pins: { try { return JSON.parse(Session.wallPins) } catch (e) { return [] } }
    readonly property var recent: { try { return JSON.parse(Session.wallRecent) } catch (e) { return [] } }
    readonly property bool pinned: pins.indexOf(dir) >= 0
    readonly property var crumbs: {
        const parts = dir.split("/").filter(p => p)
        const out = [{ name: "/", path: "/" }]
        let acc = ""
        for (const p of parts) { acc += "/" + p; out.push({ name: p, path: acc }) }
        // внутри дома — начинаем с «~»
        const hi = out.findIndex(c => c.path === home)
        return hi >= 0 ? [{ name: "~", path: home }].concat(out.slice(hi + 1)) : out
    }

    function leaf(p) { return p === home ? "~" : p === "/" ? "/" : p.slice(p.lastIndexOf("/") + 1) }
    function setDir(path) {
        dir = path
        Session.wallDir = path
        query = ""
        grid.currentIndex = 0
        const r = recent.filter(x => x !== path)
        r.unshift(path)
        Session.wallRecent = JSON.stringify(r.slice(0, 8))
    }
    function go(path) {
        if (!path || path === dir) return
        back = back.concat([dir]); fwd = []
        setDir(path)
    }
    function goBack() { if (!back.length) return; const p = back[back.length - 1]; back = back.slice(0, -1); fwd = fwd.concat([dir]); setDir(p) }
    function goFwd() { if (!fwd.length) return; const p = fwd[fwd.length - 1]; fwd = fwd.slice(0, -1); back = back.concat([dir]); setDir(p) }
    function up() { if (dir !== "/") go(dir.slice(0, dir.lastIndexOf("/")) || "/") }
    function togglePin(path) {
        const p = pins.slice(), i = p.indexOf(path)
        if (i >= 0) p.splice(i, 1); else p.push(path)
        Session.wallPins = JSON.stringify(p)
    }
    // параметры показа: как обои ложатся на экран и на какие мониторы
    function applyArgs(path) {
        const a = [Quickshell.env("HOME") + "/.local/bin/wallpick", "--anim", Session.wallAnim, "--resize", Session.wallResize]
        if (Session.wallResize === "crop") a.push("--gravity", Session.wallGravity)
        if (Session.wallResize === "fit" || Session.wallResize === "no") a.push("--fill", Session.wallFill + "ff")
        if (Session.wallOutputs) a.push("--outputs", Session.wallOutputs)
        a.push(path)
        return a
    }
    // меню остаётся открытым: можно ставить и скачивать дальше
    property string toastText: ""
    function toast(t) { toastText = t; toastTimer.restart() }
    Timer { id: toastTimer; interval: 2200; onTriggered: root.toastText = "" }
    // установка: если обоина меньше целевого монитора — сначала апскейл на лету (Session.wallAutoUp)
    function targetWidth() {
        const sel = Session.wallOutputs === "" ? null : Session.wallOutputs.split(",")
        let w = 0
        for (const sc of Quickshell.screens) if (!sel || sel.indexOf(sc.name) >= 0) w = Math.max(w, sc.width * (sc.devicePixelRatio || 1))
        return w || 2560
    }
    Process {
        id: autoUp
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text.trim().split("\n").pop()) } catch (e) {}
                root.upWorking = false
                if (!d || !d.path) { root.toast("Апскейл не удался — ставлю как есть"); root.doApply(autoUp.src, autoUp.label); return }
                root.doApply(d.path, autoUp.label + (d.skipped ? "" : " (апскейл)"))
            }
        }
        property string src: ""
    }
    property bool upWorking: false
    function apply(path, label) {
        if (!Session.wallAutoUp || autoUp.running) { doApply(path, label); return }
        upWorking = true
        toast("Проверяю размер…")
        autoUp.src = path
        autoUp.label = label ?? ""
        autoUp.command = [Quickshell.env("HOME") + "/.local/bin/wall-upscale", upModel, path, String(targetWidth()), "soft"]
        autoUp.running = true
    }
    function doApply(path, label) {
        Quickshell.execDetached(applyArgs(path))
        toast("Поставлено" + (Session.wallOutputs ? " на " + Session.wallOutputs.replace(/,/g, ", ") : "") + (label ? ": " + label : ""))
        wallsRefresh.restart()
    }
    function activate(item) { if (!item) return; item.isDir ? go(item.path) : apply(item.path, item.fileName) }
    function thumbOf(path) {
        return path.startsWith(base + "/") ? "file://" + thumbs + "/" + path.slice(base.length + 1).replace(/\//g, "_") + ".png" : ""
    }



    // ── куда можно переносить: «Избранное», подпапки корня сортировки, закреплённые
    readonly property string sortRoot: Session.wallSortRoot || home + "/Pictures/wp"
    FolderListModel {
        id: sortFolder
        folder: "file://" + root.sortRoot
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }
    readonly property var targets: {
        const out = [{ path: triKeep, label: "Избранное" }], seen = {}
        seen[triKeep] = true
        for (let i = 0; i < sortFolder.count; i++) {
            const pth = sortFolder.get(i, "filePath")
            if (seen[pth] || pth === triDir || pth === home + "/Pictures/wp/upscaled") continue
            seen[pth] = true
            out.push({ path: pth, label: sortFolder.get(i, "fileName") })
        }
        for (const pth of pins) if (!seen[pth]) { seen[pth] = true; out.push({ path: pth, label: leaf(pth) }) }
        return out
    }
    function newFolderPath(name) { return sortRoot + "/" + name.trim().replace(/\//g, "_") }

    // ── разбор скачанного: по одной картинке — оставить / в корзину / в закреплённую папку
    property bool helpOpen: false
    property int triSel: 0
    property bool triNaming: false
    signal triEnsure
    function triActivate(i) {
        if (i === 0) triMove(triKeep)
        else if (i === 1) triMove("trash")
        else if (i === 2) { if (triItem) apply(triItem.path, triItem.name) }
        else if (i === 3) triSkip()
        else if (i === 4) triBack()
        else if (i - 5 < targets.length) triMove(targets[i - 5].path)
    }
    property bool triage: false
    property int triPos: 0                         // сколько пропущено (картинка под номером triPos)
    property var triUndo: []                       // [{ name, from, to, trash }]
    readonly property string triDir: home + "/Pictures/wp/online"
    readonly property string triKeep: home + "/Pictures/wp/Избранное"
    readonly property var triItem: triFolder.count > triPos ? { path: triFolder.get(triPos, "filePath"), name: triFolder.get(triPos, "fileName") } : null
    FolderListModel {
        id: triFolder
        folder: root.triage ? "file://" + root.triDir : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.jfif", "*.png", "*.webp", "*.avif", "*.bmp", "*.gif", "*.tif", "*.tiff"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Time
        sortReversed: false
    }
    Process { id: triMover }
    function triMove(dest) {                        // dest: путь папки | "trash"
        const it = triItem
        if (!it || triMover.running) return
        const trash = dest === "trash"
        const to = trash ? home + "/.local/share/Trash/files/" + it.name : dest + "/" + it.name
        triUndo = triUndo.concat([{ name: it.name, from: triDir, to: to, trash: trash }])
        triMover.command = ["bash", "-c", 'mkdir -p "$2"; if [ "$3" = trash ]; then gio trash "$1"; else mv -n "$1" "$2"/; fi',
                            "tri", it.path, trash ? "" : dest, trash ? "trash" : ""]
        triMover.running = true
        toast(trash ? "В корзину" : "→ " + leaf(dest))
    }
    function triBack() {
        if (triPos > 0) { triPos--; return }
        const u = triUndo[triUndo.length - 1]
        if (!u || triMover.running) return
        triUndo = triUndo.slice(0, -1)
        triMover.command = ["bash", "-c", 'mv -n "$1" "$2"/ && rm -f "$HOME/.local/share/Trash/info/$3.trashinfo"', "undo", u.to, u.from, u.name]
        triMover.running = true
        toast("Возвращено: " + u.name)
    }
    function triSkip() { if (triPos < triFolder.count - 1) triPos++ }


    // маленькая кнопка на плитке
    component TileBtn: Rectangle {
        id: chip
        property string icon
        property bool on: false
        property color tint: Theme.text
        signal clicked
        width: 28; height: 28; radius: 14
        color: chipMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.82) : Qt.rgba(0, 0, 0, 0.6)
        border { width: 1; color: on ? Theme.primary : Qt.rgba(1, 1, 1, 0.14) }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text { anchors.centerIn: parent; text: chip.icon; color: chip.on ? Theme.primary : chip.tint; font { family: Theme.iconFont; pixelSize: 12 } }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // перенос файла (из плитки): папка или "trash"; сетка обновится сама
    Process { id: fileOp }
    function moveFile(path, dest) {
        if (fileOp.running) return
        const trash = dest === "trash"
        fileOp.command = ["bash", "-c", 'mkdir -p "$2"; if [ "$3" = trash ]; then gio trash "$1"; else mv -n "$1" "$2"/; fi',
                          "mv", path, trash ? "" : dest, trash ? "trash" : ""]
        fileOp.running = true
        toast(trash ? "В корзину" : "→ " + leaf(dest))
    }
    // ── «в группу обоев»: файл или папка добавляется в существующую группу или в новую (мониторы — выбранные сейчас)
    property string groupPath: ""
    property real groupX: 0
    property real groupY: 0
    function openGroupMenu(path, item) {
        const p = item.mapToItem(root.card, 0, item.height + 4)
        groupPath = path
        groupX = Math.max(8, Math.min(p.x - 120, root.card.width - 290))
        groupY = Math.min(p.y, root.card.height - 360)
    }
    function addToGroup(id, name) {
        let gid = id
        if (gid === "") gid = WallGroups.create(name, Session.wallOutputs ? Session.wallOutputs.split(",") : [], [])
        WallGroups.addSource(gid, groupPath)
        toast("В группу «" + (WallGroups.byId(gid)?.name ?? "") + "»: " + leaf(groupPath))
        groupPath = ""
    }
    property string menuPath: ""         // файл, для которого открыто меню «в папку»
    property real menuX: 0
    property real menuY: 0
    function openMoveMenu(path, item) {
        const p = item.mapToItem(root.card, 0, item.height + 4)
        menuPath = path
        menuX = Math.min(p.x, root.card.width - 250)
        menuY = Math.min(p.y, root.card.height - 330)
    }

    // существующие «места»
    Process {
        running: true
        command: ["bash", "-c", 'for d in "$HOME" "$HOME/Pictures" "$HOME/Pictures/wp" "$HOME/Pictures/Screenshots" ' +
                  '"$HOME/Изображения" "$HOME/Изображения/Wallpapers" "$HOME/Downloads" "$HOME/Загрузки" "$HOME/Desktop" ' +
                  '/usr/share/backgrounds /usr/share/wallpapers /run/media/$USER/* /mnt/*; do [ -d "$d" ] || continue; ' +
                  'case "$d" in /run/media/*|/mnt/*) mountpoint -q "$d" || continue;; esac; echo "$d"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set(), out = []
                for (const p of text.trim().split("\n")) {
                    if (!p || seen.has(p)) continue
                    seen.add(p)
                    const icon = p === root.home ? "" : p.startsWith("/run/media") || p.startsWith("/mnt") ? ""
                               : /Pictures|Изображения|wp/.test(p) ? "" : /Downloads|Загрузки/.test(p) ? "" : ""
                    out.push({ path: p, label: p === root.home ? "Домашняя" : root.leaf(p), icon: icon })
                }
                root.places = out
            }
        }
    }

    onKeyPressed: e => {
        const alt = e.modifiers & Qt.AltModifier, ctrl = e.modifiers & Qt.ControlModifier
        if (sortMenuOpen && e.key === Qt.Key_Escape) { sortMenuOpen = false; e.accepted = true; return }
        if (ctrl && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) { zoomBy(1); e.accepted = true; return }
        if (ctrl && e.key === Qt.Key_Minus) { zoomBy(-1); e.accepted = true; return }
        if (e.key === Qt.Key_F1 || (ctrl && e.key === Qt.Key_Slash)) { helpOpen = !helpOpen; e.accepted = true; return }
        if (helpOpen) { if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Space) helpOpen = false; e.accepted = true; return }
        if (triage) {
            const n = e.key >= Qt.Key_1 && e.key <= Qt.Key_9 ? e.key - Qt.Key_1 : -1
            if (triNaming) {
                if (e.key === Qt.Key_Escape) triNaming = false
                return                                  // остальное — в поле ввода
            }
            const total = 5 + targets.length             // пять действий + цели
            if (e.key === Qt.Key_Escape) triage = false
            else if (e.key === Qt.Key_Down) { triSel = Math.min(total - 1, triSel + 1); triEnsure() }
            else if (e.key === Qt.Key_Up) { triSel = Math.max(0, triSel - 1); triEnsure() }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) triActivate(triSel)
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Space || e.key === Qt.Key_K) triActivate(0)
            else if (e.key === Qt.Key_Delete || e.key === Qt.Key_X) triActivate(1)
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backspace || (ctrl && e.key === Qt.Key_Z)) triBack()
            else if (e.key === Qt.Key_S) triSkip()
            else if (e.key === Qt.Key_N) { triNaming = true }
            else if (n >= 0 && n < targets.length) triMove(targets[n].path)
            else if (e.key === Qt.Key_H) Session.wallBlur = !Session.wallBlur
            else return
            e.accepted = true
            return
        }
        if (previewOpen) {
            if (e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace) preview = null
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) previewApply()
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) stepPreview(-1)
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down) stepPreview(1)
            else if (e.key === Qt.Key_S) previewSave()
            else return
            e.accepted = true
            return
        }
        if (e.key === Qt.Key_Escape) {
            if (query) query = ""
            else if (source) source = ""
            e.accepted = true
            return
        }
        if (source && resultCount > 0 && (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Up || e.key === Qt.Key_Down)) {
            const d = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : e.key === Qt.Key_Up ? -mCols : mCols
            onlineCurrent = Math.max(0, Math.min(resultCount - 1, (onlineCurrent < 0 ? 0 : onlineCurrent) + d))
            ensureVisible(onlineCurrent)
            if (onlineCurrent >= resultCount - mCols * 2) more()
        } else if (source && e.key === Qt.Key_Space) {
            if (onlineCurrent >= 0) openOnlinePreview(onlineCurrent)
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            if (source) {
                if (query !== lastQuery || resultCount === 0) search(true)
                else if (onlineCurrent >= 0 && onlineCurrent < resultsModel.count) fetchItem(resultsModel.get(onlineCurrent), true)
            } else activate(grid.currentItem)
        }
        else if (e.key === Qt.Key_Escape && source) { source = ""; query = "" }
        else if (alt && e.key === Qt.Key_Left) { if (source) source = ""; else goBack() }
        else if (alt && e.key === Qt.Key_Right) goFwd()
        else if (alt && e.key === Qt.Key_Up) up()
        else if (ctrl && e.key === Qt.Key_D) { if (!source) togglePin(dir) }
        else if (e.key === Qt.Key_Backspace) { if (query) query = query.slice(0, -1); else if (!source) up() }
        else if (ctrl || alt) return
        else if (e.text && e.text.length === 1 && e.text >= " ") query += e.text
        else return
        e.accepted = true
    }

    component Tool: Rectangle {
        id: tool
        property string icon
        property bool on: false
        property bool off: false            // недоступна
        property string tip
        signal clicked
        width: 32; height: 32; radius: 10
        opacity: off ? 0.35 : 1
        color: on ? Theme.strong : toolMouse.containsMouse && !off ? Theme.strong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: tool.icon
            color: tool.on ? Theme.primary : Theme.text
            font { family: Theme.iconFont; pixelSize: 14 }
        }
        MouseArea { id: toolMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!tool.off) tool.clicked() }
    }

    // перетаскивание окна за верхнюю полосу (двойной клик — вернуть на место)
    MouseArea {
        id: dragArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 60
        property real sx: 0
        property real sy: 0
        property real ox: 0
        property real oy: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: e => { const p = mapToItem(null, e.x, e.y); sx = p.x; sy = p.y; ox = root.offX; oy = root.offY }
        onPositionChanged: e => {
            if (!pressed) return
            const p = mapToItem(null, e.x, e.y)
            root.offX = ox + p.x - sx
            root.offY = oy + p.y - sy
        }
        onDoubleClicked: { root.offX = 0; root.offY = 0 }
        onReleased: e => {
            // курсор за пределами этого монитора — окно переезжает на тот, что под ним
            const scr = root.screen
            const p = mapToItem(null, e.x, e.y)
            const gx = scr.x + p.x, gy = scr.y + p.y
            const t = Quickshell.screens.find(c => gx >= c.x && gx < c.x + c.width && gy >= c.y && gy < c.y + c.height)
            if (!t || t.name === scr.name) return
            Modal.anchorScreen = t
            root.offX = (gx - t.x) - t.width / 2
            root.offY = (gy - t.y) - t.height / 2 + root.card.height / 2 - 30
        }
    }

    // размытие превью: настройка постоянная (Session.wallBlur), под курсором — чётко
    // глаз в шапке — размыть все; глаз на плитке — только эту обою
    readonly property var hidden: { try { return JSON.parse(Session.wallHidden) } catch (e) { return [] } }
    function isHidden(key) { return hidden.indexOf(key) >= 0 }
    function toggleHidden(key) {
        const a = hidden.slice(), i = a.indexOf(key)
        if (i >= 0) a.splice(i, 1); else a.push(key)
        Session.wallHidden = JSON.stringify(a)
    }
    function veilOn(hover, key) { return !hover && (Session.wallBlur || Session.privacy || (key !== undefined && isHidden(key))) }
    function onlineKey(m) { return "o:" + m.provider + ":" + m.id }

    // закрыть окно целиком (то же делает Super+Q)
    Rectangle {
        id: closeBtn
        z: 40
        anchors { top: parent.top; right: parent.right; margins: 12 }
        width: 36; height: 36; radius: 18
        color: closeMouse.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.28) : Theme.strong
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: "\uf00d"
            color: closeMouse.containsMouse ? Theme.danger : Theme.text
            font { family: Theme.iconFont; pixelSize: 14 }
        }
        MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Modal.close() }
    }

    Tool {
        z: 40
        anchors { top: parent.top; right: closeBtn.left; topMargin: 14; rightMargin: 6 }
        icon: Session.wallBlur ? "\uf070" : "\uf06e"
        on: Session.wallBlur
        onClicked: Session.wallBlur = !Session.wallBlur
    }

    Tool {
        z: 40
        anchors { top: parent.top; right: closeBtn.left; topMargin: 14; rightMargin: 44 }
        icon: "\uf059"
        on: root.helpOpen
        onClicked: root.helpOpen = !root.helpOpen
    }

    // ───────── боковая панель
    Rectangle {
        id: side
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 12 }
        width: 208
        radius: 16
        color: Qt.rgba(0, 0, 0, 0.22)

        component SideItem: Rectangle {
            id: si
            property string path
            property string label
            property string icon: ""
            property bool removable: false
            width: parent?.width ?? 0
            height: 32
            radius: 8
            property bool current: root.source === "" && root.dir === path
            property bool custom: false          // свой обработчик клика (онлайн-источники)
            signal clicked
            color: current ? Theme.strong : siMouse.containsMouse ? Theme.weak : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Text {
                id: siIcon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 16
                text: si.icon
                color: si.current ? Theme.primary : Theme.muted
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            Text {
                anchors { left: siIcon.right; leftMargin: 10; right: parent.right; rightMargin: si.removable ? 30 : 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: si.label
                color: si.current ? Theme.text : Qt.rgba(1, 1, 1, 0.82)
                font { family: Theme.font; pixelSize: 13; weight: si.current ? Font.DemiBold : Font.Normal }
            }
            MouseArea {
                id: siMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: e => {
                    if (e.button === Qt.RightButton && si.removable) { root.togglePin(si.path); return }
                    if (si.custom) { si.clicked(); return }
                    root.source = ""
                    root.go(si.path)
                }
            }
            // открепить
            Rectangle {
                visible: si.removable && siMouse.containsMouse
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: 24; height: 24; radius: 7
                color: unpinMouse.containsMouse ? Theme.border : "transparent"
                Text { anchors.centerIn: parent; text: ""; color: Theme.muted; font { family: Theme.iconFont; pixelSize: 10 } }
                MouseArea { id: unpinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePin(si.path) }
            }
        }
        component Section: Text {
            leftPadding: 10
            topPadding: 8
            bottomPadding: 2
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
        }

        // на какие мониторы ставить: клик — включить / выключить, двойной клик — только этот
        Rectangle {
            id: monitorsBox
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            height: monCol.implicitHeight + 16
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.05)
            Column {
                id: monCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 4
                Item {
                    width: parent.width
                    height: 22
                    Text {
                        anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                        text: "На мониторы"
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: Session.wallOutputs === "" ? "все" : "выбрано " + Session.wallOutputs.split(",").length
                        color: allMouse.containsMouse ? Theme.text : Theme.muted
                        font { family: Theme.font; pixelSize: 11 }
                        MouseArea { id: allMouse; anchors { fill: parent; margins: -4 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Session.wallOutputs = "" }
                    }
                }
                Repeater {
                    model: Quickshell.screens
                    Rectangle {
                        id: mon
                        required property var modelData
                        readonly property bool on: root.targetsHas(modelData.name)
                        readonly property real aspect: modelData.width / modelData.height
                        width: monCol.width
                        height: 46
                        radius: 9
                        color: on ? Qt.rgba(1, 1, 1, 0.10) : monMouse.containsMouse ? Theme.weak : "transparent"
                        border { width: 1; color: on ? Theme.primary : "transparent" }
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        // миниатюра того, что сейчас на этом мониторе
                        ClippingRectangle {
                            id: monThumb
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            height: 32
                            width: Math.min(60, Math.round(32 * mon.aspect))
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Image {
                                anchors.fill: parent
                                source: root.currentWalls[mon.modelData.name] ? "file://" + root.currentWalls[mon.modelData.name] : ""
                                sourceSize { width: 160; height: 160 }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                opacity: mon.on ? 1 : 0.5
                                readonly property bool blurOn: root.veilOn(monMouse.containsMouse)
                        layer.enabled: blurOn
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.4; brightness: -0.08 }
                            }
                        }
                        Column {
                            anchors { left: monThumb.right; leftMargin: 9; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            Text {
                                text: mon.modelData.name
                                color: mon.on ? Theme.text : Theme.muted
                                font { family: Theme.font; pixelSize: 12; weight: mon.on ? Font.DemiBold : Font.Medium }
                            }
                            Text {
                                text: mon.modelData.width + "×" + mon.modelData.height
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 10; features: ({ "tnum": 1 }) }
                            }
                        }
                        MouseArea {
                            id: monMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // ЛКМ — вкл/выкл монитор, ПКМ — только он
                            onClicked: e => e.button === Qt.RightButton ? root.onlyTarget(mon.modelData.name) : root.toggleTarget(mon.modelData.name)
                        }
                    }
                }
            }
        }

        Flickable {
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: monitorsBox.top; margins: 8; bottomMargin: 6 }
            contentHeight: sideCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sideCol
                width: parent.width
                spacing: 1

                Section { visible: root.pins.length > 0; text: "Закреплённые" }
                Repeater {
                    model: root.pins
                    SideItem { required property string modelData; path: modelData; label: root.leaf(modelData); icon: ""; removable: true }
                }

                Section { text: "Онлайн" }
                Repeater {
                    model: root.sources
                    SideItem {
                        required property var modelData
                        path: modelData.id
                        label: modelData.label
                        icon: "\uf0ac"
                        current: root.source === modelData.id
                        custom: true
                        onClicked: root.openSource(modelData.id)
                    }
                }
                SideItem { path: "online-saved"; label: "Скачанные"; icon: "\uf019"; current: root.source === "" && root.dir === root.home + "/Pictures/wp/online"
                           custom: true
                           onClicked: { root.source = ""; root.go(root.home + "/Pictures/wp/online") } }

                SideItem { path: "triage"; label: "Разобрать загрузки"; icon: "\uf0ae"; current: root.triage; custom: true
                           onClicked: { root.source = ""; root.triPos = 0; root.triage = true } }

                Section { text: "Места" }
                Repeater {
                    model: root.places
                    SideItem { required property var modelData; path: modelData.path; label: modelData.label; icon: modelData.icon }
                }

                Section { visible: root.recent.length > 0; text: "Недавние" }
                Repeater {
                    model: root.recent.filter(p => root.pins.indexOf(p) < 0 && !root.places.some(x => x.path === p)).slice(0, 5)
                    SideItem { required property string modelData; path: modelData; label: root.leaf(modelData); icon: "" }
                }
            }
        }
    }

    // ───────── верхняя панель
    Item {
        id: header
        anchors { top: parent.top; left: side.right; right: parent.right; margins: 12; leftMargin: 14; rightMargin: 56 }
        height: 36

        Row {
            id: navRow
            visible: root.source === ""
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 2
            Tool { icon: ""; off: root.back.length === 0; onClicked: root.goBack() }
            Tool { icon: ""; off: root.fwd.length === 0; onClicked: root.goFwd() }
            Tool { icon: ""; off: root.dir === "/"; onClicked: root.up() }
        }

        // путь: сегменты кликабельны
        Item {
            id: pathBox
            visible: root.source === ""
            anchors { left: navRow.right; leftMargin: 8; right: tools.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            height: 32
            clip: true
            Rectangle { anchors.fill: parent; radius: 10; color: Theme.weak }
            ListView {
                id: crumbList
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                orientation: ListView.Horizontal
                interactive: false
                model: root.crumbs
                // если путь длиннее строки — хвост всегда виден
                onCountChanged: positionViewAtEnd()
                onContentWidthChanged: positionViewAtEnd()
                delegate: Item {
                    id: crumb
                    required property var modelData
                    required property int index
                    width: crumbRow.implicitWidth
                    height: ListView.view.height
                    Row {
                        id: crumbRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            visible: crumb.index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            leftPadding: 4; rightPadding: 4
                            color: Theme.faint
                            font { family: Theme.iconFont; pixelSize: 9 }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: crumb.modelData.name
                            leftPadding: 5; rightPadding: 5
                            color: crumbMouse.containsMouse ? Theme.text : crumb.index === root.crumbs.length - 1 ? Theme.text : Theme.muted
                            font { family: Theme.font; pixelSize: 13; weight: crumb.index === root.crumbs.length - 1 ? Font.DemiBold : Font.Normal }
                            MouseArea { id: crumbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.go(crumb.modelData.path) }
                        }
                    }
                }
            }
        }

        Row {
            id: tools
            visible: root.source === ""
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            Tool { icon: root.pinned ? "" : ""; on: root.pinned; onClicked: root.togglePin(root.dir) }
            Rectangle {
                id: sortBtn
                height: 32; radius: 10
                width: sortRow.implicitWidth + 20
                color: sortM.containsMouse || root.sortMenuOpen ? Theme.strong : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                Row {
                    id: sortRow
                    anchors.centerIn: parent
                    spacing: 7
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf0dc"; color: Theme.text; font { family: Theme.iconFont; pixelSize: 12 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: root.sortShort; color: Theme.text; font { family: Theme.font; pixelSize: 12; weight: Font.Medium } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf078"; color: Theme.muted; font { family: Theme.iconFont; pixelSize: 8 } }
                }
                MouseArea { id: sortM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSortMenu(sortBtn) }
            }
            Tool { icon: "\uf0c0"; tip: "Группы обоев: смена по таймеру"; onClicked: Modal.toggle("wallgroups") }
            Tool { icon: "\uf067"; tip: "Эту папку — в группу обоев"; onClicked: root.openGroupMenu(root.dir, this) }
            Tool { icon: ""; off: Session.wallZoom === 0; onClicked: Session.wallZoom = Math.max(0, Session.wallZoom - 1) }
            Tool { icon: ""; off: Session.wallZoom === 4; onClicked: Session.wallZoom = Math.min(4, Session.wallZoom + 1) }
        }
    }
    readonly property var sortOrders: [{ id: "name", label: "по имени", rev: false, f: FolderListModel.Name }, { id: "date", label: "по дате загрузки (сначала новые)", rev: true, f: FolderListModel.Time },
                                       { id: "size", label: "по размеру", rev: true, f: FolderListModel.Size }, { id: "type", label: "по типу", rev: false, f: FolderListModel.Type }]
    readonly property var sortCur: sortOrders.find(x => x.id === Session.wallSort) ?? sortOrders[0]
    readonly property string sortShort: ({ name: "Имя", date: "Дата", size: "Размер", type: "Тип" })[sortCur.id] + (Session.wallSortRev ? " ↓" : " ↑")
    property bool sortMenuOpen: false
    property real sortX: 0
    property real sortY: 0
    function openSortMenu(item) {
        const p = item.mapToItem(root.card, 0, item.height + 4)
        sortX = Math.max(8, Math.min(p.x + item.width - 250, root.card.width - 258))
        sortY = p.y
        sortMenuOpen = true
    }
    readonly property string sortLabel: sortCur.label + (Session.wallSortRev !== sortCur.rev ? ", наоборот" : "")

    // верхняя панель онлайна: источник, рейтинги, сортировка, обновить
    Item {
        id: onlineBar
        visible: root.source !== ""
        anchors { top: parent.top; left: side.right; right: parent.right; margins: 12; leftMargin: 14; rightMargin: 56 }
        height: 36

        component Chip: Rectangle {
            id: chip
            property string label
            property bool on: false
            property color tint: Theme.primary
            signal clicked
            height: 30
            width: chipText.implicitWidth + 24
            radius: 15
            color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.22) : chipMouse.containsMouse ? Theme.strong : Theme.weak
            border { width: 1; color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.55) : "transparent" }
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Text {
                id: chipText
                anchors.centerIn: parent
                text: chip.label
                color: chip.on ? chip.tint : Theme.muted
                font { family: Theme.font; pixelSize: 12; weight: chip.on ? Font.DemiBold : Font.Medium }
            }
            MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
        }

        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 6
            Tool { icon: "\uf060"; onClicked: root.source = "" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 6; rightPadding: 8
                text: (root.sources.find(s => s.id === root.source)?.label ?? "")
                color: Theme.text
                font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            }
            Chip { label: "Безопасно"; on: Session.wallRatings.indexOf("s") >= 0; tint: Theme.success; onClicked: root.toggleRating("s") }
            Chip { label: "Сомнительно"; on: Session.wallRatings.indexOf("q") >= 0; tint: Theme.warning; onClicked: root.toggleRating("q") }
            Chip { label: "18+"; on: Session.wallRatings.indexOf("e") >= 0; tint: Theme.danger; onClicked: root.toggleRating("e") }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: root.sorts
                Chip {
                    required property var modelData
                    label: modelData.label
                    on: Session.wallOnSort === modelData.id
                    tint: Theme.text
                    onClicked: { Session.wallOnSort = modelData.id; root.search(true) }
                }
            }
            Chip { label: "Пропорции"; on: Session.wallAspect; tint: Theme.text; onClicked: Session.wallAspect = !Session.wallAspect }
            Tool { icon: "\uf021"; onClicked: root.search(true) }
        }
    }

    // поиск и сводка; в онлайне слева — пропорции
    Item {
        id: sub
        anchors { top: header.bottom; left: side.right; right: parent.right; leftMargin: 14; rightMargin: 12; topMargin: 6 }
        height: root.source ? 34 : 22

        Row {
            id: ratioRow
            visible: root.source !== ""
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 4
                text: "Пропорции"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 12 }
            }
            Repeater {
                model: [["Любые", ""], ["16:9", "16:9"], ["16:10", "16:10"], ["21:9", "21:9"], ["32:9", "32:9"], ["4:3", "4:3"], ["9:16", "9:16"]]
                Rectangle {
                    id: rchip
                    required property var modelData
                    readonly property bool on: Session.wallRatio === modelData[1]
                    height: 26
                    width: rtext.implicitWidth + 20
                    radius: 13
                    color: on ? Qt.rgba(1, 1, 1, 0.18) : rmouse.containsMouse ? Theme.strong : Theme.weak
                    border { width: 1; color: on ? Theme.primary : "transparent" }
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    Text {
                        id: rtext
                        anchors.centerIn: parent
                        text: rchip.modelData[0]
                        color: rchip.on ? Theme.text : Theme.muted
                        font { family: Theme.font; pixelSize: 12; weight: rchip.on ? Font.DemiBold : Font.Medium; features: ({ "tnum": 1 }) }
                    }
                    MouseArea {
                        id: rmouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Session.wallRatio = rchip.modelData[1]; root.search(true) }
                    }
                }
            }
        }
        Text {
            anchors { left: root.source ? ratioRow.right : parent.left; leftMargin: root.source ? 16 : 0; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - (root.source ? ratioRow.width + 16 : 0) - 190)
            elide: Text.ElideRight
            text: root.source
                  ? (root.query ? "\uf002  " + root.query + (root.query !== root.lastQuery ? "   — Enter, чтобы искать" : "")
                                : "печатай теги и жми Enter  ·  ЛКМ — просмотр, ПКМ — поставить")
                  : (root.query ? "\uf002  " + root.query : "печатай, чтобы искать по имени  ·  ЛКМ — просмотр, ПКМ — поставить")
            color: root.query ? Theme.primary : Theme.faint
            font { family: root.query ? Theme.iconFont : Theme.font; pixelSize: 12 }
        }
        // размер превью: кнопки, Ctrl+колесо, Ctrl+«+» / Ctrl+«−»
        Row {
            id: zoomRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            Tool { icon: "\uf068"; tip: "Мельче превью (Ctrl + колесо)"; off: Session.wallZoom === 0; onClicked: root.zoomBy(-1) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 34; horizontalAlignment: Text.AlignHCenter
                text: (Session.wallZoom + 1) + "/5"
                color: Theme.muted
                font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
            }
            Tool { icon: "\uf067"; tip: "Крупнее превью (Ctrl + колесо)"; off: Session.wallZoom === 4; onClicked: root.zoomBy(1) }
        }
        Text {
            anchors { right: zoomRow.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            readonly property int dirs: { let n = 0; for (let i = 0; i < folder.count; i++) if (folder.get(i, "fileIsDir")) n++; return n }
            text: root.source
                  ? root.resultCount + " " + Theme.plural(root.resultCount, "картинка", "картинки", "картинок") + (root.loading ? "  ·  загрузка…" : root.exhausted ? "  ·  больше нет" : "")
                    + (root.source === "wallhaven" && Session.wallRatings.indexOf("e") >= 0 && !root.hasKey ? "  ·  18+ на Wallhaven нужен ключ (wallhaven.key)" : "")
                  : (dirs > 0 ? dirs + " " + Theme.plural(dirs, "папка", "папки", "папок") + " · " : "") + (folder.count - dirs) + " " + Theme.plural(folder.count - dirs, "картинка", "картинки", "картинок")
            color: Theme.muted
            font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
        }
    }

    FolderListModel {
        id: folder
        folder: "file://" + root.dir
        nameFilters: ["jpg", "jpeg", "jfif", "png", "webp", "avif", "bmp", "gif", "tif", "tiff"].map(x => "*" + root.query + "*." + x)
        caseSensitive: false
        showDirs: root.query === ""
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        sortField: root.sortCur.f
        sortReversed: Session.wallSortRev
    }

    GridView {
        id: grid
        visible: root.source === ""
        anchors { top: sub.bottom; bottom: parent.bottom; left: side.right; right: parent.right; margins: 12; leftMargin: 14; topMargin: 6 }
        readonly property var zoom: root.zooms[Session.wallZoom]
        readonly property int cols: Math.max(1, Math.floor(width / (zoom.w + 12)))
        cellWidth: Math.floor(width / cols)
        cellHeight: zoom.h + 12
        clip: true
        focus: true
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        flickDeceleration: 3200
        maximumFlickVelocity: 7000
        model: folder

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: e => {
                if (e.modifiers & Qt.ControlModifier) { root.zoomBy(e.angleDelta.y > 0 ? 1 : -1); return }
                const g = grid
                g.contentY = Math.max(0, Math.min(Math.max(0, g.contentHeight - g.height), g.contentY - e.angleDelta.y * 2.6))
            }
        }

        delegate: Item {
            id: cell
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            required property int index
            readonly property string path: filePath
            readonly property bool isDir: fileIsDir
            readonly property bool current: GridView.isCurrentItem
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: frame
                anchors { fill: parent; margins: 5 }
                radius: 14
                color: cell.isDir ? (cellMouse.containsMouse || cell.current ? Theme.strong : Theme.weak) : Theme.weak
                border { width: cell.current ? 2 : 1; color: cell.current ? Theme.primary : cell.isDir ? Theme.rimSoft : "transparent" }
                Behavior on color { ColorAnimation { duration: Theme.dFast } }

                // папка
                Column {
                    visible: cell.isDir
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""
                        color: root.pins.indexOf(cell.path) >= 0 ? Theme.primary : Qt.rgba(1, 1, 1, 0.55)
                        font { family: Theme.iconFont; pixelSize: Math.round(frame.height * 0.32) }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, frame.width - 24)
                        elide: Text.ElideRight
                        text: cell.fileName
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                    }
                }
                // отметка закреплённой папки
                Text {
                    visible: cell.isDir && root.pins.indexOf(cell.path) >= 0
                    anchors { top: parent.top; right: parent.right; margins: 9 }
                    text: ""
                    color: Theme.primary
                    font { family: Theme.iconFont; pixelSize: 11 }
                }

                // картинка
                ClippingRectangle {
                    visible: !cell.isDir
                    anchors { fill: parent; margins: 3 }
                    radius: 11
                    color: "transparent"
                    Image {
                        anchors.fill: parent
                        source: cell.isDir ? "" : root.thumbOf(cell.filePath) || "file://" + cell.filePath
                        onStatusChanged: if (status === Image.Error && source.toString().indexOf(root.thumbs) >= 0)
                            source = "file://" + cell.filePath
                        sourceSize { width: grid.zoom.w * 2; height: grid.zoom.h * 2 }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        smooth: true
                        readonly property bool blurOn: root.veilOn(cellMouse.containsMouse, cell.filePath)
                        layer.enabled: blurOn
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.4; brightness: -0.08 }
                    }
                    // имя файла — при наведении / выборе
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 26
                        opacity: cellMouse.containsMouse || cell.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 7; bottomMargin: 5 }
                            elide: Text.ElideMiddle
                            text: cell.fileName
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                }
            }

            MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: grid.currentIndex = cell.index
                onClicked: e => {
                    if (e.button === Qt.RightButton) {
                        if (cell.isDir) root.togglePin(cell.path)
                        else root.apply(cell.path, cell.fileName)
                    } else {
                        if (cell.isDir) root.go(cell.path)
                        else root.openLocalPreview(cell.index)
                    }
                }
            }

            HoverHandler { id: cellHover }
            Row {
                visible: !cell.isDir && (cellHover.hovered || cell.current)
                z: 5
                anchors { top: parent.top; right: parent.right; margins: 9 }
                spacing: 4
                TileBtn { icon: root.isHidden(cell.filePath) ? "\uf070" : "\uf06e"; on: root.isHidden(cell.filePath); onClicked: root.toggleHidden(cell.filePath) }
                TileBtn { icon: "\uf07b"; onClicked: root.openMoveMenu(cell.path, this) }
                TileBtn { icon: "\uf0c0"; visible: !cell.isDir; onClicked: root.openGroupMenu(cell.path, this) }
                TileBtn { icon: "\uf1f8"; tint: Theme.danger; onClicked: root.moveFile(cell.path, "trash") }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: folder.status === FolderListModel.Ready && folder.count === 0
            text: root.query ? "Ничего не найдено по «" + root.query + "»" : "Здесь нет ни папок, ни картинок"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 14 }
        }
    }

    // ───────── онлайн-лента: кирпичиками, в исходных пропорциях (переключается кнопкой «Пропорции»)
    Flickable {
        id: onlineFlick
        visible: root.source !== ""
        anchors { top: sub.bottom; bottom: parent.bottom; left: side.right; right: parent.right; margins: 12; leftMargin: 14; topMargin: 6 }
        clip: true
        contentWidth: width
        contentHeight: root.masonryHeight + 12
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3200
        maximumFlickVelocity: 7000

        // дальше подгружаем заранее: ещё до того, как упрёшься в конец; позиция прокрутки не сбрасывается
        function prefetch() {
            if (visible && contentHeight > 0 && contentHeight - (contentY + height) < height * 0.9) root.more()
        }
        onContentYChanged: prefetch()
        onContentHeightChanged: prefetch()
        onHeightChanged: prefetch()

        // колесо: быстрее стандартного шага (3 строки ≈ 60 px → ~150 px за щелчок)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: e => {
                if (e.modifiers & Qt.ControlModifier) { root.zoomBy(e.angleDelta.y > 0 ? 1 : -1); return }
                const f = onlineFlick
                f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY - e.angleDelta.y * 2.6))
            }
        }

        Repeater {
            model: resultsModel
            delegate: Item {
                id: tile
                required property var model
                required property int index
                readonly property bool current: root.onlineCurrent === index
                readonly property bool busy: root.dlBusy[model.id] !== undefined
                readonly property bool saved: root.dlDone[model.id] === true
                x: model.px; y: model.py
                width: model.pw; height: model.ph
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Theme.dBase } }
                Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

                ClippingRectangle {
                    anchors { fill: parent; margins: 5 }
                    radius: 14
                    color: Theme.weak
                    border { width: tile.current ? 2 : 0; color: Theme.primary }
                    Image {
                        anchors.fill: parent
                        source: "file://" + tile.model.thumb
                        sourceSize { width: Math.round(root.mColW * 2); height: Math.round(root.mColW * 2) }
                        fillMode: Image.PreserveAspectCrop        // никогда не растягиваем: при расхождении — лёгкая обрезка
                        asynchronous: true
                        cache: false
                        smooth: true
                        readonly property bool blurOn: root.veilOn(tileMouse.containsMouse, root.onlineKey(tile.model))
                        layer.enabled: blurOn
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.4; brightness: -0.08 }
                        opacity: tile.busy ? 0.45 : 1
                        Behavior on opacity { NumberAnimation { duration: Theme.dBase } }
                    }
                    // разрешение и рейтинг — при наведении / выборе
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 28
                        opacity: tileMouse.containsMouse || tile.current || tile.busy ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
                        }
                        Row {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7; height: 7; radius: 3.5
                                color: tile.model.rating === "e" ? Theme.danger : tile.model.rating === "q" ? Theme.warning : Theme.success
                            }
                            Text {
                                text: tile.busy ? "скачиваю…" : tile.model.w + " × " + tile.model.h
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                            }
                        }
                    }
                }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: root.onlineCurrent = tile.index
                    onClicked: e => e.button === Qt.RightButton ? root.fetchItem(resultsModel.get(tile.index), false)
                                                                : root.openOnlinePreview(tile.index)
                }
                HoverHandler { id: tileHover }
                Row {
                    visible: tileHover.hovered || tile.current
                    z: 5
                    anchors { top: parent.top; right: parent.right; margins: 10 }
                    spacing: 4
                    TileBtn { icon: root.isHidden(root.onlineKey(tile.model)) ? "\uf070" : "\uf06e"; on: root.isHidden(root.onlineKey(tile.model)); onClicked: root.toggleHidden(root.onlineKey(tile.model)) }
                    TileBtn { icon: tile.saved ? "\uf00c" : tile.busy ? "\uf110" : "\uf019"; on: tile.saved; onClicked: root.fetchItem(resultsModel.get(tile.index), false) }
                }
            }
        }

        // состояние: загрузка / ошибка
        Text {
            anchors.centerIn: parent
            visible: root.resultCount === 0
            text: root.loading ? "Ищу…" : root.error
            color: root.error && !root.loading ? Theme.danger : Theme.muted
            font { family: Theme.font; pixelSize: 14 }
        }
    }

    // подтверждение действия: меню не закрывается, можно продолжать
    Rectangle {
        id: toastPill
        z: 80
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
        height: 36
        width: toastLabel.implicitWidth + 32
        radius: 18
        color: Qt.rgba(0, 0, 0, 0.78)
        border { width: 1; color: Theme.border }
        opacity: root.toastText ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase } }
        Text {
            id: toastLabel
            anchors.centerIn: parent
            text: "\uf00c  " + root.toastText
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
        }
    }

    // очередь загрузок: сколько ещё качается
    Rectangle {
        z: 79
        visible: root.dlPending > 0
        anchors { right: parent.right; bottom: parent.bottom; margins: 22 }
        height: 36
        width: dlLabel.implicitWidth + 32
        radius: 18
        color: Qt.rgba(0, 0, 0, 0.78)
        border { width: 1; color: Theme.border }
        Text {
            id: dlLabel
            anchors.centerIn: parent
            text: "\uf019  Скачивается: " + root.dlPending + (root.dlTotal > root.dlPending ? " из " + root.dlTotal : "")
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.Medium; features: ({ "tnum": 1 }) }
        }
    }

    // ───────── увеличенный просмотр с параметрами показа на экране
    component PvBtn: Rectangle {
        id: pb
        property string text
        property string icon
        property bool primary: false
        property bool busy: false
        signal clicked
        height: 38
        width: pbRow.implicitWidth + 28
        radius: 19
        opacity: busy ? 0.6 : 1
        color: primary ? Theme.selected : pbMouse.containsMouse ? Theme.border : Theme.strong
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Row {
            id: pbRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                visible: pb.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pb.icon
                color: pb.primary ? Theme.base : Theme.text
                font { family: Theme.iconFont; pixelSize: 14 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pb.text
                color: pb.primary ? Theme.base : Theme.text
                font { family: Theme.font; pixelSize: 13; weight: pb.primary ? Font.DemiBold : Font.Medium }
            }
        }
        MouseArea { id: pbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
    // переключатель в боковой панели параметров
    component Opt: Rectangle {
        id: opt
        property string label
        property bool on: false
        property color swatch: "transparent"
        signal clicked
        height: 30
        width: optRow.implicitWidth + 22
        radius: 15
        color: on ? Qt.rgba(1, 1, 1, 0.16) : optMouse.containsMouse ? Theme.strong : Theme.weak
        border { width: 1; color: on ? Theme.primary : "transparent" }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Row {
            id: optRow
            anchors.centerIn: parent
            spacing: 7
            Rectangle {
                visible: opt.swatch.a > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: opt.swatch
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.3) }
            }
            Text {
                visible: opt.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: opt.label
                color: opt.on ? Theme.text : Theme.muted
                font { family: Theme.font; pixelSize: 12; weight: opt.on ? Font.DemiBold : Font.Medium }
            }
        }
        MouseArea { id: optMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: opt.clicked() }
    }

    Item {
        id: pv
        anchors.fill: parent
        z: 50
        visible: opacity > 0
        opacity: root.previewOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase } }

        readonly property real panelW: 252
        readonly property real areaW: width - panelW - 150
        readonly property real areaH: height - 130
        readonly property string src: !root.preview ? ""
            : root.preview.online ? "file://" + (root.preview.full || root.preview.thumb) : "file://" + root.preview.path
        // монитор, по которому показываем «как на экране»: первый из выбранных, иначе основной
        readonly property string outName: Session.wallOutputs ? Session.wallOutputs.split(",")[0] : Theme.primaryMonitor
        readonly property var scr: Quickshell.screens.find(s => s.name === outName) ?? Quickshell.screens[0]
        readonly property real scrAspect: scr ? scr.width / scr.height : 16 / 9
        readonly property bool simulate: Session.wallSim
        readonly property string mode: Session.wallResize

        Rectangle { anchors.fill: parent; radius: 28; color: Qt.rgba(0, 0, 0, 0.9) }
        MouseArea { anchors.fill: parent; onClicked: root.preview = null }

        // кадр: либо монитор целиком с выбранным режимом, либо картинка как есть
        Item {
            id: stage
            anchors { left: parent.left; leftMargin: 90; top: parent.top; topMargin: 24 }
            width: pv.areaW
            height: pv.areaH

            readonly property real imgAspect: {
                const p = root.preview
                if (!p) return 16 / 9
                const w = p.online ? p.w : realImg.sourceSize.width, h = p.online ? p.h : realImg.sourceSize.height
                return w > 0 && h > 0 ? w / h : 16 / 9
            }
            readonly property real fa: pv.simulate ? pv.scrAspect : imgAspect          // пропорции рамки
            readonly property real fw: Math.min(width, height * fa)
            readonly property real fh: fw / fa

            ClippingRectangle {
                id: frame
                anchors.centerIn: parent
                width: Math.max(80, stage.fw)
                height: Math.max(60, stage.fh)
                radius: pv.simulate ? 10 : 18
                color: pv.simulate ? "#" + Session.wallFill : "transparent"
                border { width: pv.simulate ? 2 : 0; color: Qt.rgba(1, 1, 1, 0.25) }
                MouseArea { anchors.fill: parent }

                HoverHandler { id: frameHover }
                Image {
                    id: realImg
                    readonly property bool blurOn: root.veilOn(frameHover.hovered, root.preview ? (root.preview.online ? root.onlineKey(root.preview) : root.preview.path) : undefined)
                    layer.enabled: blurOn
                    layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.4; brightness: -0.08 }
                    anchors.centerIn: parent
                    readonly property real nativeScale: pv.scr ? frame.width / pv.scr.width : 1
                    width: !pv.simulate ? parent.width : pv.mode === "no" ? sourceSize.width * nativeScale : parent.width
                    height: !pv.simulate ? parent.height : pv.mode === "no" ? sourceSize.height * nativeScale : parent.height
                    source: pv.src
                    sourceSize { width: pv.mode === "no" && pv.simulate ? 8192 : 3840; height: pv.mode === "no" && pv.simulate ? 8192 : 2160 }
                    fillMode: !pv.simulate ? Image.PreserveAspectFit
                            : pv.mode === "crop" ? Image.PreserveAspectCrop
                            : pv.mode === "fit" ? Image.PreserveAspectFit
                            : Image.Stretch
                    horizontalAlignment: pv.mode !== "crop" ? Image.AlignHCenter
                        : /left/.test(Session.wallGravity) ? Image.AlignLeft : /right/.test(Session.wallGravity) ? Image.AlignRight : Image.AlignHCenter
                    verticalAlignment: pv.mode !== "crop" ? Image.AlignVCenter
                        : /top/.test(Session.wallGravity) ? Image.AlignTop : /bottom/.test(Session.wallGravity) ? Image.AlignBottom : Image.AlignVCenter
                    asynchronous: true
                    cache: false
                    smooth: true
                }
            }
            // название монитора в углу кадра
            Text {
                visible: pv.simulate
                anchors { left: frame.left; bottom: frame.top; bottomMargin: 6 }
                text: pv.outName + "  ·  " + (pv.scr ? pv.scr.width + "×" + pv.scr.height : "")
                color: Theme.muted
                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
            }
            Text {
                visible: !!(root.preview && root.preview.online && !root.preview.full)
                anchors { top: frame.top; right: frame.right; margins: 12 }
                text: "загружаю оригинал…"
                color: Theme.text
                font { family: Theme.font; pixelSize: 12 }
                Rectangle { anchors { fill: parent; margins: -8 } z: -1; radius: 12; color: Qt.rgba(0, 0, 0, 0.6) }
            }
        }

        // листание
        component Arrow: Rectangle {
            id: ar
            property string icon
            signal clicked
            width: 44; height: 44; radius: 22
            color: arMouse.containsMouse ? Theme.border : Theme.strong
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Text { anchors.centerIn: parent; text: ar.icon; color: Theme.text; font { family: Theme.iconFont; pixelSize: 16 } }
            MouseArea { id: arMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ar.clicked() }
        }
        Arrow {
            anchors { left: parent.left; leftMargin: 24; verticalCenter: stage.verticalCenter }
            icon: ""
            onClicked: root.stepPreview(-1)
        }
        Arrow {
            anchors { left: stage.right; leftMargin: 16; verticalCenter: stage.verticalCenter }
            icon: ""
            onClicked: root.stepPreview(1)
        }

        // ── параметры показа
        Rectangle {
            id: panel
            anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 18; bottom: bar.top; bottomMargin: 12 }
            width: pv.panelW - 12
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.05)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.08) }
            MouseArea { anchors.fill: parent }

            Flickable {
                anchors { fill: parent; margins: 14 }
                contentHeight: optCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: optCol
                    width: parent.width
                    spacing: 8

                    component Cap: Text {
                        topPadding: 6
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
                    }

                    Cap { text: "Предпросмотр" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Opt { label: "Как на экране"; on: Session.wallSim; onClicked: Session.wallSim = true }
                        Opt { label: "Целиком"; on: !Session.wallSim; onClicked: Session.wallSim = false }
                    }

                    Cap { text: "Подгонка под экран" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Opt { label: "Заполнить"; on: Session.wallResize === "crop"; onClicked: Session.wallResize = "crop" }
                        Opt { label: "Вписать"; on: Session.wallResize === "fit"; onClicked: Session.wallResize = "fit" }
                        Opt { label: "Растянуть"; on: Session.wallResize === "stretch"; onClicked: Session.wallResize = "stretch" }
                        Opt { label: "Оригинал"; on: Session.wallResize === "no"; onClicked: Session.wallResize = "no" }
                    }

                    Cap { visible: Session.wallResize === "crop"; text: "Какую часть оставить при обрезке" }
                    Flow {
                        visible: Session.wallResize === "crop"
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [["Центр", "center"], ["Верх", "top"], ["Низ", "bottom"], ["Лево", "left"], ["Право", "right"]]
                            Opt {
                                required property var modelData
                                label: modelData[0]
                                on: Session.wallGravity === modelData[1]
                                onClicked: Session.wallGravity = modelData[1]
                            }
                        }
                    }

                    Cap { visible: Session.wallResize === "fit" || Session.wallResize === "no"; text: "Цвет полей" }
                    Flow {
                        visible: Session.wallResize === "fit" || Session.wallResize === "no"
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [["Чёрный", "000000"], ["Графит", "1c1c21"], ["Белый", "ffffff"],
                                    ["Акцент", Theme.accent.toString().slice(1, 7)]]
                            Opt {
                                required property var modelData
                                label: modelData[0]
                                swatch: "#" + modelData[1]
                                on: Session.wallFill === modelData[1]
                                onClicked: Session.wallFill = modelData[1]
                            }
                        }
                    }

                    Cap { text: "Анимация смены обоев" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [["Динамичная", "dynamic"], ["Волна", "wave"], ["Круг", "grow"], ["Сжатие", "outer"], ["Шторка", "wipe"], ["Плавно", "fade"], ["Без анимации", "none"]]
                            Opt {
                                required property var modelData
                                label: modelData[0]
                                on: Session.wallAnim === modelData[1]
                                onClicked: Session.wallAnim = modelData[1]
                            }
                        }
                    }

                    Cap { text: "Апскейл" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Opt { label: "При установке — авто"; on: Session.wallAutoUp; onClicked: Session.wallAutoUp = true }
                        Opt { label: "Выкл"; on: !Session.wallAutoUp; onClicked: Session.wallAutoUp = false }
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.upModels
                            Opt {
                                required property var modelData
                                label: modelData[0]
                                on: root.upModel === modelData[1]
                                onClicked: root.upModel = modelData[1]
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Если обои меньше монитора, при установке они автоматически увеличиваются на видеокарте (до ширины выбранных мониторов). Файлы лежат в ~/Pictures/wp/upscaled."
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }

                    Cap { text: "Мониторы" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Opt { label: "Все"; on: Session.wallOutputs === ""; onClicked: Session.wallOutputs = "" }
                        Repeater {
                            model: Quickshell.screens
                            Opt {
                                required property var modelData
                                label: modelData.name
                                on: Session.wallOutputs.split(",").indexOf(modelData.name) >= 0
                                onClicked: {
                                    const cur = Session.wallOutputs ? Session.wallOutputs.split(",") : []
                                    const i = cur.indexOf(modelData.name)
                                    if (i >= 0) cur.splice(i, 1); else cur.push(modelData.name)
                                    Session.wallOutputs = cur.join(",")
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        topPadding: 4
                        text: Session.wallOutputs === "" ? "Применится ко всем мониторам." : "Только: " + Session.wallOutputs.replace(/,/g, ", ") + "."
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
            }
        }

        // ── панель: сведения и действия
        Item {
            id: bar
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
            width: Math.min(parent.width - 60, info.implicitWidth + actions.implicitWidth + 40)
            height: 56

            Column {
                id: info
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: Math.min(implicitWidth, 420)
                    elide: Text.ElideMiddle
                    text: root.preview?.name ?? ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                }
                Text {
                    text: {
                        const p = root.preview
                        if (!p) return ""
                        const w = p.online ? p.w : realImg.sourceSize.width, h = p.online ? p.h : realImg.sourceSize.height
                        const parts = []
                        if (w > 0) parts.push(w + " × " + h)
                        if (!p.online && p.size) parts.push((p.size / 1048576).toFixed(1) + " МБ")
                        if (p.online) parts.push(p.rating === "e" ? "18+" : p.rating === "q" ? "сомнительно" : "безопасно")
                        return parts.join(" · ")
                    }
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                }
            }
            Row {
                id: actions
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                PvBtn {
                    visible: root.preview !== null && !root.preview.online
                    icon: ""
                    text: "В файловом менеджере"
                    onClicked: { const p = root.preview.path; Modal.close(); Quickshell.execDetached(["alacritty", "-e", "yazi", p]) }
                }
                PvBtn {
                    visible: root.preview?.online ?? false
                    icon: ""
                    text: root.dlBusy[root.preview?.id] === "save" ? "В очереди…" : root.dlDone[root.preview?.id] ? "Сохранено" : "Сохранить"
                    onClicked: root.previewSave()
                }
                PvBtn {
                    icon: "\uf0b2"
                    text: root.upBusy ? "Апскейлю…" : "Апскейл + установить"
                    busy: root.upBusy
                    onClicked: root.upscale(true)
                }
                PvBtn {
                    primary: true
                    icon: ""
                    text: root.dlBusy[root.preview?.id] === "apply" ? "Ставлю…" : "Установить"
                    busy: root.dlBusy[root.preview?.id] === "apply"
                    onClicked: root.previewApply()
                }
                PvBtn { icon: ""; text: "Закрыть"; onClicked: root.preview = null }
            }
        }
    }

    // ───────── разбор загрузок
    Rectangle {
        id: tri
        z: 35
        visible: opacity > 0
        opacity: root.triage ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
        anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: parent.right; margins: 12; leftMargin: 14 }
        radius: 16
        color: Qt.rgba(0.035, 0.035, 0.05, 0.96)       // непрозрачный: сетка под ним не должна просвечивать
        MouseArea { anchors.fill: parent }

        readonly property real colW: 270

        Text {
            id: triTitle
            anchors { left: parent.left; top: parent.top; margins: 20 }
            text: "Разбор загрузок"
            color: Theme.text
            font { family: Theme.font; pixelSize: 17; weight: Font.DemiBold }
        }
        Text {
            anchors { left: triTitle.right; leftMargin: 14; verticalCenter: triTitle.verticalCenter }
            text: triFolder.count === 0 ? "всё разобрано" : (root.triPos + 1) + " из " + triFolder.count
            color: Theme.muted
            font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) }
        }

        // картинка
        Item {
            id: triStage
            anchors { left: parent.left; top: triTitle.bottom; bottom: parent.bottom; right: triSide.left; margins: 20; topMargin: 14 }
            Image {
                id: triImg
                anchors.fill: parent
                source: root.triItem ? "file://" + root.triItem.path : ""
                sourceSize { width: 2560; height: 1440 }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                smooth: true
                readonly property bool blurOn: root.veilOn(triHover.hovered, root.triItem ? root.triItem.path : undefined)
                layer.enabled: blurOn
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.4; brightness: -0.08 }
                HoverHandler { id: triHover }
            }
            Text {
                anchors.centerIn: parent
                visible: triFolder.count === 0
                text: "В «Скачанных» ничего не осталось"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 15 }
            }
        }

        // действия
        Item {
            id: triSide
            anchors { right: parent.right; top: triTitle.bottom; bottom: parent.bottom; margins: 20; topMargin: 14 }
            width: tri.colW

            component TriBtn: Rectangle {
                id: tb
                property string icon
                property string text
                property string hint
                property bool primary: false
                property bool selected: false
                property color tint: Theme.text
                signal clicked
                width: parent?.width ?? 0
                height: 42
                radius: 12
                color: primary ? (tbm.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85))
                              : tbm.containsMouse || selected ? Theme.strong : Theme.weak
                border { width: selected ? 2 : 0; color: Theme.primary }
                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                Text {
                    id: tbi
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 18
                    text: tb.icon
                    color: tb.primary ? Theme.base : tb.tint
                    font { family: Theme.iconFont; pixelSize: 15 }
                }
                Text {
                    anchors { left: tbi.right; leftMargin: 10; right: tbh.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: tb.text
                    color: tb.primary ? Theme.base : Theme.text
                    font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    id: tbh
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: tb.hint
                    color: tb.primary ? Qt.rgba(0, 0, 0, 0.5) : Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
                MouseArea { id: tbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
            }

            Column {
                id: triTop
                width: parent.width
                spacing: 6
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.triItem?.name ?? ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    text: triImg.implicitWidth > 0 ? Math.round(triImg.implicitWidth) + " × " + Math.round(triImg.implicitHeight) : ""
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                }
                Item { width: 1; height: 2 }
                TriBtn { primary: root.triSel === 0; selected: root.triSel === 0; icon: "\uf00c"; text: "Оставить"; hint: "→"; onClicked: { root.triSel = 0; root.triActivate(0) } }
                TriBtn { selected: root.triSel === 1; icon: "\uf1f8"; text: "В корзину"; hint: "Del"; tint: Theme.danger; onClicked: { root.triSel = 1; root.triActivate(1) } }
                TriBtn { selected: root.triSel === 2; icon: "\uf0c5"; text: "Поставить на обои"; hint: ""; onClicked: { root.triSel = 2; root.triActivate(2) } }
                TriBtn { selected: root.triSel === 3; icon: "\uf0a9"; text: "Пропустить"; hint: "S"; onClicked: { root.triSel = 3; root.triActivate(3) } }
                TriBtn { selected: root.triSel === 4; icon: "\uf0e2"; text: "Назад / отменить"; hint: "←"; onClicked: { root.triSel = 4; root.triActivate(4) } }
                Item { width: 1; height: 2 }
                Text {
                    text: "В ПАПКУ  ·  " + root.leaf(root.sortRoot)
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 }
                }
            }

            // цели: подпапки корня и закреплённые; скроллятся, выбор — стрелками
            Flickable {
                id: triTargets
                anchors { left: parent.left; right: parent.right; top: triTop.bottom; bottom: triFoot.top; topMargin: 6; bottomMargin: 8 }
                contentHeight: tgCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Connections {
                    target: root
                    function onTriEnsure() {
                        const i = root.triSel - 5
                        if (i < 0) { triTargets.contentY = 0; return }
                        const y = i * 44
                        if (y < triTargets.contentY) triTargets.contentY = y
                        else if (y + 42 > triTargets.contentY + triTargets.height) triTargets.contentY = y + 42 - triTargets.height
                    }
                }
                Column {
                    id: tgCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.targets
                        TriBtn {
                            required property var modelData
                            required property int index
                            selected: root.triSel === index + 5
                            icon: "\uf07b"
                            text: modelData.label
                            hint: index < 9 ? String(index + 1) : ""
                            onClicked: { root.triSel = index + 5; root.triMove(modelData.path) }
                        }
                    }
                }
            }

            Column {
                id: triFoot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                spacing: 6
                // новая папка в корне сортировки
                Rectangle {
                    visible: root.triNaming
                    width: parent.width
                    height: 40
                    radius: 12
                    color: Theme.weak
                    border { width: 2; color: Theme.primary }
                    TextInput {
                        id: triName
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 13 }
                        clip: true
                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                        onAccepted: {
                            if (text.trim() !== "") root.triMove(root.newFolderPath(text))
                            root.triNaming = false
                        }
                        Keys.onEscapePressed: root.triNaming = false
                        Text {
                            visible: triName.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Имя новой папки — Enter"
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 13 }
                        }
                    }
                }
                TriBtn { visible: !root.triNaming; icon: "\uf067"; text: "Новая папка…"; hint: "N"; onClicked: root.triNaming = true }
                TriBtn {
                    icon: "\uf013"
                    text: "Сделать текущую папку корнем"
                    hint: ""
                    height: 34
                    onClicked: { Session.wallSortRoot = root.dir; root.toast("Корень сортировки: " + root.leaf(root.dir)) }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Перейди в проводнике в папку с твоими подпапками и нажми «Сделать текущую папку корнем» — они появятся в списке."
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
        }

        // выйти
        Rectangle {
            anchors { right: parent.right; top: parent.top; rightMargin: 100; topMargin: 14 }
            width: 32; height: 32; radius: 16
            color: exM.containsMouse ? Theme.strong : Theme.weak
            Text { anchors.centerIn: parent; text: "\uf00d"; color: Theme.text; font { family: Theme.iconFont; pixelSize: 13 } }
            MouseArea { id: exM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.triage = false }
        }
    }

    // ───────── меню «в папку»
    MouseArea {
        z: 60
        visible: root.menuPath !== ""
        anchors.fill: parent
        onClicked: root.menuPath = ""
    }
    Rectangle {
        id: moveMenu
        z: 61
        visible: root.menuPath !== ""
        x: root.menuX; y: root.menuY
        width: 260
        height: Math.min(420, mmFlick.contentHeight + 60)
        radius: 14
        color: Qt.rgba(0.07, 0.07, 0.09, 0.97)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
        Text {
            id: mmHead
            anchors { left: parent.left; top: parent.top; margins: 12 }
            text: "В ПАПКУ  ·  " + root.leaf(root.sortRoot)
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 }
        }
        Flickable {
            id: mmFlick
            anchors { left: parent.left; right: parent.right; top: mmHead.bottom; bottom: mmNew.top; margins: 8; topMargin: 6 }
            contentHeight: mmCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: mmCol
                width: parent.width
                spacing: 2
                Repeater {
                    model: root.targets
                    Rectangle {
                        required property var modelData
                        width: mmCol.width
                        height: 32
                        radius: 8
                        color: mmM.containsMouse ? Theme.strong : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideMiddle
                            text: "\uf07b   " + modelData.label
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13 }
                        }
                        MouseArea {
                            id: mmM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.moveFile(root.menuPath, parent.modelData.path); root.menuPath = "" }
                        }
                    }
                }
            }
        }
        // новая папка прямо отсюда
        Rectangle {
            id: mmNew
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            height: 36
            radius: 10
            color: Theme.weak
            border { width: mmName.activeFocus ? 2 : 0; color: Theme.primary }
            TextInput {
                id: mmName
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font { family: Theme.font; pixelSize: 13 }
                clip: true
                onAccepted: {
                    if (text.trim() !== "") { root.moveFile(root.menuPath, root.newFolderPath(text)); text = ""; root.menuPath = "" }
                }
                Keys.onEscapePressed: root.menuPath = ""
                Text {
                    visible: mmName.text === "" && !mmName.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "＋ Новая папка — имя и Enter"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
        }
    }

    // ───────── меню сортировки: весь список сразу, текущее отмечено
    MouseArea { z: 62; visible: root.sortMenuOpen; anchors.fill: parent; onClicked: root.sortMenuOpen = false }
    Rectangle {
        z: 63
        visible: root.sortMenuOpen
        x: root.sortX; y: root.sortY
        width: 250
        height: sortCol.implicitHeight + 16
        radius: 14
        color: Qt.rgba(0.07, 0.07, 0.09, 0.97)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
        Column {
            id: sortCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2
            Text { text: "СОРТИРОВКА"; leftPadding: 6; bottomPadding: 4; color: Theme.faint; font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 } }
            Repeater {
                model: [{ id: "name", label: "По имени", rev: false }, { id: "date", label: "По дате загрузки", rev: true },
                        { id: "size", label: "По размеру файла", rev: true }, { id: "type", label: "По типу файла", rev: false }]
                Rectangle {
                    required property var modelData
                    readonly property bool cur: Session.wallSort === modelData.id
                    width: sortCol.width; height: 34; radius: 8
                    color: smM.containsMouse ? Theme.strong : cur ? Theme.weak : "transparent"
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "\uf00c"; opacity: parent.cur ? 1 : 0; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 12 } }
                    Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: parent.cur ? Font.DemiBold : Font.Normal } }
                    MouseArea {
                        id: smM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { if (!parent.cur) Session.wallSortRev = parent.modelData.rev; Session.wallSort = parent.modelData.id; root.sortMenuOpen = false }
                    }
                }
            }
            Rectangle { width: sortCol.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
            Repeater {
                model: [{ label: "Сначала новые / большие", rev: true }, { label: "Сначала старые / маленькие", rev: false }]
                Rectangle {
                    required property var modelData
                    readonly property bool cur: Session.wallSortRev === modelData.rev
                    width: sortCol.width; height: 34; radius: 8
                    color: dM.containsMouse ? Theme.strong : cur ? Theme.weak : "transparent"
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "\uf00c"; opacity: parent.cur ? 1 : 0; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 12 } }
                    Text { x: 32; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.label; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: parent.cur ? Font.DemiBold : Font.Normal } }
                    MouseArea { id: dM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Session.wallSortRev = parent.modelData.rev; root.sortMenuOpen = false } }
                }
            }
        }
    }

    // ───────── меню «в группу обоев»
    MouseArea { z: 62; visible: root.groupPath !== ""; anchors.fill: parent; onClicked: root.groupPath = "" }
    Rectangle {
        z: 63
        visible: root.groupPath !== ""
        x: root.groupX; y: root.groupY
        width: 280
        height: Math.min(420, ggCol.implicitHeight + 130)
        radius: 14
        color: Qt.rgba(0.07, 0.07, 0.09, 0.97)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
        Text {
            id: ggHead
            anchors { left: parent.left; top: parent.top; margins: 12 }
            text: "В ГРУППУ ОБОЕВ"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 }
        }
        Flickable {
            anchors { left: parent.left; right: parent.right; top: ggHead.bottom; bottom: ggNew.top; margins: 8; topMargin: 6 }
            contentHeight: ggCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: ggCol
                width: parent.width
                spacing: 2
                Text {
                    visible: WallGroups.groups.length === 0
                    width: parent.width; padding: 8; wrapMode: Text.Wrap
                    text: "Групп пока нет — создайте ниже"
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }
                Repeater {
                    model: WallGroups.groups
                    Rectangle {
                        required property var modelData
                        width: ggCol.width; height: 32; radius: 8
                        color: ggM.containsMouse ? Theme.strong : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: "\uf0c0   " + modelData.name + "  ·  " + modelData.sources.length
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13 }
                        }
                        MouseArea { id: ggM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addToGroup(parent.modelData.id, "") }
                    }
                }
            }
        }
        Rectangle {
            id: ggNew
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            height: 36; radius: 10
            color: Theme.weak
            border { width: ggName.activeFocus ? 2 : 0; color: Theme.primary }
            TextInput {
                id: ggName
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font { family: Theme.font; pixelSize: 13 }
                clip: true
                onAccepted: { if (text.trim() !== "") { root.addToGroup("", text.trim()); text = "" } }
                Keys.onEscapePressed: root.groupPath = ""
                Text {
                    visible: ggName.text === "" && !ggName.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    text: "＋ Новая группа — имя и Enter"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
        }
    }

    // ───────── шпаргалка
    Rectangle {
        id: help
        z: 70
        visible: opacity > 0
        opacity: root.helpOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
        anchors.fill: parent
        radius: 28
        color: Qt.rgba(0.03, 0.03, 0.045, 0.97)
        MouseArea { anchors.fill: parent; onClicked: root.helpOpen = false }

        readonly property var groups: [
            { title: "Проводник", rows: [
                ["Печатать", "поиск по имени"], ["Enter", "поставить / открыть папку"], ["Backspace", "стереть поиск / вверх"],
                ["Alt + ← →", "назад / вперёд"], ["Alt + ↑", "на уровень выше"], ["Ctrl + D", "закрепить папку"] ] },
            { title: "Мышь", rows: [
                ["ЛКМ по картинке", "просмотр"], ["ПКМ по картинке", "сразу поставить"], ["ПКМ по папке", "закрепить / открепить"],
                ["ЛКМ по монитору", "включить / выключить монитор"], ["ПКМ по монитору", "только он"], ["Верхняя полоса окна", "перетащить (между мониторами тоже)"],
                ["Двойной клик по верхней полосе", "вернуть на место"] ] },
            { title: "Просмотр", rows: [
                ["← → ↑ ↓", "соседние картинки"], ["Enter / Пробел", "установить"], ["S", "сохранить (онлайн)"], ["Esc / Backspace", "закрыть просмотр"] ] },
            { title: "Онлайн", rows: [
                ["← → ↑ ↓", "выбор плитки"], ["Пробел", "просмотр"], ["Enter", "скачать и поставить"], ["Esc", "выйти из источника"] ] },
            { title: "Разбор загрузок", rows: [
                ["→ / Пробел", "оставить в Избранное"], ["Del / X", "в корзину"], ["Enter", "поставить на обои"],
                ["↓ / S", "пропустить"], ["← / Ctrl+Z", "назад / отменить"], ["1 – 9", "в закреплённую папку"], ["H", "размытие"] ] },
            { title: "На плитках", rows: [
                ["глаз", "размытие превью (запоминается)"], ["папка", "перенести файл в папку"], ["корзина", "удалить файл"], ["стрелка вниз", "скачать (онлайн)"] ] }
        ]

        Text {
            id: helpTitle
            anchors { left: parent.left; top: parent.top; margins: 28 }
            text: "Шпаргалка"
            color: Theme.text
            font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
        }
        Text {
            anchors { left: helpTitle.right; leftMargin: 14; verticalCenter: helpTitle.verticalCenter }
            text: "F1 или Esc — закрыть"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
        Grid {
            anchors { left: parent.left; right: parent.right; top: helpTitle.bottom; margins: 28; topMargin: 20 }
            columns: 3
            columnSpacing: 28
            rowSpacing: 22
            Repeater {
                model: help.groups
                Column {
                    required property var modelData
                    width: (parent.width - 56) / 3
                    spacing: 6
                    Text {
                        text: modelData.title
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
                    }
                    Repeater {
                        model: modelData.rows
                        Row {
                            required property var modelData
                            spacing: 10
                            Rectangle {
                                height: 24
                                width: Math.max(28, kc.implicitWidth + 14)
                                radius: 7
                                color: Theme.strong
                                Text { id: kc; anchors.centerIn: parent; text: modelData[0]; color: Theme.text; font { family: Theme.font; pixelSize: 12; weight: Font.Medium } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData[1]
                                color: Theme.muted
                                font { family: Theme.font; pixelSize: 12 }
                            }
                        }
                    }
                }
            }
        }
    }
}
