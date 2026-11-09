pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ИИ-помощник и мультиагентный оркестратор (в стиле T3 Code Orchestration V2 + Quickshell lite).
// Поддерживает:
//   • 3 провайдера (Claude, Codex, Antigravity) с переключением прямо внутри одного треда и бесшовной передачей контекста (Context Handoff: full_thread_summary / delta_since_last_seen);
//   • Режимы взаимодействия (interactionMode: "default" | "plan") и разрешений (permissionMode: "supervised" | "auto-edit" | "full-access");
//   • Очередь сообщений (queuedMessages) и живое перенаправление активного хода (steer / Ctrl+Enter), удержание очереди при ручном Стоп;
//   • Черновики (Stash / Ctrl+S), контекстные чипы (@file, @thread, $skill, ❝ цитаты) и автодополнение файлов;
//   • Неразрушающие git-чекпоинты через теневой индекс (ai-clip checkpoint-capture), просмотр diff по ходу/файлу, откат к чекпоинту и изоляцию в git worktree;
//   • Карточки размышлений (thinking), раскрываемые карточки инструментов с выводом, карточки планов (Proposed Plan) и интерактивные вопросы (AskUserQuestion);
//   • Делегирование подзадач субагентам (delegate_task / ask_agent) в синхронном и параллельном async-режиме с авто-пробуждением родительского треда (Parent Cohort Wake).
Singleton {
    id: root

    // ── активный разговор
    // Элемент log: { role: user|assistant|tool|thinking|plan|subagent|checkpoint, text, error, kind, done, tid, filesJson, output, metaJson }
    readonly property ListModel log: ListModel {}
    readonly property ListModel attachments: ListModel {}    // { path, name, mime, isImage, width, height, size, sizeLabel, excerpt }
    readonly property ListModel contextChips: ListModel {}   // { kind: file|dir|thread|skill|quote, label, value, detail }
    readonly property ListModel queuedMessages: ListModel {} // { qid, text, filesJson, chipsJson, createdAt }

    property string chatId: ""
    property string provider: "claude"                       // claude | agy | codex
    property string sessionId: ""
    property var chatSessions: ({ claude: "", codex: "", agy: "" })
    property var chatLastSeen: ({ claude: 0, codex: 0, agy: 0 })
    property var providersUsed: ["claude"]
    property string cwd: Quickshell.env("HOME")
    property string sourceRoot: ""                           // исходный git root, если чат запущен в изолированном worktree
    property string worktreeBranch: ""
    property string parentChatId: ""
    property bool isSubagentChat: false
    property string subagentStatus: ""

    // Режимы работы
    property string interactionMode: "default"               // "default" (Код) | "plan" (План)
    property string permissionMode: "supervised"             // "supervised" | "auto-edit" | "full-access"
    property bool agent: false                               // совместимость: true при auto-edit / full-access или ручном включении
    property bool imported: false                            // подтянут из консольного клиента
    property bool busy: false
    property bool queueHeld: false                           // очередь на паузе после ручного Стоп
    property bool picking: false                             // открыт выбор файла или выделение области снимка экрана
    property int unread: 0
    property bool windowOpen: false
    property var promptHistory: []                           // история отправленных реплик для навигации стрелками ↑/↓
    property var stashList: []                               // сохранённые черновики [{ id, text, filesJson, chipsJson, ts }]

    // Живая телеметрия текущего хода
    property int turnStartedAt: 0
    property int turnElapsedSec: 0
    property int turnStepCount: 0
    property string currentTurnId: ""
    property string preTurnRef: ""
    property bool wasSteered: false
    property var pendingSteerPayload: null
    property var tokenUsage: ({ input: 0, output: 0, total: 0, maxWindow: 200000, percent: 0 })
    property var activePlan: null                            // { title, plan, ts, status }
    property var turnChangedFiles: []                        // [{ path, status, additions, deletions }]

    // Просмотр diff (модальное окно поверх чата)
    property bool diffOpen: false
    property bool diffLoading: false
    property string diffTitle: ""
    property string diffText: ""
    property string diffRefA: ""
    property string diffRefB: ""

    // Git-состояние текущей рабочей папки
    property var gitInfo: ({ isGit: false, root: "", branch: "", head: "", isWorktree: false, dirtyCount: 0, branches: [], worktrees: [] })
    property var fileMatches: []                             // результаты поиска файлов для @-меню

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.local/share/qs-ai"
    readonly property string stateFile: home + "/.local/state/qs-lite-ai.json"
    readonly property string mcpFile: dir + "/mcp.json"
    readonly property string mcpCmd: home + "/.local/bin/qs-mcp"
    readonly property string clipCmd: home + "/.local/bin/ai-clip"

    // Таймер секундомера активного хода и размышлений
    Timer {
        id: turnTickTimer
        interval: 1000
        repeat: true
        running: root.busy
        onTriggered: {
            if (root.turnStartedAt > 0)
                root.turnElapsedSec = Math.max(1, Math.floor(Date.now() / 1000) - root.turnStartedAt)
        }
    }

    // Унифицированное добавление записи в ListModel log (все поля гарантированно одного типа)
    function appendLog(item) {
        log.append({
            role: String(item.role ?? "assistant"),
            text: String(item.text ?? ""),
            error: Boolean(item.error ?? false),
            kind: String(item.kind ?? ""),
            done: Boolean(item.done !== undefined ? item.done : true),
            tid: String(item.tid ?? ""),
            filesJson: String(item.filesJson ?? ""),
            output: String(item.output ?? ""),
            metaJson: String(item.metaJson ?? "")
        })
    }

    // ── Вложения и вставка
    function addAttachments(items) {
        for (const it of items ?? []) {
            if (!it || !it.path) continue
            let exists = false
            for (let i = 0; i < attachments.count; i++) if (attachments.get(i).path === it.path) { exists = true; break }
            if (!exists) attachments.append({
                path: String(it.path),
                name: String(it.name || it.path.split("/").pop()),
                mime: String(it.mime || ""),
                isImage: Boolean(it.isImage),
                width: Number(it.width || 0),
                height: Number(it.height || 0),
                size: Number(it.size || 0),
                sizeLabel: String(it.sizeLabel || ""),
                excerpt: String(it.excerpt || "")
            })
        }
    }
    function removeAttachment(idx) { if (idx >= 0 && idx < attachments.count) attachments.remove(idx) }
    function clearAttachments() { attachments.clear() }
    function attachPath(path) {
        if (!path || aiAttachProc.running) return
        aiAttachProc.command = [clipCmd, "inspect", path]
        aiAttachProc.running = true
    }
    Process {
        id: aiAttachProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.items) root.addAttachments(d.items)
                } catch (e) {}
            }
        }
    }

    // ── Контекстные чипы (@file, @thread, $skill, ❝ quote)
    function addContextChip(kind, label, value, detail) {
        value = String(value ?? label ?? "")
        if (!value) return
        for (let i = 0; i < contextChips.count; i++) {
            if (contextChips.get(i).kind === kind && contextChips.get(i).value === value) return
        }
        contextChips.append({
            kind: String(kind || "file"),
            label: String(label || value),
            value: value,
            detail: String(detail || "")
        })
    }
    function removeContextChip(idx) {
        if (idx >= 0 && idx < contextChips.count) contextChips.remove(idx)
    }
    function clearContextChips() { contextChips.clear() }
    function quoteText(snippet, sourceLabel) {
        const clean = String(snippet ?? "").trim()
        if (!clean) return
        const shortLabel = sourceLabel ? sourceLabel : (clean.slice(0, 32).replace(/\s+/g, " ") + (clean.length > 32 ? "…" : ""))
        addContextChip("quote", "❝ " + shortLabel, clean, sourceLabel || "Цитата из ответа")
    }
    function serializeChips(chipsArr) {
        if (!chipsArr || !chipsArr.length) return ""
        const parts = []
        for (const ch of chipsArr) {
            if (ch.kind === "file" || ch.kind === "dir") {
                parts.push("[Контекст @" + ch.label + ": `" + ch.value + "` — изучи этот путь при ответе]")
            } else if (ch.kind === "thread") {
                const tc = db.chats.find(x => x.id === ch.value)
                if (tc && tc.log) {
                    const ex = tc.log.filter(m => (m.role === "user" || m.role === "assistant") && m.text)
                                     .slice(-8)
                                     .map(m => (m.role === "user" ? "Пользователь: " : "Помощник: ") + m.text.slice(0, 500))
                                     .join("\n")
                    parts.push("[Контекст из треда «" + (tc.title || ch.label) + "» (`" + tc.id + "`):\n" + ex + "\n]")
                }
            } else if (ch.kind === "skill") {
                parts.push("[Активируй скилл `" + ch.label + "`" + (ch.detail ? " (инструкция: `" + ch.detail + "`)" : "") + "]")
            } else if (ch.kind === "quote") {
                parts.push("Цитата (" + (ch.label || "фрагмент") + "):\n> " + String(ch.value).split("\n").join("\n> "))
            }
        }
        return parts.length ? parts.join("\n\n") + "\n\n" : ""
    }

    // ── Поиск файлов в рабочей папке для @-автодополнения
    function searchFiles(query) {
        fileSearchProc.pendingQuery = String(query ?? "")
        fileSearchDebounce.restart()
    }
    Timer {
        id: fileSearchDebounce
        interval: 90
        onTriggered: {
            if (fileSearchProc.running) fileSearchProc.running = false
            fileSearchProc.command = [root.clipCmd, "search-files", root.cwd, fileSearchProc.pendingQuery]
            fileSearchProc.running = true
        }
    }
    Process {
        id: fileSearchProc
        property string pendingQuery: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.fileMatches = d.items ?? []
                } catch (e) { root.fileMatches = [] }
            }
        }
    }

    // ── Git и Worktree механики + неразрушающие чекпоинты
    function refreshGitInfo() {
        if (!cwd || gitInfoProc.running) return
        gitInfoProc.command = [clipCmd, "git-info", cwd]
        gitInfoProc.running = true
    }
    Process {
        id: gitInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.gitInfo = JSON.parse(text)
                } catch (e) {
                    root.gitInfo = { isGit: false, root: "", branch: "", head: "", isWorktree: false, dirtyCount: 0, branches: [], worktrees: [] }
                }
            }
        }
    }
    function switchGitBranch(branch, createNew) {
        if (!branch || gitBranchProc.running) return
        const args = [clipCmd, "git-branch", cwd, branch]
        if (createNew) args.push("--create")
        gitBranchProc.command = args
        gitBranchProc.running = true
    }
    Process {
        id: gitBranchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshGitInfo()
            }
        }
    }
    function createWorktreeForChat(slug) {
        if (busy || gitWorktreeProc.running) return
        gitWorktreeProc.mode = "create"
        gitWorktreeProc.command = [clipCmd, "git-worktree", cwd, "create", slug || chatId || uid()]
        gitWorktreeProc.running = true
    }
    function mergeWorktreeBack() {
        if (busy || gitWorktreeProc.running) return
        gitWorktreeProc.mode = "merge-back"
        gitWorktreeProc.command = [clipCmd, "git-worktree", cwd, "merge-back"]
        gitWorktreeProc.running = true
    }
    Process {
        id: gitWorktreeProc
        property string mode: "create"
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.ok && gitWorktreeProc.mode === "create" && d.path) {
                        root.sourceRoot = d.sourceRoot || root.gitInfo.root || root.cwd
                        root.worktreeBranch = d.branch || ""
                        root.cwd = d.path
                        root.save()
                        root.refreshGitInfo()
                    } else if (d.ok && gitWorktreeProc.mode === "merge-back") {
                        const targetRoot = d.sourceRoot || root.sourceRoot
                        if (targetRoot) root.cwd = targetRoot
                        root.worktreeBranch = ""
                        root.save()
                        root.refreshGitInfo()
                    }
                } catch (e) {}
            }
        }
    }

    function viewTurnDiff(refA, refB, filePath, title) {
        diffTitle = title || (filePath ? "Diff · " + filePath : "Изменения за ход")
        diffRefA = refA || ""
        diffRefB = refB || ""
        diffText = ""
        diffLoading = true
        diffOpen = true
        if (diffProc.running) diffProc.running = false
        const args = [clipCmd, "checkpoint-diff", cwd, refA || "HEAD", refB || ""]
        if (filePath) args.push(filePath)
        diffProc.command = args
        diffProc.running = true
    }
    function closeDiff() { diffOpen = false }
    Process {
        id: diffProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.diffLoading = false
                try {
                    const d = JSON.parse(text)
                    root.diffText = d.ok ? (d.diff || "Нет отличий.") : ("Ошибка diff: " + (d.error || ""))
                } catch (e) {
                    root.diffText = text || "Не удалось загрузить diff."
                }
            }
        }
    }
    function restoreCheckpoint(ref) {
        if (!ref || busy || restoreCheckpointProc.running) return
        restoreCheckpointProc.targetRef = ref
        restoreCheckpointProc.command = [clipCmd, "checkpoint-restore", cwd, ref]
        restoreCheckpointProc.running = true
    }
    Process {
        id: restoreCheckpointProc
        property string targetRef: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.ok) {
                        root.appendLog({
                            role: "checkpoint",
                            text: "Рабочая папка откачена к чекпоинту " + restoreCheckpointProc.targetRef.split("/").pop(),
                            done: true,
                            tid: restoreCheckpointProc.targetRef,
                            metaJson: JSON.stringify({ restored: true, ref: restoreCheckpointProc.targetRef })
                        })
                        root.save()
                        root.refreshGitInfo()
                    }
                } catch (e) {}
            }
        }
    }

    // ── Черновики (Prompt Stash / Ctrl+S)
    function collectCurrentAttachments() {
        const out = []
        for (let i = 0; i < attachments.count; i++) {
            const a = attachments.get(i)
            out.push({ path: a.path, name: a.name, mime: a.mime, isImage: a.isImage, width: a.width, height: a.height, size: a.size, sizeLabel: a.sizeLabel, excerpt: a.excerpt })
        }
        return out
    }
    function collectCurrentChips() {
        const out = []
        for (let i = 0; i < contextChips.count; i++) {
            const c = contextChips.get(i)
            out.push({ kind: c.kind, label: c.label, value: c.value, detail: c.detail })
        }
        return out
    }
    function stashDraft(text) {
        text = String(text ?? "").trim()
        const files = collectCurrentAttachments()
        const chips = collectCurrentChips()
        if (!text && !files.length && !chips.length) return false
        const item = {
            id: uid(),
            text: text,
            filesJson: files.length ? JSON.stringify(files) : "",
            chipsJson: chips.length ? JSON.stringify(chips) : "",
            ts: Math.floor(Date.now() / 1000)
        }
        stashList = [item].concat(stashList.slice(0, 19))
        clearAttachments()
        clearContextChips()
        save()
        return true
    }
    function popStash(id) {
        const item = stashList.find(x => x.id === id)
        if (!item) return ""
        stashList = stashList.filter(x => x.id !== id)
        clearAttachments()
        clearContextChips()
        if (item.filesJson) { try { addAttachments(JSON.parse(item.filesJson)) } catch (e) {} }
        if (item.chipsJson) {
            try {
                for (const c of JSON.parse(item.chipsJson)) addContextChip(c.kind, c.label, c.value, c.detail)
            } catch (e) {}
        }
        save()
        return item.text || ""
    }
    function removeStash(id) {
        stashList = stashList.filter(x => x.id !== id)
        save()
    }

    // ── Очередь сообщений и живое перенаправление (Queue & Steer)
    function enqueueMessage(text, customFiles, customChips) {
        text = String(text ?? "").trim()
        const files = customFiles !== undefined ? customFiles : collectCurrentAttachments()
        const chips = customChips !== undefined ? customChips : collectCurrentChips()
        if (!text && !files.length && !chips.length) return
        queuedMessages.append({
            qid: uid(),
            text: text,
            filesJson: files.length ? JSON.stringify(files) : "",
            chipsJson: chips.length ? JSON.stringify(chips) : "",
            createdAt: Math.floor(Date.now() / 1000)
        })
        if (customFiles === undefined) clearAttachments()
        if (customChips === undefined) clearContextChips()
    }
    function removeQueued(idx) {
        if (idx >= 0 && idx < queuedMessages.count) queuedMessages.remove(idx)
    }
    function moveQueued(idx, delta) {
        const target = idx + delta
        if (idx >= 0 && idx < queuedMessages.count && target >= 0 && target < queuedMessages.count)
            queuedMessages.move(idx, target, 1)
    }
    function popQueued(idx) {
        if (idx < 0 || idx >= queuedMessages.count) return ""
        const q = queuedMessages.get(idx)
        const text = q.text
        const fJson = q.filesJson
        const cJson = q.chipsJson
        queuedMessages.remove(idx)
        clearAttachments()
        clearContextChips()
        if (fJson) { try { addAttachments(JSON.parse(fJson)) } catch (e) {} }
        if (cJson) {
            try {
                for (const c of JSON.parse(cJson)) addContextChip(c.kind, c.label, c.value, c.detail)
            } catch (e) {}
        }
        return text
    }
    function promoteQueuedToSteer(idx) {
        if (idx < 0 || idx >= queuedMessages.count) return
        const q = queuedMessages.get(idx)
        let files = []
        let chips = []
        if (q.filesJson) { try { files = JSON.parse(q.filesJson) } catch (e) {} }
        if (q.chipsJson) { try { chips = JSON.parse(q.chipsJson) } catch (e) {} }
        const text = q.text
        queuedMessages.remove(idx)
        steer(text, files, chips)
    }
    function steer(text, customFiles, customChips) {
        text = String(text ?? "").trim()
        const files = customFiles !== undefined ? customFiles : collectCurrentAttachments()
        const chips = customChips !== undefined ? customChips : collectCurrentChips()
        if (!text && !files.length && !chips.length) return
        if (customFiles === undefined) clearAttachments()
        if (customChips === undefined) clearContextChips()
        queueHeld = false
        if (!busy) {
            sendInternal(text, files, chips, "steered")
            return
        }
        pendingSteerPayload = { text: text, files: files, chips: chips, mode: "steered" }
        wasSteered = true
        denyAll()
        proc.running = false
    }
    function resumeQueue() {
        queueHeld = false
        if (!busy && queuedMessages.count > 0) drainQueueTimer.restart()
    }
    Timer {
        id: drainQueueTimer
        interval: 160
        onTriggered: {
            if (root.busy || root.queueHeld || root.queuedMessages.count === 0) return
            const q = root.queuedMessages.get(0)
            let files = []
            let chips = []
            if (q.filesJson) { try { files = JSON.parse(q.filesJson) } catch (e) {} }
            if (q.chipsJson) { try { chips = JSON.parse(q.chipsJson) } catch (e) {} }
            const text = q.text
            root.queuedMessages.remove(0)
            root.sendInternal(text, files, chips, "queued")
        }
    }

    // ── Чаты, сессии провайдеров и передача контекста (Context Handoff)
    property var db: ({ active: "", chats: [] })
    property var chatList: []
    readonly property var providers: [
        { id: "claude", label: "Claude" },
        { id: "agy", label: "Antigravity" },
        { id: "codex", label: "Codex" }
    ]

    function uid() { return Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36) }

    function refreshList() {
        const now = Math.floor(Date.now() / 1000)
        chatList = db.chats.map(c => ({
            id: c.id,
            provider: c.provider,
            providersUsed: c.providersUsed ?? [c.provider],
            title: c.title || "Новый чат",
            updated: c.updated || 0,
            count: (c.log ?? []).length,
            imported: !!c.imported,
            pinned: !!c.pinned,
            settled: !!c.settled,
            snoozedUntil: c.snoozedUntil || 0,
            isSnoozed: (c.snoozedUntil || 0) > now,
            parentId: c.parentId || "",
            isSubagent: !!c.isSubagent,
            subagentStatus: c.subagentStatus || "",
            worktreeBranch: c.worktreeBranch || "",
            cwd: c.cwd || home,
            interactionMode: c.interactionMode || "default",
            hasActivePlan: !!c.activePlan
        })).sort((a, b) => {
            if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
            return b.updated - a.updated
        })
    }

    function snapshot() {
        const out = []
        for (let i = Math.max(0, log.count - 120); i < log.count; i++) {
            const m = log.get(i)
            if (m.text !== "" || m.role === "tool" || m.role === "subagent" || m.role === "plan" || m.role === "checkpoint" || (m.filesJson && m.filesJson !== "" && m.filesJson !== "[]"))
                out.push({
                    role: m.role,
                    text: m.text,
                    error: m.error,
                    kind: m.kind,
                    done: m.done,
                    tid: m.tid,
                    filesJson: m.filesJson || "",
                    output: (m.output || "").slice(0, 4000),
                    metaJson: m.metaJson || ""
                })
        }
        return out
    }

    function syncCurrent() {
        const c = db.chats.find(x => x.id === chatId)
        if (!c) return
        c.provider = provider
        c.session = sessionId
        const sess = Object.assign({ claude: "", codex: "", agy: "" }, c.sessions ?? {}, chatSessions)
        if (sessionId) sess[provider] = sessionId
        c.sessions = sess
        c.lastSeenCount = Object.assign({ claude: 0, codex: 0, agy: 0 }, c.lastSeenCount ?? {}, chatLastSeen)
        c.providersUsed = providersUsed && providersUsed.length ? providersUsed : [provider]
        c.cwd = cwd
        c.sourceRoot = sourceRoot
        c.worktreeBranch = worktreeBranch
        c.parentId = parentChatId
        c.isSubagent = isSubagentChat
        c.subagentStatus = subagentStatus
        c.interactionMode = interactionMode
        c.permissionMode = permissionMode
        c.agent = agent
        c.imported = imported
        c.activePlan = activePlan
        c.tokenUsage = tokenUsage
        c.log = snapshot()
        if (log.count > 0) c.updated = Math.floor(Date.now() / 1000)
        const first = c.log.find(m => m.role === "user")
        if (first && (c.title === "" || c.title === "Новый чат")) {
            const rawTitle = first.text ? first.text.split("\n")[0].slice(0, 70) : "Вложение"
            c.title = rawTitle || "Вложение"
        }
    }

    function save() {
        syncCurrent()
        if (db.chats.length > 80) {
            db.chats = db.chats.sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || (b.updated - a.updated)).slice(0, 80)
        }
        db.active = chatId
        refreshList()
        file.setText(JSON.stringify({
            active: db.active,
            chats: db.chats,
            limits: limits,
            stash: stashList
        }))
    }

    function loadChat(c) {
        log.clear()
        chatId = c.id
        provider = c.provider || "claude"
        const sess = Object.assign({ claude: "", codex: "", agy: "" }, c.sessions ?? {})
        if (c.session && !sess[provider]) sess[provider] = c.session
        chatSessions = sess
        sessionId = sess[provider] || ""
        chatLastSeen = Object.assign({ claude: 0, codex: 0, agy: 0 }, c.lastSeenCount ?? {})
        providersUsed = (c.providersUsed && c.providersUsed.length) ? c.providersUsed.slice() : [provider]
        cwd = c.cwd || home
        sourceRoot = c.sourceRoot || ""
        worktreeBranch = c.worktreeBranch || ""
        parentChatId = c.parentId || ""
        isSubagentChat = !!c.isSubagent
        subagentStatus = c.subagentStatus || ""
        interactionMode = c.interactionMode || "default"
        permissionMode = c.permissionMode || (c.agent ? "auto-edit" : "supervised")
        agent = !!c.agent || permissionMode !== "supervised"
        imported = !!c.imported
        activePlan = c.activePlan ?? null
        tokenUsage = c.tokenUsage ?? { input: 0, output: 0, total: 0, maxWindow: 200000, percent: 0 }
        turnChangedFiles = []
        for (const m of c.log ?? []) {
            appendLog(m)
            if (m.role === "checkpoint" && m.filesJson) {
                try { turnChangedFiles = JSON.parse(m.filesJson) } catch (e) {}
            }
        }
        refreshGitInfo()
    }

    function newChat(p, opts) {
        if (busy) return ""
        syncCurrent()
        opts = opts ?? {}
        const targetProv = p || provider
        const c = {
            id: opts.id || uid(),
            provider: targetProv,
            providersUsed: [targetProv],
            title: opts.title || "Новый чат",
            session: "",
            sessions: { claude: "", codex: "", agy: "" },
            lastSeenCount: { claude: 0, codex: 0, agy: 0 },
            cwd: opts.cwd || cwd || home,
            sourceRoot: opts.sourceRoot || "",
            worktreeBranch: opts.worktreeBranch || "",
            parentId: opts.parentId || "",
            isSubagent: !!opts.isSubagent,
            subagentStatus: opts.subagentStatus || "",
            interactionMode: opts.interactionMode || "default",
            permissionMode: opts.permissionMode || permissionMode || "supervised",
            agent: opts.agent !== undefined ? !!opts.agent : agent,
            imported: false,
            pinned: false,
            settled: false,
            snoozedUntil: 0,
            activePlan: null,
            updated: Math.floor(Date.now() / 1000),
            log: opts.log || []
        }
        db.chats.push(c)
        loadChat(c)
        save()
        if (opts.worktree) createWorktreeForChat(c.id)
        return c.id
    }

    function openChat(id) {
        if (busy || id === chatId) return
        syncCurrent()
        const c = db.chats.find(x => x.id === id)
        if (c) { loadChat(c); save() }
    }

    function deleteChat(id) {
        if (busy && id === chatId) return
        db.chats = db.chats.filter(c => c.id !== id)
        if (id === chatId) {
            if (db.chats.length === 0) { chatId = ""; newChat(provider) }
            else loadChat(db.chats.slice().sort((a, b) => b.updated - a.updated)[0])
        }
        save()
    }

    // Организация тредов в боковой панели (Pin, Settle/Архив, Snooze, Переименование, Ответвление/Fork)
    function togglePinChat(id) {
        const c = db.chats.find(x => x.id === (id || chatId))
        if (!c) return
        c.pinned = !c.pinned
        save()
    }
    function toggleSettleChat(id) {
        const c = db.chats.find(x => x.id === (id || chatId))
        if (!c) return
        c.settled = !c.settled
        save()
    }
    function snoozeChat(id, durationSec) {
        const c = db.chats.find(x => x.id === (id || chatId))
        if (!c) return
        c.snoozedUntil = durationSec > 0 ? Math.floor(Date.now() / 1000) + durationSec : 0
        save()
    }
    function renameChat(id, newTitle) {
        newTitle = String(newTitle ?? "").trim()
        if (!newTitle) return
        const c = db.chats.find(x => x.id === (id || chatId))
        if (!c) return
        c.title = newTitle.slice(0, 90)
        save()
    }
    function forkChat(sourceId, upToIndex, customTitle) {
        if (busy) return ""
        syncCurrent()
        const src = db.chats.find(x => x.id === (sourceId || chatId))
        if (!src) return ""
        const srcLog = src.log ?? []
        const sliceEnd = (upToIndex !== undefined && upToIndex >= 0) ? Math.min(srcLog.length, upToIndex + 1) : srcLog.length
        const clonedLog = srcLog.slice(0, sliceEnd).map(m => Object.assign({}, m))
        const newId = newChat(src.provider, {
            title: customTitle || ("⑂ " + (src.title || "Чат")),
            cwd: src.cwd || cwd,
            parentId: src.id,
            interactionMode: src.interactionMode || interactionMode,
            permissionMode: src.permissionMode || permissionMode,
            agent: src.agent,
            log: clonedLog
        })
        return newId
    }
    function launchThread(optsJson) {
        let opts = {}
        try { opts = typeof optsJson === "string" ? JSON.parse(optsJson) : (optsJson ?? {}) } catch (e) { return "" }
        if (busy) return ""
        const targetProv = opts.agent || opts.provider || provider
        if (opts.model) setPref(targetProv, "model", opts.model)
        if (opts.effort) setPref(targetProv, "effort", opts.effort)
        const id = newChat(targetProv, {
            id: opts.id || uid(),
            title: opts.title || "Новый чат",
            cwd: opts.cwd || cwd,
            interactionMode: opts.mode || "default",
            permissionMode: opts.permission_mode || permissionMode,
            worktree: opts.isolation === "worktree"
        })
        if (opts.prompt) send(opts.prompt)
        return id
    }

    function clear() {
        stop()
        log.clear()
        attachments.clear()
        contextChips.clear()
        queuedMessages.clear()
        sessionId = ""
        chatSessions = { claude: "", codex: "", agy: "" }
        chatLastSeen = { claude: 0, codex: 0, agy: 0 }
        providersUsed = [provider]
        activePlan = null
        turnChangedFiles = []
        tokenUsage = { input: 0, output: 0, total: 0, maxWindow: 200000, percent: 0 }
        unread = 0
        const c = db.chats.find(x => x.id === chatId)
        if (c) c.title = "Новый чат"
        save()
    }

    // Переключение провайдера ВНУТРИ текущего треда (как в T3 Code):
    // сохраняет текущую сессию старого провайдера и переключает активного провайдера с автоматическим Context Handoff!
    function setProvider(p, forceNewChat) {
        if (!p || busy) return
        if (forceNewChat) {
            newChat(p)
            return
        }
        if (p === provider) return
        const sess = Object.assign({ claude: "", codex: "", agy: "" }, chatSessions)
        if (sessionId) sess[provider] = sessionId
        chatSessions = sess
        provider = p
        sessionId = sess[p] || ""
        if (providersUsed.indexOf(p) < 0) providersUsed = providersUsed.concat([p])
        save()
    }

    function setInteractionMode(mode) {
        if (busy) return
        interactionMode = (mode === "plan") ? "plan" : "default"
        save()
    }
    function toggleInteractionMode() {
        setInteractionMode(interactionMode === "plan" ? "default" : "plan")
    }
    function setPermissionMode(mode) {
        if (busy) return
        if (["supervised", "auto-edit", "full-access"].indexOf(mode) < 0) mode = "supervised"
        permissionMode = mode
        agent = (mode !== "supervised")
        if (agent && provider !== "claude" && cwd === home) cwd = dir + "/work"
        save()
    }
    function cyclePermissionMode() {
        const order = ["supervised", "auto-edit", "full-access"]
        const next = order[(order.indexOf(permissionMode) + 1) % order.length]
        setPermissionMode(next)
    }
    function setAgent(on) {
        if (busy) return
        agent = !!on
        permissionMode = agent ? (permissionMode === "full-access" ? "full-access" : "auto-edit") : "supervised"
        if (agent && provider !== "claude" && cwd === home) cwd = dir + "/work"
        save()
    }
    function setCwd(path) {
        path = String(path ?? "").trim().replace(/^~/, home)
        if (path !== "" && !busy) {
            cwd = path
            save()
            refreshGitInfo()
        }
    }

    // ── Передача контекста между агентами внутри одного треда (T3 Code ContextHandoffService)
    function buildContextHandoff(targetProvider) {
        const lastSeen = Number(chatLastSeen[targetProvider] || 0)
        // Исключаем только что добавленные в конец user + пустой assistant текущего хода
        const endIdx = Math.max(0, log.count - 2)
        if (endIdx <= 0) return ""
        const hasPriorOtherProvider = providersUsed.length > 1 || (sessionId === "" && endIdx > 0)
        if (!hasPriorOtherProvider && lastSeen >= endIdx) return ""

        const startIdx = (sessionId !== "" && lastSeen > 0 && lastSeen < endIdx) ? lastSeen : Math.max(0, endIdx - 24)
        const mode = (sessionId !== "" && lastSeen > 0) ? "delta_since_last_seen" : "full_thread_summary"
        const lines = []
        for (let i = startIdx; i < endIdx; i++) {
            const m = log.get(i)
            if (m.error) continue
            if (m.role === "user" && m.text) {
                lines.push("Пользователь: " + m.text.slice(0, 900))
            } else if (m.role === "assistant" && m.text) {
                let pTag = "Помощник"
                if (m.metaJson) {
                    try { const md = JSON.parse(m.metaJson); if (md.provider) pTag = "Помощник (" + md.provider + (md.model ? "/" + md.model : "") + ")" } catch (e) {}
                }
                lines.push(pTag + ": " + m.text.slice(0, 1000))
            } else if (m.role === "tool" && m.text) {
                lines.push("[Инструмент " + m.kind + ": " + m.text.split("\n")[0].slice(0, 160) + (m.output ? " → " + m.output.slice(0, 200) : "") + "]")
            } else if (m.role === "subagent" && m.text) {
                lines.push("[Субагент " + m.kind + ": " + m.text.slice(0, 240) + (m.output ? "\nРезультат: " + m.output.slice(0, 600) : "") + "]")
            } else if (m.role === "plan" && m.text) {
                lines.push("[Предложенный план:\n" + m.text.slice(0, 1200) + "\n]")
            }
        }
        if (!lines.length && !activePlan) return ""
        let out = "<context_handoff mode=\"" + mode + "\" target_provider=\"" + targetProvider + "\">\n"
        out += "В этом треде участвуют несколько ИИ-агентов (" + providersUsed.join(" → ") + "). Ниже приведена " +
               (mode === "delta_since_last_seen" ? "дельта событий в треде с момента твоего последнего ответа" : "сводка предыдущего хода диалога") + ":\n\n"
        if (activePlan && activePlan.plan) {
            out += "## Активный план треда («" + (activePlan.title || "План") + "»):\n" + activePlan.plan.slice(0, 1800) + "\n\n"
        }
        out += lines.join("\n\n") + "\n</context_handoff>\n\n"
        return out
    }

    // ── Откат и редактирование сообщения / Перегенерация ответа
    function revertAndEditFrom(userMsgIndex, restoreGit) {
        if (busy || userMsgIndex < 0 || userMsgIndex >= log.count) return ""
        const targetMsg = log.get(userMsgIndex)
        const text = targetMsg.text || ""
        const fJson = targetMsg.filesJson || ""
        // Если нужно откатить git к чекпоинту перед этим ходом
        if (restoreGit) {
            for (let i = userMsgIndex; i < log.count; i++) {
                const m = log.get(i)
                if (m.role === "checkpoint" && m.metaJson) {
                    try {
                        const meta = JSON.parse(m.metaJson)
                        if (meta.prevRef) { restoreCheckpoint(meta.prevRef); break }
                    } catch (e) {}
                }
            }
        }
        while (log.count > userMsgIndex) log.remove(log.count - 1)
        // Сбрасываем нативные сессии, чтобы следующий ход пошёл с чистой точки и подхватил усечённую историю
        sessionId = ""
        chatSessions = { claude: "", codex: "", agy: "" }
        chatLastSeen = { claude: 0, codex: 0, agy: 0 }
        clearAttachments()
        if (fJson) { try { addAttachments(JSON.parse(fJson)) } catch (e) {} }
        save()
        return text
    }

    function regenerateLast() {
        if (busy || log.count === 0) return
        let lastUserIdx = -1
        for (let i = log.count - 1; i >= 0; i--) {
            if (log.get(i).role === "user") { lastUserIdx = i; break }
        }
        if (lastUserIdx < 0) return
        const u = log.get(lastUserIdx)
        const text = u.text
        let files = []
        if (u.filesJson) { try { files = JSON.parse(u.filesJson) } catch (e) {} }
        while (log.count > lastUserIdx) log.remove(log.count - 1)
        sessionId = ""
        chatSessions = { claude: "", codex: "", agy: "" }
        chatLastSeen = { claude: 0, codex: 0, agy: 0 }
        sendInternal(text, files, [], "regenerated")
    }

    // ── Модели и effort
    property var catalog: ({})
    readonly property var prefs: { try { return JSON.parse(Session.aiPrefs) } catch (e) { return {} } }
    readonly property var effortOrder: ["low", "medium", "high", "xhigh", "max", "ultra"]
    function modelsOf(p) { return catalog[p]?.models ?? [] }
    function pref(p, key) {
        const v = prefs[p]?.[key]
        if (v !== undefined) return v
        if (key === "model") {
            if (p === "claude") return "claude-sonnet-5-5"
            if (p === "agy") return modelsOf("agy")[0]?.id ?? "gemini-3.8-flash"
            return catalog.codex?.default_model || modelsOf("codex")[0]?.id || ""
        }
        return p === "codex" ? (catalog.codex?.default_effort ?? "") : p === "agy" ? "medium" : ""
    }
    function setPref(p, key, value) {
        const o = Object.assign({}, prefs); o[p] = Object.assign({}, o[p] ?? {}, { [key]: value })
        Session.aiPrefs = JSON.stringify(o)
    }
    readonly property var currentModel: modelsOf(provider).find(m => m.id === pref(provider, "model")) ?? null
    readonly property var efforts: {
        let e = provider === "claude" ? (catalog.claude?.efforts ?? []) : (currentModel?.efforts ?? [])
        return effortOrder.filter(x => e.indexOf(x) >= 0)
    }
    readonly property string model: pref(provider, "model")
    readonly property string effort: pref(provider, "effort")

    // ── Лимиты подписок
    property var limits: ({})
    function limitRows(p) {
        const L = limits[p] ?? {}
        const rows = []
        if (p === "agy") {
            const g = (model.startsWith("gemini") ? L.gemini : L.other) ?? {}
            if (g.five) rows.push({ label: "5 ч", used: 1 - g.five.left, reset: g.five.reset })
            if (g.week) rows.push({ label: "неделя", used: 1 - g.week.left, reset: g.week.reset })
        } else {
            if (L.five) rows.push({ label: "5 ч", used: L.five.used, reset: L.five.reset })
            if (L.week) rows.push({ label: "неделя", used: L.week.used, reset: L.week.reset })
        }
        return rows
    }
    function setLimits(p, v) { const l = Object.assign({}, limits); l[p] = v; l.ts = Math.floor(Date.now() / 1000); limits = l }
    property bool limitsBusy: false
    function refreshLimits(withClaude) {
        if (busy) return
        const now = Math.floor(Date.now() / 1000)
        if (!withClaude && limits.ts && (now - limits.ts < 180)) return
        if (!limitsProc.running) limitsProc.running = true
        if (withClaude && !claudePing.running && !busy) claudePing.running = true
    }
    Timer {
        id: postTurnLimitsTimer
        interval: 5000
        onTriggered: if (!root.busy) root.refreshLimits(false)
    }
    Process {
        id: limitsProc
        command: [root.home + "/.local/bin/ai-limits", "all"]
        onRunningChanged: root.limitsBusy = running || claudePing.running
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.codex && Object.keys(d.codex).length) root.setLimits("codex", d.codex)
                    if (d.agy && Object.keys(d.agy).length) root.setLimits("agy", d.agy)
                    root.save()
                } catch (e) {}
            }
        }
    }
    Process {
        id: claudePing
        workingDirectory: root.dir
        command: ["sh", "-c", 'exec claude -p "." --tools "" --strict-mcp-config --disable-slash-commands --model claude-haiku-4-5-20251001 --output-format stream-json --verbose --no-session-persistence </dev/null']
        onRunningChanged: root.limitsBusy = running || limitsProc.running
        stdout: SplitParser { onRead: line => root.parseClaudeLimits(line) }
    }
    function parseClaudeLimits(line) {
        let d = null
        try { d = JSON.parse(line) } catch (e) { return }
        if (d.type !== "rate_limit_event") return
        const w = d.rate_limit_info?.unifiedWindows ?? {}
        const o = {}
        if (w.five_hour) o.five = { used: w.five_hour.utilization, reset: w.five_hour.resetsAt }
        if (w.seven_day) o.week = { used: w.seven_day.utilization, reset: w.seven_day.resetsAt }
        if (Object.keys(o).length) { setLimits("claude", o); save() }
    }

    // ── Подтверждения действий агента (Tool Approvals)
    readonly property ListModel approvals: ListModel {}      // { rid, tool, title, detail }
    property var pendingSockets: ({})
    property var alwaysAllow: ({})
    function summarize(tool, input) {
        input = input ?? {}
        if (tool === "call_mcp_tool" && input.ToolName) {
            tool = (input.ServerName ? input.ServerName + ": " : "") + input.ToolName
            input = input.Arguments ?? {}
        }
        const t = String(tool || "tool").replace(/^mcp__qs__/, "qs: ")
        const act = input.action ? input.action + (input.widget ? " · " + input.widget : input.target ? " · " + input.target : input.text ? " · " + input.text : input.value ? " · " + input.value : "") : null
        const v = input.command ?? input.CommandLine ?? input.file_path ?? input.path ?? input.AbsolutePath ?? input.TargetFile
                  ?? input.pattern ?? input.Pattern ?? input.query ?? input.Query ?? input.url ?? input.Url
                  ?? (input.agent && input.prompt ? input.agent + ": " + input.prompt : null)
                  ?? act ?? input.prompt ?? input.Prompt ?? ""
        const s = typeof v === "string" && v !== "" ? v : Object.keys(input).length ? JSON.stringify(input) : ""
        return { title: t, detail: s.length > 400 ? s.slice(0, 400) + "…" : s }
    }
    function requestApproval(payloadText, sock) {
        let p = null
        try { p = JSON.parse(payloadText) } catch (e) { sock.write("deny\n"); sock.flush(); return }
        if (permissionMode === "full-access" || alwaysAllow[p.tool]) { sock.write("allow\n"); sock.flush(); return }
        if (permissionMode === "auto-edit" && ["Edit", "Write", "MultiEdit", "Read", "Glob", "Grep"].indexOf(p.tool) >= 0) {
            sock.write("allow\n"); sock.flush(); return
        }
        const rid = uid()
        const sm = summarize(p.tool, p.input)
        const m = Object.assign({}, pendingSockets); m[rid] = sock; pendingSockets = m
        approvals.append({ rid: rid, tool: p.tool, title: sm.title, detail: sm.detail })
        if (!windowOpen) Quickshell.execDetached(["notify-send", "-a", "Помощник", "Нужно разрешение", sm.title + (sm.detail ? ": " + sm.detail.slice(0, 120) : "")])
    }
    function resolveApproval(rid, decision, always) {
        for (let i = 0; i < approvals.count; i++) {
            if (approvals.get(i).rid !== rid) continue
            if (always && decision === "allow") { const a = Object.assign({}, alwaysAllow); a[approvals.get(i).tool] = true; alwaysAllow = a }
            approvals.remove(i)
            break
        }
        const s = pendingSockets[rid]
        if (s) { try { s.write(decision + "\n"); s.flush() } catch (e) {} }
        const m = Object.assign({}, pendingSockets); delete m[rid]; pendingSockets = m
    }
    function denyAll() { for (let i = approvals.count - 1; i >= 0; i--) resolveApproval(approvals.get(i).rid, "deny", false) }

    // ── Интерактивные вопросы пользователю (AskUserQuestion из qs-mcp)
    property var pendingQuestion: null                       // { qid, questions: [{ id, header, question, options: [{ label, description }], multiSelect }] }
    property var questionSocket: null
    function requestQuestion(payloadText, sock) {
        let p = null
        try { p = JSON.parse(payloadText) } catch (e) { sock.write(JSON.stringify({ cancelled: true }) + "\n"); sock.flush(); return }
        if (questionSocket) {
            try { questionSocket.write(JSON.stringify({ cancelled: true }) + "\n"); questionSocket.flush() } catch (e) {}
        }
        questionSocket = sock
        pendingQuestion = {
            qid: uid(),
            questions: p.questions ?? []
        }
        if (!windowOpen) Quickshell.execDetached(["notify-send", "-a", "Помощник", "Вопрос от помощника", (p.questions?.[0]?.question ?? "Откройте чат для ответа").slice(0, 120)])
    }
    function answerQuestion(answersMap) {
        const s = questionSocket
        questionSocket = null
        pendingQuestion = null
        if (s) {
            try {
                s.write(JSON.stringify({ answers: answersMap ?? {} }) + "\n")
                s.flush()
            } catch (e) {}
        }
    }
    function cancelQuestion() {
        const s = questionSocket
        questionSocket = null
        pendingQuestion = null
        if (s) {
            try {
                s.write(JSON.stringify({ cancelled: true }) + "\n")
                s.flush()
            } catch (e) {}
        }
    }

    // ── Карточки плана (ProposedPlanCard) и переход План → Выполнение
    function receivePlan(payloadText) {
        let p = null
        try { p = typeof payloadText === "string" ? JSON.parse(payloadText) : payloadText } catch (e) { return }
        if (!p || !p.plan) return
        const title = p.title || "План реализации"
        const planObj = { title: title, plan: p.plan, ts: p.ts || Math.floor(Date.now() / 1000), status: "proposed" }
        activePlan = planObj
        appendLog({
            role: "plan",
            text: p.plan,
            kind: title,
            done: true,
            tid: "plan_" + uid(),
            metaJson: JSON.stringify(planObj)
        })
        save()
    }
    function implementPlan(inNewThread, targetProvider) {
        if (!activePlan || !activePlan.plan || busy) return
        const planTitle = activePlan.title || "План реализации"
        const planBody = activePlan.plan
        const nextProv = targetProvider || provider
        if (inNewThread) {
            newChat(nextProv, {
                title: "⚡ " + planTitle,
                cwd: cwd,
                parentId: chatId,
                interactionMode: "default",
                permissionMode: "auto-edit",
                agent: true
            })
        } else {
            if (nextProv !== provider) setProvider(nextProv, false)
            interactionMode = "default"
            setPermissionMode("auto-edit")
        }
        if (activePlan) activePlan = Object.assign({}, activePlan, { status: "implementing" })
        const execPrompt = "Реализуй утверждённый план «" + planTitle + "» шаг за шагом, проверяя изменения:\n\n<approved_plan>\n" + planBody + "\n</approved_plan>"
        send(execPrompt)
    }
    function dismissPlan() {
        activePlan = null
        save()
    }

    // ── Живые события субагентов (delegate_task / ask_agent) и авто-пробуждение родителя (Parent Cohort Wake)
    property var pendingCohortTasks: ({})                    // { parentChatId: { taskId: meta } }
    function onSubagentEvent(payloadText) {
        let meta = null
        try { meta = JSON.parse(payloadText) } catch (e) { return }
        if (!meta || !meta.taskId) return
        const isDone = meta.status === "completed" || meta.status === "failed" || meta.status === "cancelled"
        const isErr = meta.status === "failed" || meta.status === "cancelled"
        const cardTitle = (meta.title || "Подзадача") + " · " + (meta.agent || "agent") + (meta.model ? " (" + meta.model + (meta.effort ? "/" + meta.effort : "") + ")" : "")

        // 1. Обновляем или создаём карточку role="subagent" в текущем активном чате
        let foundIdx = -1
        for (let i = log.count - 1; i >= 0; i--) {
            if (log.get(i).role === "subagent" && log.get(i).tid === meta.taskId) { foundIdx = i; break }
        }
        if (foundIdx >= 0) {
            log.setProperty(foundIdx, "text", cardTitle + "\n" + (meta.prompt || "").slice(0, 220))
            log.setProperty(foundIdx, "done", isDone)
            log.setProperty(foundIdx, "error", isErr)
            log.setProperty(foundIdx, "output", (meta.resultText || meta.error || "").slice(0, 4000))
            log.setProperty(foundIdx, "metaJson", JSON.stringify(meta))
        } else {
            if (lastEmpty()) log.remove(lastIndex())
            appendLog({
                role: "subagent",
                text: cardTitle + "\n" + (meta.prompt || "").slice(0, 220),
                error: isErr,
                kind: meta.agent || "claude",
                done: isDone,
                tid: meta.taskId,
                output: (meta.resultText || meta.error || "").slice(0, 4000),
                metaJson: JSON.stringify(meta)
            })
        }

        // 2. Создаём или обновляем дочерний тред субагента в db.chats
        const childId = meta.childThreadId || ("sub_" + meta.taskId)
        let childChat = db.chats.find(x => x.id === childId)
        const childLog = [
            { role: "user", text: meta.prompt || "", error: false, kind: "", done: true, tid: "", filesJson: "", output: "", metaJson: "" }
        ]
        if (meta.resultText || meta.error) {
            childLog.push({
                role: "assistant",
                text: meta.resultText || meta.error || "",
                error: isErr,
                kind: "",
                done: true,
                tid: "",
                filesJson: "",
                output: "",
                metaJson: JSON.stringify({ provider: meta.agent, model: meta.model })
            })
        }
        if (!childChat) {
            childChat = {
                id: childId,
                provider: meta.agent || "claude",
                providersUsed: [meta.agent || "claude"],
                title: "🤖 " + (meta.title || "Субагент"),
                session: meta.sessionId || "",
                sessions: { claude: "", codex: "", agy: "" },
                lastSeenCount: { claude: 0, codex: 0, agy: 0 },
                cwd: meta.cwd || cwd,
                sourceRoot: meta.sourceRoot || "",
                worktreeBranch: meta.worktreeBranch || "",
                parentId: meta.parentChatId || chatId,
                isSubagent: true,
                subagentStatus: meta.status || "running",
                interactionMode: meta.interactionMode || "default",
                permissionMode: meta.write ? "auto-edit" : "supervised",
                agent: !!meta.write,
                imported: false,
                pinned: false,
                settled: false,
                snoozedUntil: 0,
                updated: Math.floor(Date.now() / 1000),
                log: childLog
            }
            db.chats.push(childChat)
        } else {
            childChat.subagentStatus = meta.status || "running"
            childChat.worktreeBranch = meta.worktreeBranch || childChat.worktreeBranch || ""
            childChat.updated = Math.floor(Date.now() / 1000)
            childChat.log = childLog
        }

        // 3. Отслеживание когорты фоновых (async) субагентов для авто-пробуждения родительского чата
        if (meta.mode === "async") {
            const pId = meta.parentChatId || chatId
            const cohort = Object.assign({}, pendingCohortTasks[pId] ?? {})
            cohort[meta.taskId] = meta
            const nextAll = Object.assign({}, pendingCohortTasks)
            nextAll[pId] = cohort
            pendingCohortTasks = nextAll
            checkCohortWakeTimer.restart()
        }
        save()
    }

    Timer {
        id: checkCohortWakeTimer
        interval: 600
        onTriggered: root.checkCohortWake()
    }
    function checkCohortWake() {
        if (busy) return
        const cohort = pendingCohortTasks[chatId]
        if (!cohort) return
        const tasks = Object.values(cohort)
        if (!tasks.length) return
        const allTerminal = tasks.every(t => t.status === "completed" || t.status === "failed" || t.status === "cancelled")
        if (!allTerminal) return

        // Все фоновые субагенты завершились — очищаем когорту и будим родительский тред со сводкой!
        const nextAll = Object.assign({}, pendingCohortTasks)
        delete nextAll[chatId]
        pendingCohortTasks = nextAll

        const summaryLines = tasks.map(t =>
            "### Задача `" + t.taskId + "` — " + (t.title || t.agent) + " (" + t.agent + (t.model ? "/" + t.model : "") + ", статус: " + t.status + ")\n" +
            (t.worktreeBranch ? "Ветка worktree: `" + t.worktreeBranch + "` (`" + t.cwd + "`)\n" : "") +
            (t.resultText || t.error || "(пустой вывод)").slice(0, 2000)
        )
        const wakePrompt = "[Фоновые субагенты завершили работу]\nНиже приведены результаты всех параллельных задач:\n\n" +
                           summaryLines.join("\n\n---\n\n") +
                           "\n\nПроанализируй результаты субагентов и подведи итог или продолжи выполнение задачи."
        sendInternal(wakePrompt, [], [], "cohort-wake")
    }

    // ── Системные инструкции и режимы
    readonly property string planModeAddon:
        "\n\n[РЕЖИМ ПЛАНИРОВАНИЯ (Plan Mode)]\n" +
        "Сейчас включён режим планирования. НЕ изменяй файлы проекта. Изучи кодовую базу, при необходимости задай уточняющие вопросы через инструмент `ask_user_question`, а затем опубликуй подробный пошаговый план реализации через инструмент `propose_plan` (или оберни план в тег `<proposed_plan title=\"Название плана\">...</proposed_plan>`)."

    readonly property string system:
        "Ты — помощник, встроенный в рабочий стол пользователя (Arch/CachyOS, активный композитор Hyprland с конфигом на Lua в ~/.config/hypr/hyprland.lua и ~/.config/hypr/conf/*.lua; старый mango не используется; оболочка Quickshell lite). " +
        "Отвечай по-русски, коротко и по делу, без воды. Команды и код — в блоках кода. " +
        "У тебя есть инструменты qs: demo (интерактивная демонстрация оболочки Quickshell: полный авто-тур по 21 главе action='start', остановка action='stop', список глав action='chapters' или кастомная режиссура action='sequence'|'step'), bar (живое состояние всех 17 виджетов бара, клики/прокрутка по бару, значки системного трея, раскладка островов панели), media, organizer, weather, shell_settings, window_action/windows_list/window_focus/window_close/workspace_go, volume, wallpaper, clipboard_get/clipboard_set, screenshot, system_status, ai_info (модели и лимиты подписок), learn_rule (правила в ~/AGENTS.md по /learn), ask_agent и delegate_task (вызов и делегирование подзадач субагентам claude/codex/agy синхронно mode='wait' или параллельно в фоне mode='async', в том числе в изолированном git worktree isolation='worktree'), task_status/task_cancel, thread_manage, ask_user_question (интерактивные карточки вопросов с вариантами ответа в чате), propose_plan (карточка плана с кнопкой выполнения)."
    readonly property string agentSystem:
        "Ты работаешь внутри оболочки рабочего стола пользователя (Arch/CachyOS, активный композитор Hyprland с конфигом на Lua в ~/.config/hypr/hyprland.lua и ~/.config/hypr/conf/*.lua; старый mango не используется; Quickshell lite) как полноценный агент-разработчик и оркестратор. " +
        "Отвечай по-русски, коротко и по делу. " +
        "У тебя есть полный набор инструментов qs: demo, bar, media, organizer, weather, shell_settings, window_action, окна, громкость, обои, буфер, снимок экрана, ai_info, learn_rule, мультиагентное делегирование delegate_task / ask_agent (mode='wait'|'async', isolation='shared'|'worktree'), task_status, task_cancel, thread_manage, интерактивные карточки вопросов ask_user_question и карточки планов propose_plan."
    readonly property string agentSandbox:
        "Тебе разрешено выполнять команды и править файлы в рабочей папке, запускать интерактивную демонстрацию оболочки (demo), управлять верхней панелью (bar), плеером (media), органайзером (organizer), погодой (weather), настройками оболочки (shell_settings), окнами (window_action), делегировать подзадачи другим агентам через delegate_task / ask_agent (синхронно или параллельно mode='async', с git worktree), задавать интерактивные вопросы через ask_user_question и публиковать планы через propose_plan. Активный композитор — Hyprland (конфиг на Lua: ~/.config/hypr/hyprland.lua и ~/.config/hypr/conf/*.lua; старый mango не используется). Отвечай по-русски, коротко."
    readonly property var safeQs: [
        "demo", "bar", "media", "organizer", "weather", "shell_settings", "window_action",
        "shell_ipc_list", "shell_ipc_call", "windows_list", "window_focus", "window_close", "workspace_go", "notify",
        "clipboard_get", "clipboard_set", "volume", "wallpaper", "system_status", "screenshot",
        "ai_info", "learn_rule", "ask_agent", "delegate_task", "task_status", "task_cancel",
        "thread_manage", "ask_user_question", "propose_plan"
    ]

    // ── Слэш-команды и скиллы
    readonly property var localSlashCommands: [
        { cmd: "/plan", args: "[задача]", desc: "Переключить режим планирования или составить план (Proposed Plan Card)", tag: "qs", kind: "local" },
        { cmd: "/code", args: "", desc: "Переключить режим выполнения кода (default)", tag: "qs", kind: "local" },
        { cmd: "/fork", args: "[название]", desc: "Ответвить текущий чат в новый тред (⑂ Fork)", tag: "qs", kind: "local" },
        { cmd: "/worktree", args: "[имя]", desc: "Создать изолированный git worktree для текущего чата", tag: "qs", kind: "local" },
        { cmd: "/stash", args: "", desc: "Отложить текущий черновик в карман (Ctrl+S)", tag: "qs", kind: "local" },
        { cmd: "/demo", args: "[all|stop|главы]", desc: "Запустить или остановить интерактивную демонстрацию оболочки Quickshell", tag: "qs", kind: "local" },
        { cmd: "/clear", args: "", desc: "Очистить текущий чат и сбросить контекст", tag: "qs", kind: "local" },
        { cmd: "/new", args: "[claude|codex|agy]", desc: "Начать новый чат (можно указать помощника)", tag: "qs", kind: "local" },
        { cmd: "/agent", args: "[on|off|full]", desc: "Переключить режим разрешений (С подтверждением / Авто-правки / Полный доступ)", tag: "qs", kind: "local" },
        { cmd: "/cwd", args: "<путь>", desc: "Сменить рабочую папку помощника", tag: "qs", kind: "local" },
        { cmd: "/limits", args: "", desc: "Обновить лимиты всех подписок", tag: "qs", kind: "local" }
    ]
    readonly property var slashByProvider: ({
        claude: [
            { cmd: "/code-review", args: "[цель]", desc: "Ревью кода и текущих изменений", tag: "Claude", kind: "native" },
            { cmd: "/ultrareview", args: "[цель]", desc: "Глубокое многопроходное ревью архитектуры и багов", tag: "Claude", kind: "native" },
            { cmd: "/security-review", args: "[путь]", desc: "Аудит безопасности и поиск уязвимостей в коде", tag: "Claude", kind: "native" },
            { cmd: "/simplify", args: "[файл/код]", desc: "Упростить и отрефакторить переусложнённый код", tag: "Claude", kind: "native" },
            { cmd: "/debug", args: "<проблема>", desc: "Диагностика и отладка бага или падения", tag: "Claude", kind: "native" },
            { cmd: "/verify", args: "[задача]", desc: "Проверить решение тестами, линтером и сборкой", tag: "Claude", kind: "native" },
            { cmd: "/design", args: "<описание>", desc: "Проектирование UI и архитектуры компонента", tag: "Claude", kind: "native" },
            { cmd: "/design-sync", args: "", desc: "Синхронизировать дизайн-систему с кодом", tag: "Claude", kind: "native" },
            { cmd: "/ui-ux-design-standards", args: "[экран]", desc: "Стандарты Apple HIG и Material Design 3 (скилл)", tag: "Skill", kind: "native" },
            { cmd: "/dataviz", args: "<данные>", desc: "Визуализация данных и построение графиков", tag: "Claude", kind: "native" },
            { cmd: "/batch", args: "<задача>", desc: "Пакетная обработка однотипных изменений по проекту", tag: "Claude", kind: "native" },
            { cmd: "/loop", args: "<команда>", desc: "Циклический запуск с проверкой условия", tag: "Claude", kind: "native" },
            { cmd: "/advisor", args: "<вопрос>", desc: "Архитектурный советник Claude Code", tag: "Claude", kind: "native" },
            { cmd: "/recap", args: "", desc: "Краткая сводка сделанного в текущей сессии", tag: "Claude", kind: "native" },
            { cmd: "/insights", args: "", desc: "Анализ паттернов работы и инсайты по сессиям", tag: "Claude", kind: "native" },
            { cmd: "/doctor", args: "", desc: "Проверка состояния и настроек Claude Code", tag: "Claude", kind: "native" },
            { cmd: "/init", args: "", desc: "Изучить проект и создать/обновить CLAUDE.md", tag: "Claude", kind: "workflow" },
            { cmd: "/compact", args: "[фокус]", desc: "Сжать контекст разговора и начать свежую сессию", tag: "Claude", kind: "workflow" },
            { cmd: "/learn", args: "[правило]", desc: "Сохранить правило из диалога в ~/CLAUDE.md (AGENTS.md)", tag: "Claude", kind: "workflow" }
        ],
        codex: [
            { cmd: "/review-agent", args: "[цель]", desc: "Defect-first код-ревью изменений без правки файлов", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/.system/review-agent/SKILL.md" },
            { cmd: "/deep-research", args: "<тема>", desc: "Глубокое исследование вопроса по нескольким источникам", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/deep-research/SKILL.md" },
            { cmd: "/define-goal", args: "<задача>", desc: "Сформулировать конкретную измеримую цель перед работой", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/define-goal/SKILL.md" },
            { cmd: "/security-best-practices", args: "[путь]", desc: "Ревью безопасности под язык и фреймворк проекта", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/security-best-practices/SKILL.md" },
            { cmd: "/security-threat-model", args: "[путь]", desc: "Моделирование угроз, границ доверия и поверхности атаки", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/security-threat-model/SKILL.md" },
            { cmd: "/imagegen", args: "<описание>", desc: "Генерация и редактирование растровых изображений", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/.system/imagegen/SKILL.md" },
            { cmd: "/openai-docs", args: "<вопрос>", desc: "Документация OpenAI, моделей Codex, настроек и SDK", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/.system/openai-docs/SKILL.md" },
            { cmd: "/playwright", args: "<сценарий>", desc: "Автоматизация браузера из терминала через Playwright", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/playwright/SKILL.md" },
            { cmd: "/computer-use", args: "<задача>", desc: "Наблюдение и управление десктопными приложениями", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/computer-use/SKILL.md" },
            { cmd: "/built-in-browser", args: "<url>", desc: "Просмотр и автоматизация сайтов в изолированном браузере", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/built-in-browser/SKILL.md" },
            { cmd: "/chrome-browser", args: "<задача>", desc: "Инспекция и автоматизация открытой сессии Chrome/Chromium", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/chrome-browser/SKILL.md" },
            { cmd: "/pdf", args: "<файл/задача>", desc: "Чтение, создание и проверка PDF-документов", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/pdf/SKILL.md" },
            { cmd: "/docx", args: "<файл/задача>", desc: "Создание, чтение и правка документов Word (.docx)", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/docx/SKILL.md" },
            { cmd: "/xlsx", args: "<файл/задача>", desc: "Работа с таблицами Excel (.xlsx) и CSV/TSV", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/xlsx/SKILL.md" },
            { cmd: "/pptx", args: "<файл/задача>", desc: "Создание и редактирование презентаций PowerPoint (.pptx)", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/pptx/SKILL.md" },
            { cmd: "/docs", args: "<тема>", desc: "Написание отчёта, спецификации или гайда", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/docs/SKILL.md" },
            { cmd: "/morning", args: "", desc: "Утренний брифинг по задачам, почте и календарю", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/morning/SKILL.md" },
            { cmd: "/meeting-notes-and-actions", args: "<заметки>", desc: "Выжимка решений, рисков и задач из заметок встречи", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/meeting-notes-and-actions/SKILL.md" },
            { cmd: "/skill-creator", args: "<имя>", desc: "Создать или обновить скилл Codex в ~/.codex/skills", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/.system/skill-creator/SKILL.md" },
            { cmd: "/skill-installer", args: "<репо/имя>", desc: "Установить скилл Codex из каталога или GitHub", tag: "Codex", kind: "codex-skill", skillPath: root.home + "/.codex/skills/.system/skill-installer/SKILL.md" },
            { cmd: "/compact", args: "[фокус]", desc: "Сжать историю чата в краткую сводку и сбросить сессию", tag: "Codex", kind: "workflow" },
            { cmd: "/learn", args: "[правило]", desc: "Сохранить правило из диалога в ~/AGENTS.md", tag: "Codex", kind: "workflow" }
        ],
        agy: [
            { cmd: "/learn", args: "[правило]", desc: "Запомнить замечание или правило из диалога в ~/GEMINI.md (AGENTS.md)", tag: "AGY", kind: "workflow" },
            { cmd: "/plan", args: "<задача>", desc: "Пошаговое планирование сложной задачи перед реализацией", tag: "AGY", kind: "workflow" },
            { cmd: "/grill-me", args: "[тема]", desc: "Интерактивное интервью для выравнивания плана и дизайна", tag: "AGY", kind: "workflow" },
            { cmd: "/boost", args: "<задача>", desc: "Глубокое мышление, несколько перспектив, план и строгая проверка", tag: "AGY", kind: "workflow" },
            { cmd: "/goal", args: "<цель>", desc: "Основательная автономная работа до полного достижения цели", tag: "AGY", kind: "workflow" },
            { cmd: "/teamwork-preview", args: "<проект>", desc: "Командная работа автономных субагентов над большим проектом", tag: "AGY", kind: "workflow" },
            { cmd: "/browser", args: "<задача>", desc: "Веб-поиск и работа с веб-приложениями", tag: "AGY", kind: "workflow" },
            { cmd: "/schedule", args: "<расписание>", desc: "Запуск задачи по расписанию (cron) или таймеру", tag: "AGY", kind: "workflow" },
            { cmd: "/compact", args: "[фокус]", desc: "Сжать контекст разговора для освобождения окна", tag: "AGY", kind: "workflow" },
            { cmd: "/graphify", args: "<вопрос>", desc: "Построить или опросить граф знаний по архитектуре проекта", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/config/skills/graphify/SKILL.md" },
            { cmd: "/generative_ui", args: "<описание>", desc: "Сгенерировать интерактивный виджет или интерфейс", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/generative_ui/SKILL.md" },
            { cmd: "/automation", args: "<задача>", desc: "Спроектировать и настроить фоновую автоматизацию", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/automation/SKILL.md" },
            { cmd: "/agy-customizations", args: "[вопрос]", desc: "Справка и создание правил, скиллов, плагинов, хуков и MCP", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/agy-customizations/SKILL.md" },
            { cmd: "/antigravity-guide", args: "[вопрос]", desc: "Полное руководство по Antigravity CLI, IDE, 2.0 и SDK", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/antigravity_guide/SKILL.md" },
            { cmd: "/plugin", args: "[действие]", desc: "Управление и создание плагинов Antigravity", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/plugin/SKILL.md" },
            { cmd: "/migrate-workflows", args: "", desc: "Миграция старых воркфлоу в современные скиллы", tag: "Skill", kind: "agy-skill", skillPath: root.home + "/.gemini/antigravity-cli/builtin/skills/migrate-workflows/SKILL.md" }
        ]
    })
    readonly property var slashCommands: (slashByProvider[provider] ?? []).concat(localSlashCommands)
    readonly property var skillItems: {
        const list = []
        for (const p of ["claude", "codex", "agy"]) {
            for (const s of (slashByProvider[p] ?? [])) {
                if (s.kind === "codex-skill" || s.kind === "agy-skill" || s.tag === "Skill" || s.kind === "native") {
                    list.push({ name: s.cmd.slice(1), desc: s.desc, provider: p, path: s.skillPath || "" })
                }
            }
        }
        return list
    }

    function fmtReset(ts) {
        if (!ts) return ""
        const d = ts - Math.floor(Date.now() / 1000)
        if (d <= 0) return "сброс сейчас"
        if (d < 3600) return "сброс через " + Math.ceil(d / 60) + " мин"
        if (d < 86400) return "сброс через " + Math.floor(d / 3600) + " ч " + Math.floor(d % 3600 / 60) + " мин"
        return "сброс через " + Math.floor(d / 86400) + " дн " + Math.floor(d % 86400 / 3600) + " ч"
    }

    function runtimeContext() {
        const mpart = ["claude", "codex", "agy"].map(p => {
            const ms = modelsOf(p).map(m => {
                const effs = p === "claude" ? (catalog.claude?.efforts ?? []) : (m.efforts ?? [])
                return m.id + (effs.length ? " (" + effs.join("/") + ")" : "")
            }).join(", ")
            return (p === "agy" ? "Antigravity (agy)" : p === "claude" ? "Claude (claude)" : "Codex (codex)") + ": " + (ms || "загружаются")
        }).join("; ")
        const lpart = []
        for (const p of ["claude", "codex"]) {
            const rs = limitRows(p)
            if (rs.length) lpart.push((p === "claude" ? "Claude" : "Codex") + ": " + rs.map(r => r.label + " осталось " + Math.round((1 - r.used) * 100) + "%" + (r.reset ? " (" + fmtReset(r.reset) + ")" : "")).join(", "))
        }
        const ag = limits.agy ?? {}
        for (const [k, name] of [["gemini", "Antigravity Gemini"], ["other", "Antigravity Claude/GPT"]]) {
            const g = ag[k] ?? {}
            const s = []
            if (g.five) s.push("5 ч осталось " + Math.round(g.five.left * 100) + "%" + (g.five.reset ? " (" + fmtReset(g.five.reset) + ")" : ""))
            if (g.week) s.push("неделя осталось " + Math.round(g.week.left * 100) + "%" + (g.week.reset ? " (" + fmtReset(g.week.reset) + ")" : ""))
            if (s.length) lpart.push(name + ": " + s.join(", "))
        }
        return "[Контекст оболочки Quickshell: активный композитор — Hyprland, конфиг написан на Lua в `~/.config/hypr/hyprland.lua` и `~/.config/hypr/conf/*.lua` (`hyprland.conf` нет, а `mango` в `~/.config/mango` и `~/src/mango` — старый неиспользуемый композитор). " +
               "Текущий чат: id=`" + chatId + "`, папка=`" + cwd + "`" + (gitInfo.isGit ? " (git ветка `" + gitInfo.branch + "`" + (gitInfo.isWorktree ? ", изолированный worktree" : "") + ")" : "") + ", режим=`" + interactionMode + "`. " +
               "Для делегирования подзадач субагентам используй MCP `qs` → `delegate_task` или `ask_agent` (параметры: `agent='codex'|'claude'|'agy'`, `model`, `effort`, `title`, `prompt`, `mode='wait'|'async'`, `isolation='shared'|'worktree'`, `parent_chat_id='" + chatId + "'`). " +
               "Для интерактивных вопросов пользователю с вариантами ответа используй `ask_user_question`, а для публикации плана реализации — `propose_plan`. " +
               "Модели 3 агентов — " + mpart + ". " +
               "Лимиты/квоты подписок: " + (lpart.length ? lpart.join("; ") : "вызови ai_info") + ".]"
    }

    property string lastPrompt: ""
    property var lastFiles: []
    function pushHistory(t) {
        t = (t ?? "").trim()
        if (!t) return
        const h = promptHistory.filter(x => x !== t)
        h.push(t)
        if (h.length > 50) h.shift()
        promptHistory = h
    }
    function historyText() {
        const lines = []
        const end = Math.max(0, log.count - 2)
        for (let i = Math.max(0, end - 14); i < end; i++) {
            const m = log.get(i)
            if (m.error || (m.role !== "user" && m.role !== "assistant") || !m.text) continue
            lines.push((m.role === "user" ? "Пользователь: " : "Помощник: ") + m.text.slice(0, 800))
        }
        return lines.length ? "Предыдущие реплики в этом чате:\n" + lines.join("\n\n") + "\n\n" : ""
    }
    function recentHistoryAll() {
        const lines = []
        for (let i = Math.max(0, log.count - 14); i < log.count; i++) {
            const m = log.get(i)
            if (m.error || (m.role !== "user" && m.role !== "assistant") || !m.text) continue
            lines.push((m.role === "user" ? "Пользователь: " : "Помощник: ") + m.text.slice(0, 900))
        }
        return lines.length ? "Контекст последних сообщений в чате:\n" + lines.join("\n\n") + "\n\n" : ""
    }

    function expandSlash(text, prevHist) {
        if (!text.startsWith("/")) return { prompt: text, resetSession: false, isSlash: false }
        const m = text.match(/^\/([a-zA-Z0-9_:-]+)(?:\s+([\s\S]*))?$/)
        if (!m) return { prompt: text, resetSession: false, isSlash: false }
        const cmd = m[1].toLowerCase()
        const rest = (m[2] ?? "").trim()
        const entry = slashCommands.find(x => x.cmd.toLowerCase() === "/" + cmd)

        if (provider === "claude" && entry && entry.kind === "native") {
            return { prompt: text, resetSession: false, isSlash: true }
        }
        if (entry && entry.kind === "codex-skill") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "Активируй скилл Codex `$" + cmd + "` (прочитай инструкцию в `" + entry.skillPath + "`) и выполни запрос пользователя: " + (rest || entry.desc)
            }
        }
        if (entry && entry.kind === "agy-skill") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "Прочитай и активируй скилл `" + cmd + "` (`" + entry.skillPath + "`) и выполни запрос: " + (rest || entry.desc)
            }
        }
        if (cmd === "learn") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: prevHist +
                    "[Команда /learn]\nПользователь вызвал `/learn" + (rest ? " " + rest : "") + "`.\n" +
                    "1. Проанализируй последние сообщения пользователя (выше) и его уточнение" + (rest ? " («" + rest + "»)" : "") + ", выдели правило, исправление или ограничение, которое нужно запомнить для будущих сессий.\n" +
                    "2. Прочитай текущие правила через инструмент `learn_rule` (`action=\"read\"`).\n" +
                    "3. Сформулируй чёткое, лаконичное правило в формате Markdown и вызови `learn_rule` с `action=\"append\"`, после чего кратко сообщи, что правило сохранено в `~/AGENTS.md`."
            }
        }
        if (cmd === "compact") {
            return {
                resetSession: true,
                isSlash: true,
                prompt: prevHist +
                    "[Команда /compact]\nСожми всю историю диалога выше в компактную, структурированную сводку (ключевые решения, изменённые файлы, открытые вопросы и контекст)" +
                    (rest ? " с акцентом на: " + rest : "") + ". Мы продолжаем разговор с этой чистой точки."
            }
        }
        if (cmd === "plan") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /plan]\nЗадача: " + (rest || "составь план по текущей задаче из диалога") + "\n" +
                    "Не вноси изменения сразу. Тщательно изучи контекст, при необходимости задай вопросы через `ask_user_question` и опубликуй пошаговый план через инструмент `propose_plan` (или в теге `<proposed_plan title=\"...\">...</proposed_plan>`)."
            }
        }
        if (cmd === "review") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /review]\nПроведи строгое код-ревью" + (rest ? " (" + rest + ")" : " последних изменений и текущей рабочей папки") +
                    ": проверь баги, гонки, утечки, производительность и соответствие стилю проекта. Выведи замечания по приоритету с конкретными строками и решениями."
            }
        }
        if (cmd === "grill-me" || cmd === "grill") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /grill-me]\nТема: " + (rest || "текущая задача в чате") + "\n" +
                    "Проведи со мной короткое техническое интервью через инструмент `ask_user_question`: задай самые важные уточняющие вопросы по неоднозначным местам архитектуры, UX и крайним случаям, чтобы мы выровняли план перед реализацией."
            }
        }
        if (cmd === "boost") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /boost]\nЗадача повышенной сложности: " + (rest || "см. контекст чата") + "\n" +
                    "Используй максимум глубины: рассмотри задачу с нескольких сторон, проверь альтернативы, при необходимости привлеки сабагентов (`delegate_task` / `ask_agent`), выработай оптимальное решение и тщательно верифицируй результат."
            }
        }
        if (cmd === "goal") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /goal]\nЦель: " + (rest || "см. контекст чата") + "\n" +
                    "Работай максимально основательно до полного достижения цели: проверяй каждый шаг и доводи задачу до рабочего состояния без полумер."
            }
        }
        if (cmd === "teamwork-preview") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /teamwork-preview]\nПроект: " + (rest || "см. контекст чата") + "\n" +
                    "Разбей задачу на независимые направления и используй сабагентов (`delegate_task` с `mode='async'` или `mode='wait'` для claude, codex, agy), чтобы параллельно проработать решение и собрать единый результат."
            }
        }
        if (cmd === "browser") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /browser]\nЗадача: " + (rest || "см. контекст чата") + "\n" +
                    "Используй веб-поиск и чтение страниц для выполнения задачи."
            }
        }
        if (cmd === "schedule") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /schedule]\nЗапрос по расписанию/таймеру: " + (rest || "см. контекст чата")
            }
        }
        if (cmd === "init") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /init]\nИзучи структуру рабочей папки `" + cwd + "`, прочитай текущие правила (`learn_rule` action='read') и предложи или сохрани обновлённые правила архитектуры и стиля проекта."
            }
        }
        if (cmd === "demo") {
            return {
                resetSession: false,
                isSlash: true,
                prompt: "[Команда /demo]\nПроведи интерактивную демонстрацию оболочки Quickshell (инструмент MCP `demo`, `action='start'`, либо `action='sequence'` если просят конкретный сценарий). Запрос пользователя: " + (rest || "полная демонстрация всех возможностей оболочки (chapters='all') на основном мониторе DP-3")
            }
        }
        return { prompt: text, resetSession: false, isSlash: true }
    }

    function launchCommand(text, first, files, handoffBlock) {
        files = files ?? []
        handoffBlock = handoffBlock || ""
        const isPlan = interactionMode === "plan"
        const effectiveAgent = !isPlan && (agent || permissionMode !== "supervised")
        const ctx = runtimeContext() + (isPlan ? planModeAddon : "")
        const hist = (first && !handoffBlock) ? historyText() : ""
        const textFiles = files.filter(f => !f.isImage && f.excerpt).map(f => "Прикреплённый файл `" + f.name + "` (`" + f.path + "`):\n```\n" + f.excerpt + "\n```").join("\n\n")
        const fileNote = provider === "agy" && files.length > 0
            ? "[Прикреплённые изображения/файлы — ОБЯЗАТЕЛЬНО открой и посмотри их инструментом view_file перед ответом: " + files.map(f => f.path).join(", ") + "]\n\n"
            : provider === "codex" && files.length > 0
            ? "[Прикреплённые файлы: " + files.map(f => f.name + " (" + f.path + ")").join(", ") + "]\n\n"
            : ""
        const userBody = handoffBlock + (textFiles ? textFiles + "\n\n" : "") + fileNote + text
        const prompt = provider !== "claude"
            ? (first ? (effectiveAgent ? agentSandbox : system) + "\n" + ctx + "\n\n" + hist + "Вопрос пользователя:\n" + userBody
                     : ctx + "\n\nВопрос пользователя:\n" + userBody)
            : (handoffBlock ? handoffBlock + text : text)

        if (provider === "agy") {
            const e = effort !== "" ? effort : "medium"
            const fam = currentModel
            const eff = fam ? (fam.efforts.indexOf(e) >= 0 ? e : fam.efforts[0]) : e
            const id = /-(low|medium|high|xhigh|max)$/.test(model) ? model : (model + "-" + eff)
            let cmd = ["agy", "-p", prompt, "--output-format", "stream-json", "--dangerously-skip-permissions", "--mode", effectiveAgent ? "accept-edits" : "plan", "--model", id]
            if (files.length > 0) cmd = cmd.concat(["--add-dir", dir + "/attachments"])
            if (effectiveAgent && permissionMode !== "full-access") cmd.push("--sandbox")
            if (!first && sessionId) cmd = cmd.concat(["--conversation", sessionId])
            return ["sh", "-c", 'mkdir -p "$1" "$2" && cd "$1" && shift 2 && exec "$@" </dev/null', "ai", cwd, dir + "/attachments"].concat(cmd)
        }
        if (provider === "codex") {
            const mcp = ["-c", 'mcp_servers.qs.command="' + mcpCmd + '"']
            for (const t of safeQs) mcp.push("-c", "mcp_servers.qs.tools." + t + '.approval_mode="approve"')
            const imgs = []
            for (const f of files) if (f.isImage && f.path) imgs.push("-i", f.path)
            const opts = (model !== "" ? ["-m", model] : []).concat(effort !== "" ? ["-c", 'model_reasoning_effort="' + effort + '"'] : []).concat(mcp).concat(imgs)
            const sandbox = effectiveAgent ? (permissionMode === "full-access" ? "danger-full-access" : "workspace-write") : "read-only"
            const cmd = (first || !sessionId)
                ? ["codex", "exec", prompt, "--json", "-s", sandbox, "--skip-git-repo-check"].concat(opts)
                : ["codex", "exec", "resume", sessionId, prompt, "--json", "--skip-git-repo-check", "-c", 'sandbox_mode="' + sandbox + '"'].concat(opts)
            return ["sh", "-c", 'mkdir -p "$1" && cd "$1" && shift && exec "$@" </dev/null', "ai", cwd].concat(cmd)
        }
        // Claude
        const isNativeSlash = text.startsWith("/")
        const extraTools = effectiveAgent
            ? (permissionMode === "full-access" ? ["Bash", "Read", "Edit", "Write", "Grep", "Glob", "Skill"] : ["Skill", "Read", "Grep", "Glob"])
            : (files.length > 0 || isNativeSlash || isPlan) ? ["Skill", "Read", "Grep", "Glob"] : ["Skill", "Read", "Grep", "Glob"]
        const allowed = safeQs.map(t => "mcp__qs__" + t).concat(extraTools)
        const sysText = (effectiveAgent ? agentSystem : system) + "\n" + ctx
        let cmd = files.length > 0
            ? ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
               "--model", model, "--mcp-config", mcpFile, "--strict-mcp-config",
               "--permission-prompt-tool", "mcp__qs__approve", "--allowedTools", allowed.join(",")]
            : ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages",
               "--model", model, "--mcp-config", mcpFile, "--strict-mcp-config",
               "--permission-prompt-tool", "mcp__qs__approve", "--allowedTools", allowed.join(",")]
        if (effort !== "") cmd = cmd.concat(["--effort", effort])
        if (effectiveAgent || imported || !first) cmd = cmd.concat(["--append-system-prompt", sysText])
        else cmd = cmd.concat(["--system-prompt", sysText])
        if (!effectiveAgent) cmd = cmd.concat(["--tools", extraTools.join(",")])
        if (!first && sessionId) cmd = cmd.concat(["--resume", sessionId])
        if (files.length > 0)
            return [clipCmd, "run-claude", cwd, prompt].concat(files.map(f => f.path)).concat(["--"]).concat(cmd)
        return ["sh", "-c", 'mkdir -p "$1" && cd "$1" && shift && exec "$@" </dev/null', "ai", cwd].concat(cmd)
    }

    function send(text) {
        text = String(text ?? "").trim()
        const files = collectCurrentAttachments()
        const chips = collectCurrentChips()
        if (text === "" && files.length === 0 && chips.length === 0) return

        // Если агент занят — по умолчанию ставим сообщение в очередь (как в T3 Code)!
        if (busy) {
            enqueueMessage(text, files, chips)
            return
        }
        sendInternal(text, files, chips, "")
    }

    function sendInternal(text, files, chips, dispatchKind) {
        text = String(text ?? "").trim()
        files = files ?? []
        chips = chips ?? []
        if ((text === "" && files.length === 0 && chips.length === 0) || busy) return

        // Мгновенные локальные слэш-команды
        if (text.startsWith("/") && files.length === 0 && chips.length === 0) {
            const m = text.match(/^\/([a-zA-Z0-9_-]+)(?:\s+(.*))?$/)
            if (m) {
                const c = m[1].toLowerCase()
                const arg = (m[2] ?? "").trim()
                if (c === "clear") { clear(); return }
                if (c === "new") {
                    const p = ["claude", "codex", "agy"].indexOf(arg.toLowerCase()) >= 0 ? arg.toLowerCase() : provider
                    newChat(p)
                    return
                }
                if (c === "claude" || c === "codex" || c === "agy") { setProvider(c, false); return }
                if (c === "code") { setInteractionMode("default"); return }
                if (c === "plan" && arg === "") { toggleInteractionMode(); return }
                if (c === "fork") { forkChat(chatId, -1, arg); return }
                if (c === "worktree") { createWorktreeForChat(arg); return }
                if (c === "agent") {
                    if (arg === "full") setPermissionMode("full-access")
                    else if (arg === "on" || arg === "1" || arg === "true") setPermissionMode("auto-edit")
                    else if (arg === "off" || arg === "0" || arg === "false") setPermissionMode("supervised")
                    else cyclePermissionMode()
                    return
                }
                if (c === "cwd" && arg !== "") { setCwd(arg); return }
                if (c === "limits") { refreshLimits(true); return }
                if (c === "demo" && arg.toLowerCase() === "stop") {
                    Quickshell.execDetached([root.home + "/.local/bin/qs-demo", "stop"])
                    return
                }
            }
        }

        if (chatId === "") newChat(provider)
        if (text !== "" && dispatchKind !== "cohort-wake") pushHistory(text)
        clearAttachments()
        clearContextChips()
        queueHeld = false

        const prevHist = recentHistoryAll()
        const slash = expandSlash(text, prevHist)
        if (slash.resetSession) {
            sessionId = ""
            const s = Object.assign({}, chatSessions); s[provider] = ""; chatSessions = s
        }
        if (providersUsed.indexOf(provider) < 0) providersUsed = providersUsed.concat([provider])

        const chipBlock = serializeChips(chips)
        const baseText = slash.prompt !== "" ? slash.prompt : (files.some(f => f.isImage) ? "Посмотри на прикреплённое изображение и подробно опиши или реши то, что на нём показано." : "Посмотри на прикреплённый файл.")
        const effectiveText = chipBlock + baseText

        const savedFiles = files.map(f => ({ path: f.path, name: f.name, isImage: f.isImage, width: f.width, height: f.height, sizeLabel: f.sizeLabel }))
        const userMeta = {
            chips: chips,
            dispatchKind: dispatchKind || "",
            provider: provider,
            interactionMode: interactionMode
        }
        appendLog({
            role: "user",
            text: text || (chips.length ? chips.map(c => "@" + c.label).join(" ") : "Вложение"),
            error: false,
            kind: dispatchKind || "",
            done: true,
            tid: "",
            filesJson: savedFiles.length ? JSON.stringify(savedFiles) : "",
            output: "",
            metaJson: JSON.stringify(userMeta)
        })
        appendLog({
            role: "assistant",
            text: "",
            error: false,
            kind: "",
            done: true,
            tid: "",
            filesJson: "",
            output: "",
            metaJson: JSON.stringify({ provider: provider, model: model, effort: effort })
        })

        // Формируем Context Handoff, если провайдер подключился к треду или вернулся после другого провайдера
        const handoffBlock = buildContextHandoff(provider)
        const first = sessionId === ""

        lastPrompt = effectiveText
        lastFiles = files
        postTurnLimitsTimer.stop()
        if (limitsProc.running) limitsProc.running = false

        busy = true
        wasSteered = false
        turnOutput = false
        turnText = false
        turnStartedAt = Math.floor(Date.now() / 1000)
        turnElapsedSec = 0
        turnStepCount = 0
        currentTurnId = uid()
        preTurnRef = ""

        // Если рабочая папка — git-репозиторий, захватываем теневой pre-turn чекпоинт
        if (gitInfo.isGit && !preTurnProc.running) {
            preTurnProc.command = [clipCmd, "checkpoint-capture", cwd, chatId || "default", "pre_" + currentTurnId]
            preTurnProc.running = true
        }

        proc.workingDirectory = home
        proc.command = launchCommand(effectiveText, first, files, handoffBlock)
        proc.running = true
        save()
    }

    Process {
        id: preTurnProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.ok && d.ref) root.preTurnRef = d.ref
                } catch (e) {}
            }
        }
    }

    Process {
        id: postTurnProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.ok && d.changedFiles && d.changedFiles.length > 0) {
                        root.turnChangedFiles = d.changedFiles
                        root.appendLog({
                            role: "checkpoint",
                            text: "Изменено файлов: " + d.changedFiles.length + " (+" + (d.totalAdditions || 0) + " −" + (d.totalDeletions || 0) + ")",
                            error: false,
                            kind: "checkpoint",
                            done: true,
                            tid: d.ref || "",
                            filesJson: JSON.stringify(d.changedFiles),
                            output: "",
                            metaJson: JSON.stringify({
                                ref: d.ref || "",
                                prevRef: d.prevRef || root.preTurnRef || "",
                                totalAdditions: d.totalAdditions || 0,
                                totalDeletions: d.totalDeletions || 0,
                                count: d.changedFiles.length
                            })
                        })
                        root.save()
                    }
                } catch (e) {}
                root.refreshGitInfo()
            }
        }
    }

    function stop() {
        if (busy) {
            if (queuedMessages.count > 0) queueHeld = true
            denyAll()
            cancelQuestion()
            proc.running = false
        }
    }

    function lastIndex() { return log.count - 1 }
    property bool turnOutput: false
    property bool turnText: false

    function appendThinking(delta) {
        if (!delta) return
        let idx = -1
        for (let i = log.count - 1; i >= 0; i--) {
            const m = log.get(i)
            if (m.role === "user") break
            if (m.role === "thinking" && !m.done) { idx = i; break }
        }
        if (idx < 0) {
            if (lastEmpty()) log.remove(lastIndex())
            appendLog({
                role: "thinking",
                text: String(delta),
                error: false,
                kind: provider,
                done: false,
                tid: "think_" + currentTurnId,
                filesJson: "",
                output: "",
                metaJson: JSON.stringify({ startedAt: Math.floor(Date.now() / 1000), elapsedSec: 1 })
            })
        } else {
            log.setProperty(idx, "text", log.get(idx).text + String(delta))
        }
        turnOutput = true
    }

    function finishThinking() {
        for (let i = log.count - 1; i >= 0; i--) {
            const m = log.get(i)
            if (m.role === "user") break
            if (m.role === "thinking" && !m.done) {
                log.setProperty(i, "done", true)
                let elapsed = Math.max(1, turnElapsedSec)
                if (m.metaJson) {
                    try {
                        const md = JSON.parse(m.metaJson)
                        if (md.startedAt) elapsed = Math.max(1, Math.floor(Date.now() / 1000) - md.startedAt)
                    } catch (e) {}
                }
                log.setProperty(i, "metaJson", JSON.stringify({ elapsedSec: elapsed }))
            }
        }
    }

    function appendText(t) {
        if (!t) return
        finishThinking()
        let i = lastIndex()
        if (i < 0 || log.get(i).role !== "assistant") {
            appendLog({
                role: "assistant",
                text: "",
                error: false,
                kind: "",
                done: true,
                tid: "",
                filesJson: "",
                output: "",
                metaJson: JSON.stringify({ provider: provider, model: model, effort: effort })
            })
            i = lastIndex()
        }
        log.setProperty(i, "text", log.get(i).text + t)
        turnOutput = true
        turnText = true
    }

    function fail(msg) {
        finishThinking()
        const i = lastIndex()
        if (i >= 0 && log.get(i).role === "assistant" && log.get(i).text === "") {
            log.setProperty(i, "text", msg)
            log.setProperty(i, "error", true)
        } else {
            appendLog({ role: "assistant", text: msg, error: true, done: true })
        }
        turnOutput = true
        turnText = true
    }

    function lastEmpty() { const i = lastIndex(); return i >= 0 && log.get(i).role === "assistant" && log.get(i).text === "" }

    function addTool(block) {
        finishThinking()
        if (block.id) {
            for (let i = log.count - 1; i >= 0; i--) if (log.get(i).role === "tool" && log.get(i).tid === block.id) return
        }
        const sm = summarize(block.name, block.input)
        if (lastEmpty()) log.remove(lastIndex())
        turnStepCount++
        appendLog({
            role: "tool",
            text: sm.title + (sm.detail ? "\n" + sm.detail : ""),
            error: false,
            kind: block.name || "tool",
            done: false,
            tid: block.id ?? "",
            filesJson: "",
            output: "",
            metaJson: JSON.stringify({ input: block.input ?? {} })
        })
        turnOutput = true
    }

    function extractToolResultText(content) {
        if (!content) return ""
        if (typeof content === "string") return content
        if (Array.isArray(content)) {
            return content.map(c => (typeof c === "string" ? c : (c?.text || ""))).filter(Boolean).join("\n")
        }
        if (typeof content === "object" && content.text) return String(content.text)
        return JSON.stringify(content)
    }

    function finishTool(tid, isError, fallbackBlock, outputText) {
        const cleanOut = String(outputText ?? "").slice(0, 4000)
        for (let i = log.count - 1; i >= 0; i--) {
            const m = log.get(i)
            if (m.role === "tool" && m.tid === tid) {
                log.setProperty(i, "done", true)
                log.setProperty(i, "error", !!isError)
                if (cleanOut) log.setProperty(i, "output", cleanOut)
                return
            }
        }
        if (fallbackBlock) {
            addTool(fallbackBlock)
            const i = lastIndex()
            if (i >= 0 && log.get(i).role === "tool") {
                log.setProperty(i, "done", true)
                log.setProperty(i, "error", !!isError)
                if (cleanOut) log.setProperty(i, "output", cleanOut)
            }
        }
    }

    function updateTokenUsage(inp, outp, maxWin) {
        const curIn = Number(inp || tokenUsage.input || 0)
        const curOut = Number(outp || tokenUsage.output || 0)
        const tot = curIn + curOut
        const mw = Number(maxWin || tokenUsage.maxWindow || 200000)
        const pct = mw > 0 ? Math.min(100, Math.round((tot / mw) * 100)) : 0
        tokenUsage = { input: curIn, output: curOut, total: tot, maxWindow: mw, percent: pct }
    }

    function extractProposedPlanFromAssistant() {
        for (let i = log.count - 1; i >= 0; i--) {
            const m = log.get(i)
            if (m.role === "user") break
            if (m.role === "assistant" && m.text) {
                const match = m.text.match(/<proposed_plan(?:\s+title="([^"]*)")?>([\s\S]*?)<\/proposed_plan>/)
                if (match) {
                    const pTitle = (match[1] || "План реализации").trim()
                    const pBody = (match[2] || "").trim()
                    const cleaned = m.text.replace(/<proposed_plan(?:\s+title="[^"]*")?>[\s\S]*?<\/proposed_plan>/, "").trim()
                    log.setProperty(i, "text", cleaned || ("Составлен план «" + pTitle + "»."))
                    receivePlan({ title: pTitle, plan: pBody })
                    break
                }
            }
        }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                if (root.provider === "claude") {
                    if (d.type === "stream_event") {
                        const ev = d.event
                        if (ev?.type === "content_block_delta") {
                            if (ev.delta?.type === "text_delta") root.appendText(ev.delta.text)
                            else if (ev.delta?.type === "thinking_delta" && ev.delta?.thinking) root.appendThinking(ev.delta.thinking)
                        } else if (ev?.type === "message_start" && ev.message?.usage) {
                            const u = ev.message.usage
                            root.updateTokenUsage((u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0), u.output_tokens || 0, 200000)
                        } else if (ev?.type === "message_delta" && ev.usage) {
                            root.updateTokenUsage(root.tokenUsage.input, ev.usage.output_tokens || root.tokenUsage.output, 200000)
                        }
                    } else if (d.type === "assistant") {
                        for (const b of d.message?.content ?? []) {
                            if (b.type === "tool_use") root.addTool(b)
                            else if (b.type === "thinking" && b.thinking) root.appendThinking(b.thinking)
                        }
                    } else if (d.type === "user") {
                        for (const b of d.message?.content ?? []) {
                            if (b.type === "tool_result")
                                root.finishTool(b.tool_use_id, b.is_error, null, root.extractToolResultText(b.content))
                        }
                    } else if (d.type === "rate_limit_event") {
                        root.parseClaudeLimits(line)
                    } else if (d.type === "result") {
                        if (d.session_id) root.sessionId = d.session_id
                        if (d.usage) {
                            const u = d.usage
                            root.updateTokenUsage((u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0), u.output_tokens || 0, 200000)
                        }
                        if (d.is_error) root.fail(d.result || "Ошибка запроса")
                        else if (!root.turnText && d.result) root.appendText(d.result)
                    }
                } else if (root.provider === "agy") {
                    if (d.event === "init" && d.conversation_id) root.sessionId = d.conversation_id
                    else if (d.event === "step_update") {
                        const u = d.step_update
                        if (u?.step_type === "agent_response" && u.text_delta) root.appendText(u.text_delta)
                        else if ((u?.step_type === "thinking" || u?.step_type === "planner_thinking") && (u.text_delta || u.thinking)) {
                            root.appendThinking(u.text_delta || u.thinking)
                        } else if (u?.step_type === "tool" && u.tool_name) {
                            const tid = "agy" + u.step_index
                            const blk = { name: u.tool_name, input: u.tool_info?.parameters ?? {}, id: tid }
                            if (u.state === "ACTIVE" || u.state === "PENDING") root.addTool(blk)
                            else if (u.state === "DONE" || u.state === "ERROR" || u.state === "FAILED")
                                root.finishTool(tid, u.state !== "DONE", blk, u.tool_info?.output || u.output || "")
                        }
                    } else if (d.event === "result") {
                        const r = d.result
                        if (r?.conversation_id) root.sessionId = r.conversation_id
                        if (r?.status && r.status !== "SUCCESS") root.fail("Antigravity: " + r.status)
                        else if (!root.turnText && r?.response) root.appendText(r.response)
                    }
                } else {
                    if (d.type === "thread.started" && d.thread_id) root.sessionId = d.thread_id
                    else if (d.type === "item.started" && d.item?.type === "reasoning") {
                        if (d.item.text) root.appendThinking(d.item.text)
                    } else if (d.type === "item.completed" && d.item?.type === "reasoning") {
                        if (d.item.text) root.appendThinking(d.item.text)
                        root.finishThinking()
                    } else if ((d.type === "item.started" || d.type === "item.completed") && d.item && d.item.type !== "agent_message" && d.item.type !== "reasoning") {
                        const it = d.item
                        if (d.type === "item.started") {
                            if (it.type === "command_execution") root.addTool({ name: "Команда", input: { command: it.command }, id: it.id })
                            else if (it.type === "mcp_tool_call") root.addTool({ name: "mcp__qs__" + it.tool, input: it.arguments ?? {}, id: it.id })
                            else if (it.type === "file_change") root.addTool({ name: "Правка файлов", input: { path: (it.changes ?? []).map(c => c.path).join(", ") }, id: it.id })
                            else root.addTool({ name: it.type, input: {}, id: it.id })
                        } else {
                            const outTxt = it.aggregated_output || it.output || (it.result ? JSON.stringify(it.result) : "")
                            root.finishTool(it.id, it.status === "failed" || !!it.error || (it.exit_code !== undefined && it.exit_code !== null && it.exit_code !== 0), null, outTxt)
                        }
                    } else if (d.type === "item.completed" && d.item?.type === "agent_message") {
                        const i = root.lastIndex()
                        root.appendText((i >= 0 && root.log.get(i).role === "assistant" && root.log.get(i).text !== "" ? "\n\n" : "") + d.item.text)
                    } else if (d.type === "turn.completed" && d.usage) {
                        root.updateTokenUsage(d.usage.input_tokens || 0, d.usage.output_tokens || 0, 200000)
                    } else if (d.type === "turn.failed" || d.type === "error") {
                        root.fail(d.message || d.error?.message || "Codex: ошибка запроса")
                    }
                }
            }
        }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (!root.wasSteered && code !== 0 && !root.turnOutput && root.provider === "codex" && root.sessionId !== "" && err.text.indexOf("already has an active writer") >= 0) {
                root.sessionId = ""
                const s = Object.assign({}, root.chatSessions); s.codex = ""; root.chatSessions = s
                proc.command = root.launchCommand(root.lastPrompt, true, root.lastFiles, "")
                proc.running = true
                return
            }
            root.busy = false
            root.finishThinking()
            root.denyAll()
            root.cancelQuestion()
            for (let j = 0; j < root.log.count; j++) {
                if (root.log.get(j).role === "tool" && !root.log.get(j).done)
                    root.log.setProperty(j, "done", true)
            }

            let i = root.lastIndex()
            if (i >= 0 && root.log.get(i).role === "assistant") {
                if (root.log.get(i).text === "" && root.turnOutput) root.log.remove(i)
                else if (root.log.get(i).text !== "") {
                    root.log.setProperty(i, "text", root.log.get(i).text.trim())
                    root.log.setProperty(i, "metaJson", JSON.stringify({
                        provider: root.provider,
                        model: root.model,
                        effort: root.effort,
                        elapsedSec: root.turnElapsedSec,
                        steps: root.turnStepCount,
                        steered: root.wasSteered
                    }))
                }
            }

            if (root.wasSteered) {
                if (root.lastEmpty()) root.log.remove(root.lastIndex())
            } else if (!root.turnText) {
                if (code !== 0)
                    root.fail("Не удалось получить ответ" + (err.text.trim() ? ": " + err.text.trim().split("\n").pop().slice(0, 160) : " (код " + code + ")"))
                else if (!root.turnOutput)
                    root.fail("Пустой ответ")
                else
                    root.appendText("Готово.")
            }

            // Извлекаем карточку <proposed_plan>, если агент вывел её в тексте ответа
            root.extractProposedPlanFromAssistant()

            // Обновляем сессию и счётчик просмотренных сообщений для текущего провайдера (Context Handoff)
            const sess = Object.assign({ claude: "", codex: "", agy: "" }, root.chatSessions)
            if (root.sessionId) sess[root.provider] = root.sessionId
            root.chatSessions = sess
            const seen = Object.assign({ claude: 0, codex: 0, agy: 0 }, root.chatLastSeen)
            seen[root.provider] = root.log.count
            root.chatLastSeen = seen

            // Оценка токенов, если CLI не прислал точную телеметрию
            if (root.tokenUsage.total === 0 && root.log.count > 0) {
                let chars = 0
                for (let k = 0; k < root.log.count; k++) chars += (root.log.get(k).text || "").length
                const estTokens = Math.ceil(chars / 3.6)
                root.updateTokenUsage(Math.round(estTokens * 0.7), Math.round(estTokens * 0.3), 200000)
            }

            // Захватываем post-turn git чекпоинт (если в рабочей папке есть git)
            if (root.gitInfo.isGit && !postTurnProc.running) {
                const args = [root.clipCmd, "checkpoint-capture", root.cwd, root.chatId || "default", "post_" + root.currentTurnId]
                if (root.preTurnRef) args.push(root.preTurnRef)
                postTurnProc.command = args
                postTurnProc.running = true
            }

            if (!root.windowOpen) root.unread++
            root.save()

            // Если ход был прерван живым перенаправлением (Steer / Ctrl+Enter) — сразу запускаем новый запрос!
            if (root.pendingSteerPayload) {
                const p = root.pendingSteerPayload
                root.pendingSteerPayload = null
                root.sendInternal(p.text, p.files, p.chips, p.mode || "steered")
                return
            }

            // Если в очереди есть сообщения и очередь не на паузе — запускаем следующее!
            if (!root.queueHeld && root.queuedMessages.count > 0) {
                drainQueueTimer.restart()
                return
            }

            // Проверяем, не завершилась ли когорта фоновых субагентов во время хода
            checkCohortWakeTimer.restart()
            postTurnLimitsTimer.restart()
        }
    }

    // ── Разговоры из консольных клиентов (ai-sessions)
    property var importList: []
    property bool importBusy: false
    function loadImports() { if (!listProc.running) listProc.running = true }
    Process {
        id: listProc
        command: [root.home + "/.local/bin/ai-sessions", "list"]
        onRunningChanged: root.importBusy = running
        stdout: StdioCollector { onStreamFinished: { try { root.importList = JSON.parse(text) } catch (e) {} } }
    }
    property var importTarget: null
    function importChat(item) {
        const existing = db.chats.find(c => c.provider === item.provider && c.session === item.id)
        if (existing) { openChat(existing.id); return }
        importTarget = item
        loadProc.command = [home + "/.local/bin/ai-sessions", "load", item.provider, item.id]
        loadProc.running = true
    }
    Process {
        id: loadProc
        stdout: StdioCollector {
            onStreamFinished: {
                const it = root.importTarget
                if (!it) return
                try {
                    const d = JSON.parse(text)
                    root.syncCurrent()
                    const sess = { claude: "", codex: "", agy: "" }
                    sess[it.provider] = it.id
                    const c = {
                        id: root.uid(),
                        provider: it.provider,
                        providersUsed: [it.provider],
                        title: it.title,
                        session: it.id,
                        sessions: sess,
                        lastSeenCount: { claude: 0, codex: 0, agy: 0 },
                        cwd: d.cwd || root.home,
                        agent: false,
                        imported: true,
                        updated: Math.floor(Date.now() / 1000),
                        log: (d.log ?? []).map(m => ({ role: m.role, text: m.text, error: false, kind: "", done: true, tid: "", filesJson: "", output: "", metaJson: "" }))
                    }
                    root.db.chats.push(c)
                    root.loadChat(c)
                    root.save()
                } catch (e) {}
                root.importTarget = null
            }
        }
    }

    // ── Запуск: каталог моделей, конфиг MCP, сохранённые чаты
    Process {
        running: true
        command: [root.home + "/.local/bin/ai-models"]
        stdout: StdioCollector { onStreamFinished: { try { root.catalog = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$1/work" "$1/attachments" && printf \'{"mcpServers":{"qs":{"command":"%s"}}}\' "$2" > "$1/mcp.json"', "sh", root.dir, root.mcpCmd]
    }
    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (d.chats) {
                    root.db = { active: d.active ?? "", chats: d.chats }
                    root.limits = d.limits ?? {}
                    root.stashList = d.stash ?? []
                } else {
                    const chats = []
                    for (const p of ["claude", "agy", "codex"]) {
                        const x = d[p]
                        if (x && (x.log?.length ?? 0) > 0) chats.push({
                            id: root.uid(), provider: p, providersUsed: [p],
                            title: (x.log.find(m => m.role === "user")?.text ?? "Чат").slice(0, 70),
                            session: x.session ?? "", cwd: root.home, agent: false, imported: false,
                            updated: Math.floor(Date.now() / 1000), log: x.log
                        })
                    }
                    root.db = { active: "", chats: chats }
                }
                const hist = []
                for (const c of root.db.chats.slice().sort((a, b) => a.updated - b.updated)) {
                    for (const m of c.log ?? []) if (m.role === "user" && m.text) {
                        const t = m.text.trim()
                        if (t && hist[hist.length - 1] !== t) hist.push(t)
                    }
                }
                root.promptHistory = hist.slice(-50)
                const cur = root.db.chats.find(c => c.id === root.db.active) ?? root.db.chats.slice().sort((a, b) => b.updated - a.updated)[0]
                if (cur) root.loadChat(cur)
                else root.newChat("claude")
                root.refreshList()
            } catch (e) { root.newChat("claude") }
            if (!root.limits.ts || Math.floor(Date.now() / 1000) - root.limits.ts > 900) root.refreshLimits(false)
        }
    }
}
