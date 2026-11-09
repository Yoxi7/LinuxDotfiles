pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Полнофункциональный интерфейс чата и мультиагентной оркестрации (в стиле T3 Code + Quickshell lite).
// Включает:
//   • Боковую панель с поиском, полками (Все / 📌 Закреп / 🤖 Субагенты / ✓ Архив), индикаторами веток git, мульти-провайдеров и действий (Pin, Fork, Архив);
//   • Переключение провайдеров (Claude, Antigravity, Codex) внутри одного треда с автоматическим Context Handoff;
//   • Управление git-ветками и изолированными git worktree прямо из шапки чата, счётчик контекста/токенов и поиск по чату (Ctrl+F);
//   • Таймлайн с карточками размышлений (🧠), раскрываемыми инструментами с выводом, живыми карточками субагентов (🤖),
//     карточками планов (📋 Proposed Plan), карточками изменённых файлов и чекпоинтов с просмотром diff и откатом,
//     а также блоками кода с подсветкой заголовка, копированием и запуском в терминале;
//   • Панель интерактивных вопросов (AskUserQuestion), разрешений инструментов и управления очередью сообщений (Queue / Steer / Hold);
//   • Композер с контекстными чипами (@файл, @тред, $скилл, ❝ цитата), автодополнением /, @ и $, переключателем Код/План (Shift+Tab),
//     режимами разрешений, карманом черновиков (Stash / Ctrl+S), очередью (Enter) и живым перенаправлением (Ctrl+Enter).
Item {
    id: root
    property bool active: true
    property bool compact: false
    readonly property bool showSide: compact ? sideForced : Session.aiSidebar
    property bool sideForced: false
    property bool importOpen: false
    property string importFilter: ""

    // Боковая панель: фильтр и поиск
    property string sideQuery: ""
    property string sideShelf: "active"                      // "active" | "pinned" | "subagents" | "archived"

    // Поиск внутри текущего треда (Ctrl+F)
    property bool findOpen: false
    property string findQuery: ""

    // Всплывающие окна шапки и композера
    property bool gitPopupOpen: false
    property bool stashPopupOpen: false
    property bool titleEditing: false

    // Превью изображения
    property string previewPath: ""
    property string previewTitle: ""

    // История ввода ↑/↓
    property int histIdx: -1
    property string histDraft: ""

    // Автодополнение /, @ и $
    property int slashIdx: 0
    property bool slashDismissed: false
    property int mentionIdx: 0
    property string lastAtQuery: ""

    // Определение активного триггера автодополнения (/ в начале, либо @ / $ у курсора)
    readonly property var tokenTrigger: {
        const t = input.text
        const pos = Math.max(0, Math.min(t.length, input.cursorPosition))
        const before = t.slice(0, pos)
        const m = before.match(/(?:^|\s)([@$])([^\s@$]*)$/)
        if (!m) return { kind: "", query: "", start: -1, end: pos }
        const sym = m[1]
        const q = m[2] || ""
        const start = pos - q.length - 1
        return { kind: sym === "@" ? "at" : "skill", query: q, start: start, end: pos }
    }
    onTokenTriggerChanged: {
        mentionIdx = 0
        if (tokenTrigger.kind === "at" && tokenTrigger.query !== lastAtQuery) {
            lastAtQuery = tokenTrigger.query
            Ai.searchFiles(tokenTrigger.query)
        }
    }

    readonly property var slashMatches: {
        const t = input.text
        if (slashDismissed || !t.startsWith("/") || t.indexOf("\n") >= 0) return []
        const sp = t.indexOf(" ")
        if (sp >= 0) return []
        const q = t.slice(1).toLowerCase()
        return Ai.slashCommands.filter(c => c.cmd.slice(1).indexOf(q) === 0 || c.desc.toLowerCase().indexOf(q) >= 0)
    }
    onSlashMatchesChanged: slashIdx = 0
    readonly property bool slashOpen: slashMatches.length > 0 && tokenTrigger.kind === ""

    readonly property var mentionMatches: {
        if (tokenTrigger.kind === "at") {
            const q = tokenTrigger.query.toLowerCase()
            const threads = Ai.chatList
                .filter(c => c.id !== Ai.chatId && (q === "" || (c.title || "").toLowerCase().indexOf(q) >= 0))
                .slice(0, 5)
                .map(c => ({ kind: "thread", label: c.title || "Чат", value: c.id, detail: "Тред · " + root.provName(c.provider) }))
            const files = (Ai.fileMatches ?? []).slice(0, 20).map(f => ({
                kind: f.type === "dir" ? "dir" : "file",
                label: f.rel || f.name,
                value: f.path,
                detail: f.type === "dir" ? "Папка" : "Файл"
            }))
            return threads.concat(files)
        }
        if (tokenTrigger.kind === "skill") {
            const q = tokenTrigger.query.toLowerCase()
            return (Ai.skillItems ?? [])
                .filter(s => q === "" || s.name.toLowerCase().indexOf(q) >= 0 || s.desc.toLowerCase().indexOf(q) >= 0)
                .slice(0, 20)
                .map(s => ({
                    kind: "skill",
                    label: "$" + s.name,
                    value: s.name,
                    detail: s.path || s.desc,
                    desc: s.desc,
                    provider: s.provider
                }))
        }
        return []
    }
    readonly property bool mentionOpen: mentionMatches.length > 0

    function applySlash(item, executeNow) {
        if (!item) return
        if (executeNow && !item.args.startsWith("<")) {
            input.text = item.cmd
            submit()
        } else {
            input.text = item.cmd + " "
            input.cursorPosition = input.text.length
            input.forceActiveFocus()
        }
    }

    function applyMention(item) {
        if (!item) return
        const tr = tokenTrigger
        if (tr.start >= 0) {
            const before = input.text.slice(0, tr.start)
            const after = input.text.slice(tr.end)
            input.text = before + after
            input.cursorPosition = before.length
        }
        Ai.addContextChip(item.kind, item.label, item.value, item.detail || "")
        input.forceActiveFocus()
    }

    readonly property bool canSend: input.text.trim() !== "" || Ai.attachments.count > 0 || Ai.contextChips.count > 0
    readonly property var suggestions: [
        "Спланируй архитектуру и покажи карточку плана",
        "Позови субагента Codex и проверь git-изменения",
        "Проведи демонстрацию оболочки (/demo)",
        "Какие окна открыты и что сейчас на баре?"
    ]

    // Фильтрация чатов в боковой панели
    readonly property var filteredChats: {
        const q = sideQuery.trim().toLowerCase()
        return (Ai.chatList ?? []).filter(c => {
            if (sideShelf === "pinned" && !c.pinned) return false
            if (sideShelf === "subagents" && !c.isSubagent) return false
            if (sideShelf === "archived" && !c.settled) return false
            if (sideShelf === "active" && c.settled && c.id !== Ai.chatId) return false
            if (!q) return true
            return (c.title || "").toLowerCase().indexOf(q) >= 0
                || (c.worktreeBranch || "").toLowerCase().indexOf(q) >= 0
                || (c.cwd || "").toLowerCase().indexOf(q) >= 0
                || (c.provider || "").toLowerCase().indexOf(q) >= 0
        })
    }

    // Разбор текста ответа помощника на чередующиеся блоки текста и кода (```lang ... ```)
    function parseMessageBlocks(raw) {
        if (!raw) return [{ isCode: false, text: "", lang: "" }]
        const blocks = []
        const re = /```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```/g
        let lastIdx = 0
        let m = null
        while ((m = re.exec(raw)) !== null) {
            if (m.index > lastIdx) {
                const prose = raw.slice(lastIdx, m.index).trim()
                if (prose) blocks.push({ isCode: false, text: prose, lang: "" })
            }
            blocks.push({
                isCode: true,
                lang: (m[1] || "code").trim(),
                text: (m[2] || "").replace(/\n$/, "")
            })
            lastIdx = re.lastIndex
        }
        if (lastIdx < raw.length) {
            const tail = raw.slice(lastIdx).trim()
            if (tail || blocks.length === 0) blocks.push({ isCode: false, text: tail, lang: "" })
        }
        return blocks.length ? blocks : [{ isCode: false, text: raw, lang: "" }]
    }

    function activate() { Ai.windowOpen = true; Ai.unread = 0; Qt.callLater(() => input.forceActiveFocus()) }
    onActiveChanged: { if (active) activate(); else if (!Ai.picking) Ai.windowOpen = false }
    Component.onCompleted: { if (active) activate(); Ai.refreshLimits(Ai.limits.claude === undefined); Ai.refreshGitInfo() }
    Component.onDestruction: Ai.windowOpen = false

    // ── Буфер обмена, файлы и скриншоты (ai-clip)
    function handleClipOutput(raw, allowTextInsert) {
        let d = null
        try { d = JSON.parse(raw) } catch (e) { return }
        if (d.kind === "files" && d.items && d.items.length > 0) {
            Ai.addAttachments(d.items)
            Qt.callLater(() => input.forceActiveFocus())
        } else if (allowTextInsert && d.kind === "text" && d.text !== undefined && d.text !== "") {
            if (input.selectionStart !== input.selectionEnd)
                input.remove(input.selectionStart, input.selectionEnd)
            input.insert(input.cursorPosition, d.text)
            Qt.callLater(() => input.forceActiveFocus())
        }
    }
    function pasteClipboard() { if (!clipProc.running) clipProc.running = true }
    function pickFiles() {
        if (pickProc.running) return
        Ai.picking = true
        pickProc.command = [Ai.clipCmd, "pick"]
        pickProc.running = true
    }
    function takeScreenshot(mode) {
        if (pickProc.running) return
        Ai.picking = true
        pickProc.command = [Ai.clipCmd, "shot", mode || "region"]
        pickProc.running = true
    }
    function inspectDropped(items) {
        if (!items || items.length === 0 || inspectProc.running) return
        inspectProc.command = [Ai.clipCmd, "inspect"].concat(items)
        inspectProc.running = true
    }

    Process {
        id: clipProc
        command: [Ai.clipCmd, "paste"]
        stdout: StdioCollector { onStreamFinished: root.handleClipOutput(text, true) }
    }
    Process {
        id: pickProc
        onExited: { Ai.picking = false; Qt.callLater(() => input.forceActiveFocus()) }
        stdout: StdioCollector { onStreamFinished: root.handleClipOutput(text, false) }
    }
    Process {
        id: inspectProc
        stdout: StdioCollector { onStreamFinished: root.handleClipOutput(text, false) }
    }

    function submit() {
        const t = input.text.trim()
        if (!canSend) return
        input.text = ""
        histIdx = -1
        histDraft = ""
        Ai.send(t)
        list.positionViewAtEnd()
    }
    function submitSteer() {
        const t = input.text.trim()
        if (!canSend) return
        input.text = ""
        histIdx = -1
        histDraft = ""
        Ai.steer(t)
        list.positionViewAtEnd()
    }

    function ago(ts) {
        const d = Math.floor(Date.now() / 1000) - ts
        if (d < 60) return "только что"
        if (d < 3600) return Math.floor(d / 60) + " мин"
        if (d < 86400) return Math.floor(d / 3600) + " ч"
        return Math.floor(d / 86400) + " дн"
    }
    function until(ts) {
        const d = ts - Math.floor(Date.now() / 1000)
        if (d <= 0) return "сейчас"
        if (d < 3600) return "через " + Math.ceil(d / 60) + " мин"
        if (d < 86400) return "через " + Math.floor(d / 3600) + " ч " + Math.floor(d % 3600 / 60) + " мин"
        return "через " + Math.floor(d / 86400) + " дн " + Math.floor(d % 86400 / 3600) + " ч"
    }
    function provColor(p) { return p === "claude" ? "#d97757" : p === "agy" ? "#5b8def" : "#10a37f" }
    function provName(p) { return p === "claude" ? "Claude" : p === "agy" ? "Antigravity" : "Codex" }
    function shortDir(d) { return (d ?? "").replace(Ai.home, "~") }

    // ── Всплывающие подсказки
    property Item tipItem: null
    property string tipText: ""
    function tipRequest(item, text) {
        if (item === null) { tipPending = null; tipTimer.stop(); tipItem = null; return }
        tipPending = item; tipText = text; tipTimer.restart()
    }
    property Item tipPending: null
    Timer { id: tipTimer; interval: 320; onTriggered: root.tipItem = root.tipPending }
    Rectangle {
        id: tipBox
        z: 120
        visible: root.tipItem !== null && root.tipText !== ""
        opacity: visible ? 1 : 0
        readonly property point pos: root.tipItem ? root.tipItem.mapToItem(root, 0, 0) : Qt.point(0, 0)
        width: Math.min(320, tipLabel.implicitWidth + 20)
        height: tipLabel.implicitHeight + 14
        x: Math.max(4, Math.min(root.width - width - 4, pos.x + (root.tipItem ? root.tipItem.width / 2 : 0) - width / 2))
        y: pos.y + (root.tipItem ? root.tipItem.height : 0) + 8 + height > root.height ? pos.y - height - 8 : pos.y + (root.tipItem ? root.tipItem.height : 0) + 8
        radius: 10
        color: Qt.rgba(0.04, 0.04, 0.06, 0.96)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
        Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
        Text {
            id: tipLabel
            x: 10; y: 7
            width: 300
            text: root.tipText
            wrapMode: Text.Wrap
            color: Theme.text
            font { family: Theme.font; pixelSize: 12 }
            onTextChanged: width = Math.min(300, implicitWidth)
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        property bool dim: false
        property string tip: ""
        property color tint: Theme.primary
        signal clicked
        height: 26
        width: cl.implicitWidth + 20
        radius: 13
        opacity: dim ? 0.45 : 1
        color: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.28) : chm.containsMouse ? Theme.strong : Theme.weak
        border { width: on ? 1 : 0; color: Qt.rgba(tint.r, tint.g, tint.b, 0.7) }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text { id: cl; anchors.centerIn: parent; text: chip.label; color: Theme.text; font { family: Theme.font; pixelSize: 11; weight: chip.on ? Font.DemiBold : Font.Medium } }
        MouseArea {
            id: chm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (chip.tip !== "") root.tipRequest(containsMouse ? chip : null, chip.tip)
            onClicked: { root.tipRequest(null, ""); chip.clicked() }
        }
    }
    component IconBtn: Rectangle {
        id: ib
        property string icon
        property bool on: false
        property string tip: ""
        property color tint: Theme.muted
        signal clicked
        width: 28; height: 28; radius: 14
        color: on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : ibm.containsMouse ? Theme.strong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text { anchors.centerIn: parent; text: ib.icon; color: ib.on ? Theme.primary : ibm.containsMouse ? Theme.text : ib.tint; font { family: Theme.iconFont; pixelSize: 12 } }
        MouseArea {
            id: ibm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (ib.tip !== "") root.tipRequest(containsMouse ? ib : null, ib.tip)
            onClicked: { root.tipRequest(null, ""); ib.clicked() }
        }
    }

    // ═══════════ 1. БОКОВАЯ ПАНЕЛЬ (ТРЕДЫ, ПОИСК, ПОЛКИ, ИМПОРТ ИЗ КОНСОЛИ)
    Rectangle {
        id: side
        visible: root.showSide
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: root.compact ? Math.min(270, parent.width * 0.65) : 284
        z: 5
        radius: 16
        color: root.compact ? Qt.rgba(0.05, 0.05, 0.07, 0.96) : Qt.rgba(0, 0, 0, 0.24)
        border { width: root.compact ? 1 : 0; color: Qt.rgba(1, 1, 1, 0.1) }

        Item {
            id: sideHead
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            height: 30
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: root.importOpen ? "Из консоли" : "Треды (" + root.filteredChats.length + ")"
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                IconBtn {
                    icon: ""
                    tip: "Новый чат (" + root.provName(Ai.provider) + ")"
                    visible: !root.importOpen
                    onClicked: { Ai.newChat(Ai.provider); root.importOpen = false }
                }
                IconBtn {
                    icon: "⑂"
                    tip: "Ответвить текущий чат (Fork)"
                    visible: !root.importOpen && Ai.log.count > 0
                    onClicked: Ai.forkChat(Ai.chatId, -1, "")
                }
                IconBtn {
                    icon: root.importOpen ? "" : ""
                    tip: root.importOpen ? "Назад к чатам" : "Подтянуть разговоры из Claude Code, Codex и Antigravity"
                    on: root.importOpen
                    onClicked: { root.importOpen = !root.importOpen; if (root.importOpen) Ai.loadImports() }
                }
            }
        }

        // Поиск и полки тредов (когда не открыт импорт)
        Column {
            id: sideFilterCol
            visible: !root.importOpen
            anchors { left: parent.left; right: parent.right; top: sideHead.bottom; leftMargin: 8; rightMargin: 8; topMargin: 2 }
            spacing: 6

            Rectangle {
                width: parent.width; height: 28; radius: 10
                color: Qt.rgba(1, 1, 1, 0.05)
                border { width: 1; color: sideSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.08) }
                Text { x: 9; anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.faint; font { family: Theme.iconFont; pixelSize: 11 } }
                TextInput {
                    id: sideSearchInput
                    anchors { left: parent.left; right: parent.right; leftMargin: 26; rightMargin: 24; verticalCenter: parent.verticalCenter }
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 12 }
                    selectByMouse: true
                    onTextChanged: root.sideQuery = text
                    Keys.onEscapePressed: { text = ""; input.forceActiveFocus() }
                    Text {
                        visible: sideSearchInput.text === ""
                        text: "Поиск по тредам, веткам, папкам…"
                        color: Theme.faint
                        font: sideSearchInput.font
                    }
                }
                Text {
                    visible: sideSearchInput.text !== ""
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: ""
                    color: Theme.muted
                    font { family: Theme.iconFont; pixelSize: 10 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sideSearchInput.text = "" }
                }
            }

            Row {
                spacing: 4
                Chip { height: 22; label: "Активные"; on: root.sideShelf === "active"; onClicked: root.sideShelf = "active" }
                Chip { height: 22; label: "📌"; tip: "Закреплённые треды"; on: root.sideShelf === "pinned"; onClicked: root.sideShelf = "pinned" }
                Chip { height: 22; label: "🤖"; tip: "Треды субагентов"; on: root.sideShelf === "subagents"; onClicked: root.sideShelf = "subagents" }
                Chip { height: 22; label: "✓"; tip: "Завершённые / Архив"; on: root.sideShelf === "archived"; onClicked: root.sideShelf = "archived" }
            }
        }

        // Список тредов
        ListView {
            id: chats
            visible: !root.importOpen
            anchors { left: parent.left; right: parent.right; top: sideFilterCol.bottom; bottom: parent.bottom; margins: 8; topMargin: 6 }
            clip: true
            spacing: 3
            model: root.filteredChats
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: crow
                required property var modelData
                readonly property bool cur: modelData.id === Ai.chatId
                readonly property var provs: modelData.providersUsed ?? [modelData.provider]
                width: chats.width; height: 60; radius: 12
                color: cur ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : crm.containsMouse ? Theme.weak : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dFast } }

                // Полоска провайдера (или мульти-провайдерный стек)
                Column {
                    x: 6; y: 11
                    spacing: 2
                    Repeater {
                        model: crow.provs.slice(0, 3)
                        Rectangle {
                            required property string modelData
                            width: 3.5
                            height: Math.max(8, Math.floor((38 - (crow.provs.length - 1) * 2) / Math.min(3, crow.provs.length)))
                            radius: 1.5
                            color: root.provColor(modelData)
                        }
                    }
                }

                Column {
                    anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: crm.containsMouse || rowActionsHover.hovered ? 82 : 10; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Row {
                        width: parent.width
                        spacing: 5
                        Text {
                            visible: !!crow.modelData.pinned
                            text: "📌"
                            font { pixelSize: 10 }
                        }
                        Text {
                            visible: !!crow.modelData.isSubagent
                            text: "🤖"
                            font { pixelSize: 10 }
                        }
                        Text {
                            width: parent.width - (crow.modelData.pinned ? 16 : 0) - (crow.modelData.isSubagent ? 16 : 0)
                            elide: Text.ElideRight
                            text: crow.modelData.title
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 12; weight: crow.cur ? Font.DemiBold : Font.Medium }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            text: crow.provs.map(p => root.provName(p)).join("→") + " · " + root.ago(crow.modelData.updated)
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 10 }
                        }
                        Rectangle {
                            visible: (crow.modelData.worktreeBranch || "") !== ""
                            height: 15; width: wtBadgeTxt.implicitWidth + 8; radius: 4
                            color: Qt.rgba(0.06, 0.64, 0.5, 0.2)
                            Text {
                                id: wtBadgeTxt
                                anchors.centerIn: parent
                                text: "⑂ " + crow.modelData.worktreeBranch
                                color: "#10a37f"
                                font { family: "MedeoMono Nerd Font Mono"; pixelSize: 9 }
                            }
                        }
                        Rectangle {
                            visible: !!crow.modelData.hasActivePlan
                            height: 15; width: 38; radius: 4
                            color: Qt.rgba(0.96, 0.62, 0.04, 0.2)
                            Text { anchors.centerIn: parent; text: "ПЛАН"; color: "#f59e0b"; font { family: Theme.font; pixelSize: 8; weight: Font.Bold } }
                        }
                    }
                }

                MouseArea {
                    id: crm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Ai.openChat(crow.modelData.id); if (root.compact) root.sideForced = false }
                }

                // Кнопки быстрых действий над тредом: Pin, Fork, Архив, Удалить
                Row {
                    visible: crm.containsMouse || rowActionsHover.hovered
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    HoverHandler { id: rowActionsHover }

                    IconBtn {
                        width: 22; height: 22; radius: 11
                        icon: ""
                        on: !!crow.modelData.pinned
                        tip: crow.modelData.pinned ? "Открепить тред" : "Закрепить тред"
                        onClicked: Ai.togglePinChat(crow.modelData.id)
                    }
                    IconBtn {
                        width: 22; height: 22; radius: 11
                        icon: ""
                        on: !!crow.modelData.settled
                        tip: crow.modelData.settled ? "Вернуть из архива" : "Завершить / В архив"
                        onClicked: Ai.toggleSettleChat(crow.modelData.id)
                    }
                    IconBtn {
                        width: 22; height: 22; radius: 11
                        icon: ""
                        tint: Theme.danger
                        tip: "Удалить тред"
                        onClicked: Ai.deleteChat(crow.modelData.id)
                    }
                }
            }
        }

        // Импорт из консольных клиентов
        Item {
            id: imp
            visible: root.importOpen
            anchors { left: parent.left; right: parent.right; top: sideHead.bottom; bottom: parent.bottom; margins: 8; topMargin: 6 }
            Flow {
                id: impFilter
                width: parent.width
                spacing: 4
                Chip { label: "Все"; on: root.importFilter === ""; onClicked: root.importFilter = "" }
                Chip { label: "Claude"; tint: root.provColor("claude"); on: root.importFilter === "claude"; onClicked: root.importFilter = "claude" }
                Chip { label: "Codex"; tint: root.provColor("codex"); on: root.importFilter === "codex"; onClicked: root.importFilter = "codex" }
                Chip { label: "Antigravity"; tint: root.provColor("agy"); on: root.importFilter === "agy"; onClicked: root.importFilter = "agy" }
            }
            Text {
                visible: Ai.importBusy && Ai.importList.length === 0
                anchors { top: impFilter.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                text: "Ищу разговоры…"
                color: Theme.muted
                font { family: Theme.font; pixelSize: 12 }
            }
            ListView {
                anchors { left: parent.left; right: parent.right; top: impFilter.bottom; bottom: parent.bottom; topMargin: 8 }
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: Ai.importList.filter(x => root.importFilter === "" || x.provider === root.importFilter)
                delegate: Rectangle {
                    id: irow
                    required property var modelData
                    width: ListView.view.width; height: 58; radius: 12
                    color: im.containsMouse ? Theme.weak : "transparent"
                    Rectangle { x: 6; y: 12; width: 3; height: parent.height - 24; radius: 1.5; color: root.provColor(irow.modelData.provider) }
                    Column {
                        anchors { left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: irow.modelData.title; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Medium } }
                        Text {
                            width: parent.width; elide: Text.ElideMiddle
                            text: root.provName(irow.modelData.provider) + " · " + root.shortDir(irow.modelData.cwd) + " · " + root.ago(irow.modelData.updated)
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }
                    MouseArea {
                        id: im
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Ai.importChat(irow.modelData); root.importOpen = false; if (root.compact) root.sideForced = false }
                    }
                }
            }
        }
    }

    // ═══════════ 2. ОСНОВНАЯ КОЛОНКА
    Item {
        id: main
        anchors { left: root.showSide && !root.compact ? side.right : parent.left; leftMargin: root.showSide && !root.compact ? 14 : 0; right: parent.right; top: parent.top; bottom: parent.bottom }

        // ── Строка 1: Провайдеры (с Context Handoff в текущем треде) · Git/Worktree · Папка · Токены · Поиск
        Item {
            id: row1
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 30
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 4
                IconBtn {
                    tip: "Панель тредов"
                    icon: ""
                    on: root.showSide
                    onClicked: { if (root.compact) root.sideForced = !root.sideForced; else Session.aiSidebar = !Session.aiSidebar }
                }
                Repeater {
                    model: Ai.providers
                    Chip {
                        required property var modelData
                        label: modelData.label
                        tint: root.provColor(modelData.id)
                        tip: "Переключить активного агента в этом треде на " + modelData.label + " (с автоматической передачей контекста Context Handoff)"
                        on: Ai.provider === modelData.id
                        dim: Ai.busy && !on
                        onClicked: Ai.setProvider(modelData.id, false)
                    }
                }
                IconBtn {
                    icon: ""
                    tip: "Начать новый чистый тред"
                    visible: Ai.log.count > 0
                    onClicked: Ai.newChat(Ai.provider)
                }
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4

                // Ссылка на родительский тред (если это субагент или Fork)
                Chip {
                    visible: Ai.parentChatId !== ""
                    label: "↑ К родителю"
                    tint: Theme.accent
                    tip: "Вернуться в родительский тред"
                    onClicked: Ai.openChat(Ai.parentChatId)
                }

                // Git ветка и Worktree
                Chip {
                    visible: !!Ai.gitInfo?.isGit
                    label: (Ai.gitInfo?.isWorktree ? "⑂ WT: " : "⑂ ") + (Ai.gitInfo?.branch || "git") + (Ai.gitInfo?.dirtyCount > 0 ? " *" + Ai.gitInfo.dirtyCount : "")
                    tint: Ai.gitInfo?.isWorktree ? "#10a37f" : Theme.primary
                    on: root.gitPopupOpen || !!Ai.gitInfo?.isWorktree
                    tip: "Git-ветка и управление изолированным Worktree (клик — открыть меню)"
                    onClicked: root.gitPopupOpen = !root.gitPopupOpen
                }

                // Рабочая папка (CWD)
                Rectangle {
                    id: cwdChip
                    property bool editing: false
                    height: 26; width: cwdChip.editing ? 220 : Math.min(180, cwdText.implicitWidth + 32); radius: 13
                    color: cwdM.containsMouse || editing ? Theme.strong : Theme.weak
                    Behavior on width { NumberAnimation { duration: Theme.dFast } }
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "\uf07b"; color: Theme.muted; font { family: Theme.iconFont; pixelSize: 11 } }
                    Text {
                        id: cwdText
                        visible: !cwdChip.editing
                        x: 26; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: root.shortDir(Ai.cwd)
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    TextInput {
                        id: cwdInput
                        visible: cwdChip.editing
                        x: 26; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 11 }
                        clip: true
                        selectByMouse: true
                        onAccepted: { Ai.setCwd(text); cwdChip.editing = false; input.forceActiveFocus() }
                        Keys.onEscapePressed: { cwdChip.editing = false; input.forceActiveFocus() }
                    }
                    MouseArea {
                        id: cwdM
                        anchors.fill: parent
                        enabled: !cwdChip.editing
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tipRequest(containsMouse ? cwdChip : null, "Рабочая папка: " + Ai.cwd + " (клик — изменить)")
                        onClicked: { cwdInput.text = Ai.cwd; cwdChip.editing = true; cwdInput.forceActiveFocus(); cwdInput.selectAll() }
                    }
                }

                // Индикатор заполнения контекстного окна + быстрый /compact
                Chip {
                    visible: (Ai.tokenUsage?.total || 0) > 0
                    label: "◎ " + Math.max(1, Math.round((Ai.tokenUsage?.total || 0) / 1000)) + "k (" + (Ai.tokenUsage?.percent || 0) + "%)"
                    tint: (Ai.tokenUsage?.percent || 0) > 80 ? Theme.danger : (Ai.tokenUsage?.percent || 0) > 50 ? "#ffd60a" : "#30d158"
                    tip: "Использовано ~" + (Ai.tokenUsage?.total || 0) + " токенов (вход: " + (Ai.tokenUsage?.input || 0) + ", выход: " + (Ai.tokenUsage?.output || 0) + "). Нажмите, чтобы сжать контекст (/compact)"
                    onClicked: if (!Ai.busy) Ai.send("/compact")
                }

                IconBtn {
                    icon: ""
                    on: root.findOpen
                    tip: "Поиск по сообщениям в чате (Ctrl+F)"
                    onClicked: { root.findOpen = !root.findOpen; if (root.findOpen) Qt.callLater(() => findInput.forceActiveFocus()) }
                }
                IconBtn {
                    icon: ""
                    tip: "Очистить текущий чат"
                    visible: Ai.log.count > 0
                    tint: Theme.muted
                    onClicked: Ai.clear()
                }
            }
        }

        // ── Строка 2: Модели и effort (компактная объединённая полоса)
        Flow {
            id: modelRow
            anchors { top: row1.bottom; topMargin: 6; left: parent.left; right: parent.right }
            spacing: 4
            Repeater {
                model: Ai.modelsOf(Ai.provider)
                Chip {
                    required property var modelData
                    label: modelData.label
                    tip: modelData.id
                    on: Ai.model === modelData.id
                    onClicked: Ai.setPref(Ai.provider, "model", modelData.id)
                }
            }
            Rectangle {
                visible: Ai.efforts.length > 0
                width: 1; height: 20
                color: Qt.rgba(1, 1, 1, 0.12)
            }
            Chip {
                visible: Ai.efforts.length > 0 && Ai.provider !== "agy"
                label: "авто"
                tip: "Уровень рассуждений по умолчанию"
                on: Ai.effort === ""
                onClicked: Ai.setPref(Ai.provider, "effort", "")
            }
            Repeater {
                model: Ai.efforts
                Chip {
                    required property string modelData
                    label: modelData
                    tip: "Уровень рассуждений (effort): " + modelData
                    on: Ai.effort === modelData
                    onClicked: Ai.setPref(Ai.provider, "effort", modelData)
                }
            }
        }

        // ── Строка 3: Лимиты подписок + живой баннер работы агента
        Item {
            id: limitsRow
            anchors { top: modelRow.bottom; topMargin: 6; left: parent.left; right: parent.right }
            height: 22
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 12
                Repeater {
                    model: Ai.limitRows(Ai.provider)
                    Row {
                        id: lim
                        required property var modelData
                        spacing: 5
                        readonly property real used: Math.max(0, Math.min(1, modelData.used))
                        Text { anchors.verticalCenter: parent.verticalCenter; text: lim.modelData.label; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64; height: 5; radius: 2.5
                            color: Theme.strong
                            Rectangle {
                                width: parent.width * lim.used; height: parent.height; radius: 2.5
                                color: lim.used > 0.85 ? Theme.danger : lim.used > 0.6 ? "#ffd60a" : "#30d158"
                                Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round((1 - lim.used) * 100) + "%" + (lim.modelData.reset ? " · " + root.until(lim.modelData.reset) : "")
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                        }
                    }
                }
                Text {
                    visible: Ai.limitRows(Ai.provider).length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Ai.provider === "claude" ? "лимиты появятся после ответа или по обновлению" : "лимиты не получены"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8

                // Живой индикатор времени хода и шагов (Working Timer)
                Rectangle {
                    visible: Ai.busy
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20; width: workRow.implicitWidth + 14; radius: 10
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                    Row {
                        id: workRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: ""
                            color: Theme.primary
                            font { family: Theme.iconFont; pixelSize: 10 }
                            RotationAnimator on rotation { running: Ai.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                        Text {
                            text: "Работает " + Ai.turnElapsedSec + " с" + (Ai.turnStepCount > 0 ? " · шаг " + Ai.turnStepCount : "")
                            color: Theme.primary
                            font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                        }
                    }
                }

                IconBtn {
                    width: 22; height: 22; radius: 11
                    icon: ""
                    tip: "Обновить лимиты всех подписок"
                    on: Ai.limitsBusy
                    onClicked: Ai.refreshLimits(true)
                }
            }
        }

        // ── Полоса поиска внутри треда (Ctrl+F)
        Rectangle {
            id: findBar
            visible: root.findOpen
            anchors { top: limitsRow.bottom; topMargin: 4; left: parent.left; right: parent.right }
            height: visible ? 30 : 0
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.06)
            border { width: 1; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45) }
            Row {
                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 11 } }
                TextInput {
                    id: findInput
                    width: parent.width - 64
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 12 }
                    selectByMouse: true
                    onTextChanged: root.findQuery = text
                    Keys.onEscapePressed: { root.findOpen = false; root.findQuery = ""; input.forceActiveFocus() }
                    Text {
                        visible: findInput.text === ""
                        text: "Найти текст в текущем чате…"
                        color: Theme.faint
                        font: findInput.font
                    }
                }
                IconBtn {
                    width: 22; height: 22; radius: 11
                    icon: ""
                    tip: "Закрыть поиск (Esc)"
                    onClicked: { root.findOpen = false; root.findQuery = ""; input.forceActiveFocus() }
                }
            }
        }

        // ═══════════ 3. ТАЙМЛАЙН СООБЩЕНИЙ И ИНТЕРАКТИВНЫХ КАРТОЧЕК
        ListView {
            id: list
            anchors {
                top: root.findOpen ? findBar.bottom : limitsRow.bottom
                left: parent.left
                right: parent.right
                bottom: aboveComposerCol.top
                topMargin: 8
                bottomMargin: 8
            }
            clip: true
            spacing: 10
            model: Ai.log
            boundsBehavior: Flickable.StopAtBounds
            property bool follow: true
            onMovementEnded: follow = atYEnd
            onContentHeightChanged: if (follow) positionViewAtEnd()
            Connections { target: Ai.log; function onCountChanged() { list.follow = true; list.positionViewAtEnd() } }
            Connections { target: Ai; function onChatIdChanged() { list.follow = true; Qt.callLater(list.positionViewAtEnd) } }

            delegate: Item {
                id: msg
                required property int index
                required property string role
                required property string text
                required property bool error
                required property string kind
                required property bool done
                required property string tid
                required property string filesJson
                required property string output
                required property string metaJson

                property bool expanded: false

                readonly property bool mine: role === "user"
                readonly property bool isTool: role === "tool"
                readonly property bool isThinking: role === "thinking"
                readonly property bool isSubagent: role === "subagent"
                readonly property bool isPlan: role === "plan"
                readonly property bool isCheckpoint: role === "checkpoint"
                readonly property bool isAssistant: role === "assistant"

                readonly property var metaObj: {
                    if (!metaJson) return {}
                    try { return JSON.parse(metaJson) } catch (e) { return {} }
                }
                readonly property var attachedFiles: {
                    if (!filesJson) return []
                    try { return JSON.parse(filesJson) } catch (e) { return [] }
                }
                readonly property bool hasFiles: attachedFiles.length > 0
                readonly property bool waitingDots: isAssistant && text === "" && Ai.busy && index === Ai.log.count - 1
                readonly property bool matchesFind: root.findQuery === "" || (text || "").toLowerCase().indexOf(root.findQuery.toLowerCase()) >= 0 || (output || "").toLowerCase().indexOf(root.findQuery.toLowerCase()) >= 0

                opacity: matchesFind ? 1.0 : 0.25
                width: list.width
                height: isThinking ? thinkingCard.height
                      : isTool ? toolCard.height
                      : isSubagent ? subagentCard.height
                      : isPlan ? planCard.height
                      : isCheckpoint ? checkpointCard.height
                      : bubble.height

                // ── A. Карточка размышлений (Thinking / Reasoning)
                Rectangle {
                    id: thinkingCard
                    visible: msg.isThinking
                    width: Math.min(parent.width - 24, 620)
                    height: msg.expanded ? thinkCol.implicitHeight + 16 : 32
                    radius: 11
                    clip: true
                    color: Qt.rgba(0.55, 0.42, 0.95, 0.08)
                    border { width: 1; color: Qt.rgba(0.55, 0.42, 0.95, 0.24) }

                    Column {
                        id: thinkCol
                        x: 12; y: 7
                        width: parent.width - 24
                        spacing: 6

                        Row {
                            spacing: 8
                            Text {
                                text: !msg.done ? "" : "🧠"
                                color: "#a78bfa"
                                font { family: !msg.done ? Theme.iconFont : Theme.font; pixelSize: 12 }
                                RotationAnimator on rotation { running: !msg.done && msg.isThinking; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            Text {
                                text: !msg.done ? "Размышляет…" : ("Размышления · " + (msg.metaObj.elapsedSec || 1) + " с")
                                color: "#c4b5fd"
                                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Text {
                                text: msg.expanded ? "Свернуть " : "Показать ход мыслей "
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11 }
                            }
                        }

                        Text {
                            visible: msg.expanded
                            width: parent.width
                            text: msg.text
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 12 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: msg.expanded = !msg.expanded
                    }
                }

                // ── B. Раскрываемая карточка вызова инструмента (Tool Call Inspector)
                Rectangle {
                    id: toolCard
                    visible: msg.isTool
                    width: Math.min(parent.width - 24, 640)
                    height: toolInnerCol.implicitHeight + 16
                    radius: 12
                    color: msg.error ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                    border { width: 1; color: msg.expanded ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.08) }

                    Column {
                        id: toolInnerCol
                        x: 12; y: 8
                        width: parent.width - 24
                        spacing: 6

                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: !msg.done ? "" : msg.error ? "" : ""
                                color: msg.error ? Theme.danger : msg.done ? "#30d158" : Theme.primary
                                font { family: Theme.iconFont; pixelSize: 12 }
                                RotationAnimator on rotation { running: !msg.done && msg.isTool; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            Text {
                                width: parent.width - 46
                                text: msg.text
                                elide: msg.expanded ? Text.ElideNone : Text.ElideRight
                                maximumLineCount: msg.expanded ? 20 : 2
                                wrapMode: Text.Wrap
                                color: Theme.muted
                                font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 }
                            }
                            Text {
                                visible: msg.output !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: msg.expanded ? "" : ""
                                color: Theme.faint
                                font { family: Theme.iconFont; pixelSize: 10 }
                            }
                        }

                        Rectangle {
                            visible: msg.expanded && msg.output !== ""
                            width: parent.width
                            height: Math.min(220, toolOutText.implicitHeight + 16)
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.42)
                            border { width: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                            clip: true
                            Flickable {
                                anchors { fill: parent; margins: 8 }
                                contentWidth: width
                                contentHeight: toolOutText.implicitHeight
                                clip: true
                                Text {
                                    id: toolOutText
                                    width: parent.width
                                    text: msg.output
                                    wrapMode: Text.WrapAnywhere
                                    color: Theme.text
                                    font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 }
                                }
                            }
                            IconBtn {
                                anchors { right: parent.right; top: parent.top; margins: 4 }
                                width: 22; height: 22; radius: 11
                                icon: ""
                                tip: "Скопировать вывод инструмента"
                                onClicked: Quickshell.execDetached(["wl-copy", msg.output])
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: msg.output !== "" || msg.text.length > 80
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        z: -1
                        onClicked: msg.expanded = !msg.expanded
                    }
                }

                // ── C. Живая карточка субагента (Subagent Delegation Card)
                Rectangle {
                    id: subagentCard
                    visible: msg.isSubagent
                    readonly property color subColor: root.provColor(msg.kind || msg.metaObj.agent || "claude")
                    width: Math.min(parent.width - 16, 680)
                    height: subCol.implicitHeight + 20
                    radius: 14
                    color: Qt.rgba(subColor.r, subColor.g, subColor.b, 0.10)
                    border { width: 1; color: Qt.rgba(subColor.r, subColor.g, subColor.b, 0.42) }

                    Column {
                        id: subCol
                        x: 14; y: 10
                        width: parent.width - 28
                        spacing: 6

                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: !msg.done ? "" : msg.error ? "" : "🤖"
                                color: msg.error ? Theme.danger : subagentCard.subColor
                                font { family: !msg.done || msg.error ? Theme.iconFont : Theme.font; pixelSize: 13 }
                                RotationAnimator on rotation { running: !msg.done && msg.isSubagent; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (msg.metaObj.title || "Делегированная задача") + " · " + root.provName(msg.metaObj.agent || msg.kind)
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                            }
                            Rectangle {
                                visible: (msg.metaObj.mode || "") === "async"
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18; width: 64; radius: 5
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Text { anchors.centerIn: parent; text: "В ФОНЕ"; color: Theme.muted; font { family: Theme.font; pixelSize: 9; weight: Font.Bold } }
                            }
                            Rectangle {
                                visible: (msg.metaObj.worktreeBranch || "") !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18; width: wtSubTxt.implicitWidth + 10; radius: 5
                                color: Qt.rgba(0.06, 0.64, 0.5, 0.22)
                                Text {
                                    id: wtSubTxt
                                    anchors.centerIn: parent
                                    text: "⑂ " + (msg.metaObj.worktreeBranch || "")
                                    color: "#10a37f"
                                    font { family: "MedeoMono Nerd Font Mono"; pixelSize: 9 }
                                }
                            }
                            Chip {
                                visible: (msg.metaObj.childThreadId || "") !== ""
                                height: 22
                                label: "Открыть тред →"
                                tint: subagentCard.subColor
                                onClicked: Ai.openChat(msg.metaObj.childThreadId)
                            }
                        }

                        Text {
                            width: parent.width
                            text: msg.metaObj.prompt || msg.text
                            maximumLineCount: msg.expanded ? 12 : 2
                            elide: Text.ElideRight
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 12 }
                        }

                        Rectangle {
                            visible: msg.output !== ""
                            width: parent.width
                            height: subOutTxt.implicitHeight + 14
                            radius: 9
                            color: Qt.rgba(0, 0, 0, 0.32)
                            Text {
                                id: subOutTxt
                                x: 10; y: 7
                                width: parent.width - 20
                                text: msg.expanded ? msg.output : msg.output.slice(0, 360) + (msg.output.length > 360 ? "… (клик — развернуть)" : "")
                                wrapMode: Text.Wrap
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: msg.expanded = !msg.expanded }
                        }
                    }
                }

                // ── D. Карточка предложенного плана (Proposed Plan Card)
                Rectangle {
                    id: planCard
                    visible: msg.isPlan
                    width: Math.min(parent.width - 16, 700)
                    height: planCol.implicitHeight + 24
                    radius: 14
                    color: Qt.rgba(0.96, 0.62, 0.04, 0.10)
                    border { width: 1; color: Qt.rgba(0.96, 0.62, 0.04, 0.45) }

                    Column {
                        id: planCol
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 10

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { text: "📋"; font { pixelSize: 15 } }
                            Text {
                                width: parent.width - 260
                                elide: Text.ElideRight
                                text: msg.kind || msg.metaObj.title || "Предложенный план"
                                color: "#fbbf24"
                                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                            }
                            Chip {
                                height: 24
                                label: "Выполнить план ▶"
                                tint: "#30d158"
                                on: true
                                tip: "Переключить чат в режим выполнения кода и запустить реализацию этого плана"
                                onClicked: {
                                    Ai.activePlan = { title: msg.kind || "План", plan: msg.text, status: "proposed" }
                                    Ai.implementPlan(false, Ai.provider)
                                }
                            }
                            Chip {
                                height: 24
                                label: "В новом чате ⑂"
                                tint: "#f59e0b"
                                tip: "Создать чистый тред и реализовать план в нём"
                                onClicked: {
                                    Ai.activePlan = { title: msg.kind || "План", plan: msg.text, status: "proposed" }
                                    Ai.implementPlan(true, Ai.provider)
                                }
                            }
                            IconBtn {
                                width: 24; height: 24; radius: 12
                                icon: ""
                                tip: "Скопировать Markdown плана"
                                onClicked: Quickshell.execDetached(["wl-copy", msg.text])
                            }
                        }

                        Text {
                            width: parent.width
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            text: msg.text
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13 }
                        }
                    }
                }

                // ── E. Карточка git-чекпоинта и изменённых файлов за ход (ChangedFilesTree + Checkpoint)
                Rectangle {
                    id: checkpointCard
                    visible: msg.isCheckpoint
                    width: Math.min(parent.width - 16, 660)
                    height: cpCol.implicitHeight + 18
                    radius: 12
                    color: Qt.rgba(0.06, 0.64, 0.5, 0.09)
                    border { width: 1; color: Qt.rgba(0.06, 0.64, 0.5, 0.34) }

                    Column {
                        id: cpCol
                        x: 12; y: 9
                        width: parent.width - 24
                        spacing: 6

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "⑂"; color: "#10a37f"; font { pixelSize: 13; weight: Font.Bold } }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: msg.text
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                            }
                            Chip {
                                visible: (msg.metaObj.ref || "") !== "" && !msg.metaObj.restored
                                height: 22
                                label: "Показать diff"
                                tint: "#10a37f"
                                onClicked: Ai.viewTurnDiff(msg.metaObj.prevRef || "HEAD", msg.metaObj.ref || "", "", msg.text)
                            }
                            Chip {
                                visible: (msg.metaObj.prevRef || "") !== "" && !msg.metaObj.restored
                                height: 22
                                label: "Откатить ↩"
                                tint: Theme.danger
                                tip: "Откатить файлы рабочей папки к состоянию до этого хода"
                                onClicked: Ai.restoreCheckpoint(msg.metaObj.prevRef)
                            }
                        }

                        Flow {
                            visible: msg.hasFiles
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: msg.attachedFiles
                                Rectangle {
                                    id: cfChip
                                    required property var modelData
                                    height: 22
                                    width: cfRow.implicitWidth + 14
                                    radius: 6
                                    color: cfm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.3)
                                    Row {
                                        id: cfRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Text {
                                            text: cfChip.modelData.status || "M"
                                            color: cfChip.modelData.status === "A" ? "#30d158" : cfChip.modelData.status === "D" ? Theme.danger : "#fbbf24"
                                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 10; weight: Font.Bold }
                                        }
                                        Text {
                                            text: cfChip.modelData.path || ""
                                            color: Theme.text
                                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 10 }
                                        }
                                        Text {
                                            visible: (cfChip.modelData.additions || 0) > 0 || (cfChip.modelData.deletions || 0) > 0
                                            text: "+" + (cfChip.modelData.additions || 0) + " −" + (cfChip.modelData.deletions || 0)
                                            color: Theme.muted
                                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 9 }
                                        }
                                    }
                                    MouseArea {
                                        id: cfm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Ai.viewTurnDiff(msg.metaObj.prevRef || "HEAD", msg.metaObj.ref || "", cfChip.modelData.path, "Diff · " + cfChip.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── F. Пузырь сообщения пользователя или ответа помощника (с Rich Code Blocks)
                Rectangle {
                    id: bubble
                    visible: msg.mine || msg.isAssistant
                    anchors { right: msg.mine ? parent.right : undefined; left: msg.mine ? undefined : parent.left }
                    readonly property real maxBubbleW: Math.max(140, parent.width - 20)
                    readonly property var blocks: msg.isAssistant ? root.parseMessageBlocks(msg.text) : []
                    readonly property bool hasCodeBlocks: blocks.some(b => b.isCode)
                    width: msg.waitingDots ? 64
                         : hasCodeBlocks ? Math.min(maxBubbleW, 720)
                         : Math.max(76, Math.min(maxBubbleW, bubbleCol.implicitWidth + 28))
                    height: msg.waitingDots ? 38 : bubbleCol.implicitHeight + 20
                    radius: 14
                    color: msg.error ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.18)
                         : msg.mine ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Theme.weak

                    Column {
                        id: bubbleCol
                        visible: !msg.waitingDots
                        x: 14; y: 10
                        width: bubble.hasCodeBlocks ? (bubble.width - 28) : Math.min(bubble.maxBubbleW - 28, Math.max(userText.visible ? userText.implicitWidth : 0, assistantBlocksCol.visible ? assistantBlocksCol.implicitWidth : 0, msgFiles.visible ? msgFiles.implicitWidth : 0, msgChipsFlow.visible ? msgChipsFlow.implicitWidth : 0, metaFooterRow.visible ? metaFooterRow.implicitWidth : 0))
                        spacing: 8

                        // Бейджи контекстных чипов и режима отправки на сообщении пользователя
                        Flow {
                            id: msgChipsFlow
                            visible: msg.mine && ((msg.metaObj.chips && msg.metaObj.chips.length > 0) || (msg.kind !== ""))
                            width: Math.min(bubble.maxBubbleW - 28, implicitWidth)
                            spacing: 4
                            Rectangle {
                                visible: msg.kind === "steered" || msg.kind === "queued"
                                height: 18; width: kindBadgeTxt.implicitWidth + 10; radius: 5
                                color: msg.kind === "steered" ? Qt.rgba(0.96, 0.62, 0.04, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                                Text {
                                    id: kindBadgeTxt
                                    anchors.centerIn: parent
                                    text: msg.kind === "steered" ? "↪ Перенаправлено" : "Из очереди"
                                    color: msg.kind === "steered" ? "#fbbf24" : Theme.muted
                                    font { family: Theme.font; pixelSize: 9; weight: Font.DemiBold }
                                }
                            }
                            Repeater {
                                model: msg.metaObj.chips ?? []
                                Rectangle {
                                    required property var modelData
                                    height: 18; width: mchTxt.implicitWidth + 10; radius: 5
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    Text {
                                        id: mchTxt
                                        anchors.centerIn: parent
                                        text: (modelData.kind === "skill" ? "" : "@") + (modelData.label || "")
                                        color: Theme.primary
                                        font { family: "MedeoMono Nerd Font Mono"; pixelSize: 9 }
                                    }
                                }
                            }
                        }

                        // Прикреплённые изображения и файлы
                        Flow {
                            id: msgFiles
                            visible: msg.hasFiles
                            width: Math.min(bubble.maxBubbleW - 28, implicitWidth)
                            spacing: 6
                            Repeater {
                                model: msg.attachedFiles
                                Rectangle {
                                    id: mf
                                    required property var modelData
                                    readonly property bool isImg: !!modelData.isImage
                                    width: isImg ? 148 : Math.min(220, mfRow.implicitWidth + 18)
                                    height: isImg ? 104 : 32
                                    radius: 10
                                    clip: true
                                    color: Qt.rgba(0, 0, 0, 0.32)
                                    border { width: 1; color: mfm.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.14) }
                                    Image {
                                        visible: mf.isImg
                                        anchors { fill: parent; margins: 2 }
                                        source: mf.isImg ? "file://" + mf.modelData.path : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                    }
                                    Row {
                                        id: mfRow
                                        visible: !mf.isImg
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "\uf15b"; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 12 } }
                                        Text {
                                            text: (mf.modelData.name || "Файл") + (mf.modelData.sizeLabel ? " (" + mf.modelData.sizeLabel + ")" : "")
                                            color: Theme.text
                                            font { family: Theme.font; pixelSize: 12 }
                                        }
                                    }
                                    MouseArea {
                                        id: mfm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (mf.isImg) {
                                                root.previewPath = mf.modelData.path
                                                root.previewTitle = (mf.modelData.name || "Изображение") + (mf.modelData.sizeLabel ? " · " + mf.modelData.sizeLabel : "")
                                            } else {
                                                Quickshell.execDetached(["xdg-open", mf.modelData.path])
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Текст сообщения пользователя
                        Text {
                            id: userText
                            visible: msg.mine && (msg.text !== "" || !msg.hasFiles)
                            width: Math.min(bubble.maxBubbleW - 28, implicitWidth)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: msg.text
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 14 }
                        }

                        // Структурированные блоки ответа помощника (Markdown + Rich Code Blocks)
                        Column {
                            id: assistantBlocksCol
                            visible: msg.isAssistant
                            width: bubble.hasCodeBlocks ? (bubble.width - 28) : Math.min(bubble.maxBubbleW - 28, implicitWidth)
                            spacing: 8

                            Repeater {
                                model: bubble.blocks
                                Item {
                                    id: blkItem
                                    required property var modelData
                                    readonly property bool isCode: !!modelData.isCode
                                    property bool wrapLines: true
                                    width: isCode ? (bubble.width - 28) : Math.min(bubble.maxBubbleW - 28, proseTxt.implicitWidth)
                                    height: isCode ? codeBox.height : proseTxt.implicitHeight

                                    Text {
                                        id: proseTxt
                                        visible: !blkItem.isCode
                                        width: Math.min(bubble.maxBubbleW - 28, implicitWidth)
                                        textFormat: Text.MarkdownText
                                        wrapMode: Text.Wrap
                                        text: blkItem.modelData.text || "…"
                                        color: msg.error ? Theme.danger : Theme.text
                                        linkColor: Theme.primary
                                        font { family: Theme.font; pixelSize: 14 }
                                        onLinkActivated: link => Qt.openUrlExternally(link)
                                    }

                                    Rectangle {
                                        id: codeBox
                                        visible: blkItem.isCode
                                        width: parent.width
                                        height: codeHead.height + codeBodyTxt.implicitHeight + 18
                                        radius: 10
                                        color: Qt.rgba(0.03, 0.03, 0.05, 0.78)
                                        border { width: 1; color: Qt.rgba(1, 1, 1, 0.10) }

                                        Rectangle {
                                            id: codeHead
                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                            height: 26
                                            radius: 10
                                            color: Qt.rgba(1, 1, 1, 0.05)
                                            Text {
                                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                                text: blkItem.modelData.lang || "code"
                                                color: Theme.muted
                                                font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11; weight: Font.DemiBold }
                                            }
                                            Row {
                                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                                spacing: 4
                                                Chip {
                                                    visible: ["sh", "bash", "zsh", "shell"].indexOf((blkItem.modelData.lang || "").toLowerCase()) >= 0
                                                    height: 20
                                                    label: "▶ В терминал"
                                                    tint: "#30d158"
                                                    tip: "Выполнить команду в новом окне терминала (kitty)"
                                                    onClicked: Quickshell.execDetached(["kitty", "--working-directory", Ai.cwd, "sh", "-c", blkItem.modelData.text + "; exec $SHELL"])
                                                }
                                                Chip {
                                                    height: 20
                                                    label: "Скопировать"
                                                    onClicked: Quickshell.execDetached(["wl-copy", blkItem.modelData.text])
                                                }
                                            }
                                        }

                                        Text {
                                            id: codeBodyTxt
                                            anchors { left: parent.left; right: parent.right; top: codeHead.bottom; margins: 10; topMargin: 8 }
                                            text: blkItem.modelData.text
                                            wrapMode: blkItem.wrapLines ? Text.WrapAnywhere : Text.NoWrap
                                            color: "#e2e8f0"
                                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 12 }
                                        }
                                    }
                                }
                            }
                        }

                        // Нижняя строка метаданных ответа (какой провайдер/модель ответил и за сколько секунд)
                        Row {
                            id: metaFooterRow
                            visible: msg.isAssistant && (msg.metaObj.provider !== undefined || msg.metaObj.elapsedSec !== undefined)
                            spacing: 6
                            Rectangle {
                                visible: (msg.metaObj.provider || "") !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6; radius: 3
                                color: root.provColor(msg.metaObj.provider || Ai.provider)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.provName(msg.metaObj.provider || Ai.provider)
                                    + (msg.metaObj.model ? " · " + msg.metaObj.model : "")
                                    + (msg.metaObj.elapsedSec ? " · " + msg.metaObj.elapsedSec + " с" : "")
                                    + (msg.metaObj.steps ? " · " + msg.metaObj.steps + " шаг." : "")
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 10 }
                            }
                        }
                    }

                    // Точки ожидания
                    Row {
                        visible: msg.waitingDots
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 5
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 7; height: 7; radius: 3.5
                                color: Theme.muted
                                SequentialAnimation on opacity {
                                    running: Ai.busy
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 160 }
                                    NumberAnimation { to: 0.25; duration: 360 }
                                    NumberAnimation { to: 1; duration: 360 }
                                    PauseAnimation { duration: (2 - index) * 160 }
                                }
                            }
                        }
                    }

                    // Панель действий при наведении (Откатить и править, Цитировать, Ответвить, Перегенерировать, Копировать)
                    Row {
                        visible: msg.text !== "" && (bm.containsMouse || actHover.hovered)
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        spacing: 3
                        HoverHandler { id: actHover }

                        // Для сообщения пользователя: Откатить чат к этому сообщению и отредактировать
                        IconBtn {
                            visible: msg.mine && !Ai.busy
                            width: 24; height: 24; radius: 12
                            icon: ""
                            tip: "Откатить диалог к этому месту и изменить вопрос (Edit from here)"
                            onClicked: {
                                input.text = Ai.revertAndEditFrom(msg.index, false)
                                input.cursorPosition = input.text.length
                                input.forceActiveFocus()
                            }
                        }
                        // Для ответа помощника: Цитировать в контекстный чип
                        IconBtn {
                            visible: msg.isAssistant
                            width: 24; height: 24; radius: 12
                            icon: ""
                            tip: "Процитировать ответ в следующее сообщение (❝ Цитата)"
                            onClicked: {
                                Ai.quoteText(msg.text.slice(0, 600), root.provName(msg.metaObj.provider || Ai.provider))
                                input.forceActiveFocus()
                            }
                        }
                        // Ответвить чат (Fork) от этого сообщения
                        IconBtn {
                            visible: msg.isAssistant && !Ai.busy
                            width: 24; height: 24; radius: 12
                            icon: "⑂"
                            tip: "Ответвить новый чат от этого сообщения (Fork)"
                            onClicked: Ai.forkChat(Ai.chatId, msg.index, "")
                        }
                        // Перегенерировать последний ответ
                        IconBtn {
                            visible: msg.isAssistant && !Ai.busy && msg.index === Ai.log.count - 1
                            width: 24; height: 24; radius: 12
                            icon: ""
                            tip: "Перегенерировать ответ"
                            onClicked: Ai.regenerateLast()
                        }
                        // Скопировать
                        IconBtn {
                            width: 24; height: 24; radius: 12
                            icon: ""
                            tip: "Скопировать текст сообщения"
                            onClicked: Quickshell.execDetached(["wl-copy", msg.text])
                        }
                    }
                    MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }

            // Пустое состояние чата
            Column {
                visible: Ai.log.count === 0
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 14
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\u{f0674}"; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 36 } }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Ai.interactionMode === "plan"
                        ? "Режим планирования (План): агент изучит проект, задаст вопросы и составит карточку плана без правки кода."
                        : "Переключайте Claude, Codex и Antigravity прямо по ходу диалога · Используйте @ для файлов/тредов, $ для скиллов и / для команд."
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 13 }
                }
                Flow {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 600)
                    spacing: 6
                    Repeater {
                        model: root.suggestions
                        Rectangle {
                            id: sg
                            required property string modelData
                            height: 30; width: sl.implicitWidth + 22; radius: 15
                            color: sm.containsMouse ? Theme.strong : Theme.weak
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            Text { id: sl; anchors.centerIn: parent; text: sg.modelData; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
                            MouseArea {
                                id: sm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Ai.send(sg.modelData)
                            }
                        }
                    }
                }
            }
        }

        // ═══════════ 4. СТЕК НАД КОМПОЗЕРОМ (ПЛАН, ВОПРОСЫ ASK_USER_QUESTION, РАЗРЕШЕНИЯ, ОЧЕРЕДЬ)
        Column {
            id: aboveComposerCol
            anchors { left: parent.left; right: parent.right; bottom: composer.top; bottomMargin: 6 }
            spacing: 6

            // 4.1 Баннер готового плана (Plan Follow-Up Banner)
            Rectangle {
                visible: Ai.activePlan !== null && Ai.activePlan.status === "proposed" && !Ai.busy
                width: parent.width
                height: visible ? 38 : 0
                radius: 12
                color: Qt.rgba(0.96, 0.62, 0.04, 0.14)
                border { width: 1; color: Qt.rgba(0.96, 0.62, 0.04, 0.45) }
                Row {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                    spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "📋 План готов: " + (Ai.activePlan?.title || "Реализация"); color: "#fbbf24"; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                    Chip { height: 24; label: "Выполнить ▶"; tint: "#30d158"; on: true; onClicked: Ai.implementPlan(false, Ai.provider) }
                    Chip { height: 24; label: "В новом треде ⑂"; tint: "#f59e0b"; onClicked: Ai.implementPlan(true, Ai.provider) }
                    Chip {
                        height: 24
                        label: "Передать в Codex →"
                        visible: Ai.provider !== "codex"
                        tint: root.provColor("codex")
                        onClicked: Ai.implementPlan(false, "codex")
                    }
                    Chip {
                        height: 24
                        label: "Передать в Claude →"
                        visible: Ai.provider !== "claude"
                        tint: root.provColor("claude")
                        onClicked: Ai.implementPlan(false, "claude")
                    }
                    IconBtn { width: 22; height: 22; radius: 11; icon: ""; tip: "Скрыть баннер плана"; onClicked: Ai.dismissPlan() }
                }
            }

            // 4.2 Интерактивная карточка вопросов от агента (AskUserQuestion)
            Rectangle {
                id: questionPanel
                visible: Ai.pendingQuestion !== null
                property int qIdx: 0
                property var selectedAnswers: ({})
                readonly property var qList: Ai.pendingQuestion?.questions ?? []
                readonly property var curQ: qList[qIdx] ?? null
                width: parent.width
                height: visible ? qPanelCol.implicitHeight + 20 : 0
                radius: 14
                color: Qt.rgba(0.22, 0.52, 0.96, 0.14)
                border { width: 1; color: Qt.rgba(0.22, 0.52, 0.96, 0.55) }

                Connections {
                    target: Ai
                    function onPendingQuestionChanged() {
                        questionPanel.qIdx = 0
                        questionPanel.selectedAnswers = {}
                        customAnswerInput.text = ""
                    }
                }

                Column {
                    id: qPanelCol
                    x: 12; y: 10
                    width: parent.width - 24
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "❓ " + (questionPanel.curQ?.header || "Уточняющий вопрос") + (questionPanel.qList.length > 1 ? " (" + (questionPanel.qIdx + 1) + "/" + questionPanel.qList.length + ")" : "")
                            color: "#60a5fa"
                            font { family: Theme.font; pixelSize: 12; weight: Font.Bold }
                        }
                        Text {
                            text: questionPanel.curQ?.question || ""
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: questionPanel.curQ?.options ?? []
                            Chip {
                                required property int index
                                required property var modelData
                                readonly property string optLabel: typeof modelData === "string" ? modelData : (modelData.label || "")
                                readonly property string qKey: questionPanel.curQ?.id || ("q_" + questionPanel.qIdx)
                                label: (index + 1) + ". " + optLabel
                                tip: typeof modelData === "object" ? (modelData.description || "") : ""
                                on: questionPanel.selectedAnswers[qKey] === optLabel
                                onClicked: {
                                    const next = Object.assign({}, questionPanel.selectedAnswers)
                                    next[qKey] = optLabel
                                    questionPanel.selectedAnswers = next
                                    if (questionPanel.qIdx + 1 < questionPanel.qList.length) {
                                        questionPanel.qIdx++
                                    } else {
                                        Ai.answerQuestion(next)
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 6
                        Rectangle {
                            width: parent.width - 170
                            height: 26; radius: 8
                            color: Qt.rgba(0, 0, 0, 0.35)
                            border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
                            TextInput {
                                id: customAnswerInput
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12 }
                                onAccepted: {
                                    const qKey = questionPanel.curQ?.id || ("q_" + questionPanel.qIdx)
                                    const next = Object.assign({}, questionPanel.selectedAnswers)
                                    next[qKey] = text.trim()
                                    Ai.answerQuestion(next)
                                }
                                Text {
                                    visible: customAnswerInput.text === ""
                                    text: "Или введите свой вариант ответа…"
                                    color: Theme.faint
                                    font: customAnswerInput.font
                                }
                            }
                        }
                        Chip {
                            height: 26
                            label: "Ответить ✔"
                            tint: "#30d158"
                            on: true
                            onClicked: {
                                const qKey = questionPanel.curQ?.id || ("q_" + questionPanel.qIdx)
                                const next = Object.assign({}, questionPanel.selectedAnswers)
                                if (customAnswerInput.text.trim() !== "") next[qKey] = customAnswerInput.text.trim()
                                Ai.answerQuestion(next)
                            }
                        }
                        Chip {
                            height: 26
                            label: "Пропустить"
                            tint: Theme.danger
                            onClicked: Ai.cancelQuestion()
                        }
                    }
                }
            }

            // 4.3 Карточки подтверждения разрешений (Tool Approvals)
            Repeater {
                model: Ai.approvals
                Rectangle {
                    id: ap
                    required property string rid
                    required property string title
                    required property string detail
                    width: parent.width
                    height: apc.implicitHeight + 20
                    radius: 14
                    color: Qt.rgba(1, 0.75, 0.2, 0.12)
                    border { width: 1; color: Qt.rgba(1, 0.75, 0.2, 0.45) }
                    Column {
                        id: apc
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 6
                        Text { text: "🛡 Нужно разрешение: " + ap.title; color: Theme.text; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                        Text {
                            visible: ap.detail !== ""
                            width: parent.width
                            text: ap.detail
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            color: Theme.muted
                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 }
                        }
                        Row {
                            spacing: 6
                            Chip { label: "Разрешить"; tint: "#30d158"; on: true; onClicked: Ai.resolveApproval(ap.rid, "allow", false) }
                            Chip { label: "Всегда в сессии"; onClicked: Ai.resolveApproval(ap.rid, "allow", true) }
                            Chip { label: "Отклонить"; tint: Theme.danger; onClicked: Ai.resolveApproval(ap.rid, "deny", false) }
                        }
                    }
                }
            }

            // 4.4 Панель управления очередью сообщений (QueuedRunsControl)
            Rectangle {
                visible: Ai.queuedMessages.count > 0
                width: parent.width
                height: visible ? queueCol.implicitHeight + 16 : 0
                radius: 13
                color: Qt.rgba(1, 1, 1, 0.05)
                border { width: 1; color: Ai.queueHeld ? Qt.rgba(0.96, 0.62, 0.04, 0.45) : Qt.rgba(1, 1, 1, 0.12) }

                Column {
                    id: queueCol
                    x: 10; y: 8
                    width: parent.width - 20
                    spacing: 5

                    Row {
                        width: parent.width
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (Ai.queueHeld ? "⏸ Очередь на паузе (" : "⏳ В очереди (") + Ai.queuedMessages.count + ")"
                            color: Ai.queueHeld ? "#fbbf24" : Theme.muted
                            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                        }
                        Chip {
                            visible: Ai.queueHeld && !Ai.busy
                            height: 20
                            label: "Продолжить очередь ▶"
                            tint: "#30d158"
                            on: true
                            onClicked: Ai.resumeQueue()
                        }
                    }

                    Repeater {
                        model: Ai.queuedMessages
                        Rectangle {
                            id: qItem
                            required property int index
                            required property string text
                            width: queueCol.width
                            height: 28
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.32)
                            Text {
                                anchors { left: parent.left; leftMargin: 8; right: qBtns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: (qItem.index + 1) + ". " + qItem.text
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            Row {
                                id: qBtns
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Chip {
                                    height: 20
                                    label: "↪ Сейчас"
                                    tint: "#f59e0b"
                                    tip: "Прервать текущий ход и сразу направить это сообщение (Steer)"
                                    onClicked: Ai.promoteQueuedToSteer(qItem.index)
                                }
                                IconBtn {
                                    width: 20; height: 20; radius: 10
                                    icon: ""
                                    tip: "Вернуть в поле ввода для редактирования"
                                    onClicked: {
                                        input.text = Ai.popQueued(qItem.index)
                                        input.cursorPosition = input.text.length
                                        input.forceActiveFocus()
                                    }
                                }
                                IconBtn {
                                    visible: qItem.index > 0
                                    width: 20; height: 20; radius: 10
                                    icon: ""
                                    tip: "Поднять выше в очереди"
                                    onClicked: Ai.moveQueued(qItem.index, -1)
                                }
                                IconBtn {
                                    visible: qItem.index + 1 < Ai.queuedMessages.count
                                    width: 20; height: 20; radius: 10
                                    icon: ""
                                    tip: "Опустить ниже в очереди"
                                    onClicked: Ai.moveQueued(qItem.index, 1)
                                }
                                IconBtn {
                                    width: 20; height: 20; radius: 10
                                    icon: ""
                                    tint: Theme.danger
                                    tip: "Удалить из очереди"
                                    onClicked: Ai.removeQueued(qItem.index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ═══════════ 5. КОМПОЗЕР (КОНТЕКСТНЫЕ ЧИПЫ + ВЛОЖЕНИЯ + РЕДАКТОР + НИЖНЯЯ ПАНЕЛЬ)
        Rectangle {
            id: composer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            readonly property bool hasChips: Ai.contextChips.count > 0
            readonly property bool hasAtt: Ai.attachments.count > 0
            readonly property real chipsH: hasChips ? 32 : 0
            readonly property real attH: hasAtt ? 70 : 0
            readonly property real editorH: Math.min(168, Math.max(24, input.contentHeight))
            readonly property real barH: 36
            height: chipsH + attH + editorH + barH + 18
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.36)
            border {
                width: 1
                color: dropArea.containsDrag ? Theme.primary
                     : Ai.interactionMode === "plan" ? Qt.rgba(0.96, 0.62, 0.04, 0.55)
                     : input.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.65)
                     : composerHover.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)
            }
            Behavior on border.color { ColorAnimation { duration: Theme.dFast } }
            HoverHandler { id: composerHover }
            MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

            // 5.1 Полоса контекстных чипов (@файл, @тред, $скилл, ❝ цитата)
            Item {
                id: chipsBox
                visible: composer.hasChips
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 10; topMargin: 7 }
                height: composer.hasChips ? 26 : 0

                ListView {
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 6
                    clip: true
                    model: Ai.contextChips
                    delegate: Rectangle {
                        id: cchip
                        required property int index
                        required property string kind
                        required property string label
                        required property string detail
                        height: 24
                        width: cchipRow.implicitWidth + 16
                        radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border { width: 1; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.42) }
                        Row {
                            id: cchipRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: cchip.kind === "thread" ? "💬" : cchip.kind === "skill" ? "⚡" : cchip.kind === "quote" ? "❝" : "📄"
                                font { pixelSize: 10 }
                            }
                            Text {
                                text: cchip.label
                                color: Theme.text
                                font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11; weight: Font.Medium }
                            }
                            Text {
                                text: ""
                                color: Theme.muted
                                font { family: Theme.iconFont; pixelSize: 9 }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Ai.removeContextChip(cchip.index)
                                }
                            }
                        }
                    }
                }
            }

            // 5.2 Лента прикреплённых изображений и файлов
            Item {
                id: attBox
                visible: composer.hasAtt
                anchors {
                    left: parent.left; right: parent.right
                    top: composer.hasChips ? chipsBox.bottom : parent.top
                    leftMargin: 10; rightMargin: 10
                    topMargin: composer.hasChips ? 4 : 8
                }
                height: composer.hasAtt ? 62 : 0

                ListView {
                    id: attList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Ai.attachments
                    delegate: Rectangle {
                        id: attCard
                        required property int index
                        required property string path
                        required property string name
                        required property bool isImage
                        required property string sizeLabel
                        width: isImage ? 168 : 164
                        height: 58
                        radius: 12
                        color: attCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
                        border { width: 1; color: attCardMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5) : Qt.rgba(1, 1, 1, 0.12) }

                        Rectangle {
                            id: thumbBox
                            x: 5; y: 5
                            width: 48; height: 48; radius: 8
                            clip: true
                            color: Qt.rgba(0, 0, 0, 0.35)
                            Image {
                                visible: attCard.isImage
                                anchors.fill: parent
                                source: attCard.isImage ? "file://" + attCard.path : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }
                            Text {
                                visible: !attCard.isImage
                                anchors.centerIn: parent
                                text: "\uf15b"
                                color: Theme.primary
                                font { family: Theme.iconFont; pixelSize: 18 }
                            }
                        }

                        Column {
                            anchors { left: thumbBox.right; leftMargin: 8; right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideMiddle; text: attCard.name; color: Theme.text; font { family: Theme.font; pixelSize: 11; weight: Font.Medium } }
                            Text { width: parent.width; elide: Text.ElideRight; text: (attCard.isImage ? "Картинка" : "Файл") + (attCard.sizeLabel ? " · " + attCard.sizeLabel : ""); color: Theme.faint; font { family: Theme.font; pixelSize: 10 } }
                        }

                        MouseArea {
                            id: attCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (attCard.isImage) {
                                    root.previewPath = attCard.path
                                    root.previewTitle = attCard.name + (attCard.sizeLabel ? " · " + attCard.sizeLabel : "")
                                } else {
                                    Quickshell.execDetached(["xdg-open", attCard.path])
                                }
                            }
                        }

                        Rectangle {
                            anchors { right: parent.right; top: parent.top; margins: 4 }
                            width: 18; height: 18; radius: 9
                            color: rmMouse.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.55)
                            Text { anchors.centerIn: parent; text: ""; color: rmMouse.containsMouse ? Theme.base : Theme.text; font { family: Theme.iconFont; pixelSize: 8 } }
                            MouseArea {
                                id: rmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { Ai.removeAttachment(attCard.index); input.forceActiveFocus() }
                            }
                        }
                    }
                }
            }

            // 5.3 Многострочное поле ввода
            Flickable {
                id: flick
                anchors {
                    left: parent.left; right: parent.right
                    top: composer.hasAtt ? attBox.bottom : composer.hasChips ? chipsBox.bottom : parent.top
                    leftMargin: 14; rightMargin: 14
                    topMargin: (composer.hasAtt || composer.hasChips) ? 6 : 10
                }
                height: composer.editorH
                contentWidth: width
                contentHeight: input.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                TextEdit {
                    id: input
                    width: flick.width - (scrollBar.visible ? 8 : 0)
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    selectedTextColor: Theme.text
                    font { family: Theme.font; pixelSize: 14 }
                    selectByMouse: true
                    onTextChanged: {
                        root.slashIdx = 0
                        root.slashDismissed = false
                    }

                    Keys.onPressed: e => {
                        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0
                        const shift = (e.modifiers & Qt.ShiftModifier) !== 0

                        // Shift+Tab — мгновенное переключение Код / План (как в T3 Code!)
                        if (e.key === Qt.Key_Backtab || (e.key === Qt.Key_Tab && shift)) {
                            Ai.toggleInteractionMode()
                            e.accepted = true
                            return
                        }

                        // Ctrl+S — отложить черновик в Stash
                        if (ctrl && e.key === Qt.Key_S) {
                            if (Ai.stashDraft(input.text)) input.text = ""
                            e.accepted = true
                            return
                        }

                        // Ctrl+F — поиск по текущему треду
                        if (ctrl && e.key === Qt.Key_F) {
                            root.findOpen = !root.findOpen
                            if (root.findOpen) Qt.callLater(() => findInput.forceActiveFocus())
                            e.accepted = true
                            return
                        }

                        // Навигация в меню @-упоминаний и $-скиллов
                        if (root.mentionOpen && !ctrl && !shift) {
                            if (e.key === Qt.Key_Up) {
                                root.mentionIdx = (root.mentionIdx - 1 + root.mentionMatches.length) % root.mentionMatches.length
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Down) {
                                root.mentionIdx = (root.mentionIdx + 1) % root.mentionMatches.length
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Tab || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.applyMention(root.mentionMatches[root.mentionIdx])
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Escape) {
                                root.lastAtQuery = ""
                                e.accepted = true; return
                            }
                        }

                        // Навигация в меню /-команд
                        if (root.slashOpen && !ctrl && !shift) {
                            if (e.key === Qt.Key_Up) {
                                root.slashIdx = (root.slashIdx - 1 + root.slashMatches.length) % root.slashMatches.length
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Down) {
                                root.slashIdx = (root.slashIdx + 1) % root.slashMatches.length
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Tab) {
                                root.applySlash(root.slashMatches[root.slashIdx], false)
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                root.applySlash(root.slashMatches[root.slashIdx], true)
                                e.accepted = true; return
                            }
                            if (e.key === Qt.Key_Escape) {
                                root.slashDismissed = true
                                e.accepted = true; return
                            }
                        }

                        // Ctrl+V / Shift+Insert — умная вставка (картинка, большой текст в файл или обычный текст)
                        if ((ctrl && e.key === Qt.Key_V) || (shift && e.key === Qt.Key_Insert)) {
                            root.pasteClipboard()
                            e.accepted = true
                            return
                        }
                        // Enter без Shift/Ctrl — отправить (или поставить в очередь, если занят)
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !shift && !ctrl) {
                            root.submit()
                            e.accepted = true
                            return
                        }
                        // Ctrl+Enter — живое перенаправление активного хода (Steer) или отправка
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ctrl) {
                            if (Ai.busy) root.submitSteer()
                            else root.submit()
                            e.accepted = true
                            return
                        }
                        // Esc — закрыть попапы / остановить генерацию
                        if (e.key === Qt.Key_Escape) {
                            if (Ai.diffOpen) { Ai.closeDiff(); e.accepted = true; return }
                            if (root.previewPath !== "") { root.previewPath = ""; e.accepted = true; return }
                            if (root.gitPopupOpen || root.stashPopupOpen) { root.gitPopupOpen = false; root.stashPopupOpen = false; e.accepted = true; return }
                            if (Ai.busy) { Ai.stop(); e.accepted = true; return }
                        }
                        // Backspace в пустом поле удаляет последний чип или вложение
                        if (e.key === Qt.Key_Backspace && input.text === "") {
                            if (Ai.contextChips.count > 0) {
                                Ai.removeContextChip(Ai.contextChips.count - 1)
                                e.accepted = true; return
                            }
                            if (Ai.attachments.count > 0) {
                                Ai.removeAttachment(Ai.attachments.count - 1)
                                e.accepted = true; return
                            }
                        }
                        // История отправленных запросов (↑ / ↓)
                        if (e.key === Qt.Key_Up && !shift && !ctrl && Ai.promptHistory.length > 0) {
                            const beforeCursor = input.text.slice(0, input.cursorPosition)
                            if (beforeCursor.indexOf("\n") === -1) {
                                if (root.histIdx === -1) {
                                    root.histDraft = input.text
                                    root.histIdx = Ai.promptHistory.length - 1
                                } else if (root.histIdx > 0) {
                                    root.histIdx--
                                }
                                input.text = Ai.promptHistory[root.histIdx]
                                input.cursorPosition = input.text.length
                                e.accepted = true
                                return
                            }
                        }
                        if (e.key === Qt.Key_Down && !shift && !ctrl && root.histIdx >= 0) {
                            const afterCursor = input.text.slice(input.cursorPosition)
                            if (afterCursor.indexOf("\n") === -1) {
                                if (root.histIdx < Ai.promptHistory.length - 1) {
                                    root.histIdx++
                                    input.text = Ai.promptHistory[root.histIdx]
                                } else {
                                    root.histIdx = -1
                                    input.text = root.histDraft
                                }
                                input.cursorPosition = input.text.length
                                e.accepted = true
                                return
                            }
                        }
                    }

                    onCursorRectangleChanged: {
                        if (cursorRectangle.y < flick.contentY)
                            flick.contentY = cursorRectangle.y
                        else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                            flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height
                    }

                    Text {
                        visible: input.text === "" && !input.preeditText
                        width: parent.width
                        elide: Text.ElideRight
                        text: Ai.busy
                            ? "Агент работает… (Enter — в очередь, Ctrl+Enter — перенаправить ↪, Esc — стоп)"
                            : Ai.interactionMode === "plan"
                            ? "Опишите задачу для плана (" + root.provName(Ai.provider) + ")… (@ файл/тред, $ скилл, Shift+Tab — режим Код)"
                            : "Спросить " + root.provName(Ai.provider) + "… (/ команды, @ файл/тред, $ скилл, Ctrl+V — картинка)"
                        color: Theme.faint
                        font: input.font
                    }
                }

                Rectangle {
                    id: scrollBar
                    visible: flick.contentHeight > flick.height + 2
                    x: flick.width - 3
                    y: flick.height * (flick.contentY / Math.max(1, flick.contentHeight))
                    width: 3
                    height: Math.max(14, flick.height * (flick.height / Math.max(1, flick.contentHeight)))
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.28)
                }
            }

            // 5.4 Нижняя панель инструментов внутри композера
            Item {
                id: composerBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 8; bottomMargin: 6 }
                height: composer.barH

                Row {
                    id: leftTools
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 3

                    // Переключатель режима Код / План (Shift+Tab)
                    Chip {
                        height: 26
                        label: Ai.interactionMode === "plan" ? "📋 План" : "⚡ Код"
                        tint: Ai.interactionMode === "plan" ? "#f59e0b" : Theme.primary
                        on: Ai.interactionMode === "plan"
                        tip: "Переключить режим взаимодействия: Код (выполнение) / План (только планирование и вопросы, Shift+Tab)"
                        onClicked: Ai.toggleInteractionMode()
                    }

                    // Переключатель режима разрешений (С подтверждением / Авто-правки / Полный доступ)
                    Chip {
                        height: 26
                        label: Ai.permissionMode === "full-access" ? "🔓 Полный" : Ai.permissionMode === "auto-edit" ? "✎ Авто-правки" : "🛡 Спрос"
                        tint: Ai.permissionMode === "full-access" ? Theme.danger : Ai.permissionMode === "auto-edit" ? "#30d158" : Theme.muted
                        on: Ai.permissionMode !== "supervised"
                        tip: "Режим разрешений: С подтверждением → Авто-правки в рабочей папке → Полный доступ без вопросов"
                        onClicked: Ai.cyclePermissionMode()
                    }

                    IconBtn {
                        icon: "/"
                        on: root.slashOpen
                        tip: "Слэш-команды (/plan, /learn, /compact, /fork, /worktree, /demo…)"
                        onClicked: {
                            if (input.text === "/") input.text = ""
                            else { input.text = "/"; input.cursorPosition = 1 }
                            input.forceActiveFocus()
                        }
                    }
                    IconBtn {
                        icon: "@"
                        on: root.tokenTrigger.kind === "at"
                        tip: "Упомянуть файл, папку или другой тред (@)"
                        onClicked: {
                            const prefix = (input.text !== "" && !input.text.endsWith(" ")) ? " @" : "@"
                            input.insert(input.cursorPosition, prefix)
                            input.forceActiveFocus()
                        }
                    }
                    IconBtn {
                        icon: "$"
                        on: root.tokenTrigger.kind === "skill"
                        tip: "Прикрепить скилл агента ($)"
                        onClicked: {
                            const prefix = (input.text !== "" && !input.text.endsWith(" ")) ? " $" : "$"
                            input.insert(input.cursorPosition, prefix)
                            input.forceActiveFocus()
                        }
                    }
                    IconBtn {
                        icon: "\uf0c6"
                        tip: "Прикрепить изображение или файл с диска"
                        onClicked: root.pickFiles()
                    }
                    IconBtn {
                        icon: ""
                        tip: "Вставить картинку, большой лог или текст из буфера обмена (Ctrl+V)"
                        on: clipProc.running
                        onClicked: root.pasteClipboard()
                    }
                    IconBtn {
                        icon: "\uf030"
                        tip: "Выделить область экрана и прикрепить снимок"
                        onClicked: root.takeScreenshot("region")
                    }
                    IconBtn {
                        icon: ""
                        on: root.stashPopupOpen || Ai.stashList.length > 0
                        tip: "Карман черновиков (Stash · Ctrl+S — сохранить текущий текст, клик — список черновиков: " + Ai.stashList.length + ")"
                        onClicked: {
                            if (input.text.trim() !== "" && !root.stashPopupOpen) {
                                if (Ai.stashDraft(input.text)) input.text = ""
                            } else {
                                root.stashPopupOpen = !root.stashPopupOpen
                            }
                        }
                    }
                    IconBtn {
                        visible: input.text !== "" || composer.hasAtt || composer.hasChips
                        icon: ""
                        tint: Theme.danger
                        tip: "Очистить поле ввода, чипы и вложения"
                        onClicked: { input.text = ""; Ai.clearAttachments(); Ai.clearContextChips(); root.histIdx = -1; input.forceActiveFocus() }
                    }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    // Кнопка живого перенаправления (Steer ↪), когда агент занят и в поле есть текст
                    Chip {
                        visible: Ai.busy && root.canSend
                        height: 28
                        label: "↪ Направить"
                        tint: "#f59e0b"
                        on: true
                        tip: "Прервать текущий ход и сразу направить агента по новому курсу (Ctrl+Enter)"
                        onClicked: root.submitSteer()
                    }

                    // Кнопка добавления в очередь, когда агент занят и в поле есть текст
                    Chip {
                        visible: Ai.busy && root.canSend
                        height: 28
                        label: "+ В очередь"
                        tint: Theme.primary
                        tip: "Поставить сообщение в очередь после завершения текущего хода (Enter)"
                        onClicked: root.submit()
                    }

                    // Основная кнопка Отправить / Стоп
                    Rectangle {
                        id: sendBtn
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        width: Ai.busy ? 82 : root.canSend ? (Ai.interactionMode === "plan" ? 108 : 102) : 32
                        radius: 15
                        color: Ai.busy ? Theme.danger
                             : root.canSend ? (Ai.interactionMode === "plan" ? "#f59e0b" : Theme.primary)
                             : Theme.strong
                        Behavior on width { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Ai.busy ? "" : ""
                                color: Ai.busy || root.canSend ? Theme.base : Theme.muted
                                font { family: Theme.iconFont; pixelSize: 11 }
                            }
                            Text {
                                visible: Ai.busy || root.canSend
                                anchors.verticalCenter: parent.verticalCenter
                                text: Ai.busy ? "Стоп" : (Ai.interactionMode === "plan" ? "В план" : "Отправить")
                                color: Theme.base
                                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: root.tipRequest(containsMouse ? sendBtn : null, Ai.busy ? "Остановить генерацию (Esc)" : "Отправить сообщение (Enter)")
                            onClicked: { root.tipRequest(null, ""); if (Ai.busy) Ai.stop(); else root.submit() }
                        }
                    }
                }
            }
        }

        // ═══════════ 6. ВСПЛЫВАЮЩИЕ МЕНЮ (/, @, $, GIT WORKTREE, STASH)

        // 6.1 Меню @-упоминаний (файлы, папки, треды) и $-скиллов
        Rectangle {
            id: mentionPopup
            visible: root.mentionOpen
            anchors { left: parent.left; bottom: composer.top; bottomMargin: 6 }
            width: Math.min(parent.width, 560)
            height: Math.min(320, mentionList.contentHeight + 36)
            z: 65
            radius: 16
            color: Qt.rgba(0.04, 0.04, 0.06, 0.97)
            border { width: 1; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45) }

            Text {
                id: mentionHeader
                anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 14 }
                text: root.tokenTrigger.kind === "skill"
                    ? "⚡ Скиллы агентов (" + root.mentionMatches.length + ") · Tab/Enter выбрать"
                    : "📄 Файлы и треды в " + root.shortDir(Ai.cwd) + " (" + root.mentionMatches.length + ") · Tab/Enter выбрать"
                color: Theme.muted
                font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
            }

            ListView {
                id: mentionList
                anchors { top: mentionHeader.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                clip: true
                spacing: 2
                model: root.mentionMatches
                currentIndex: root.mentionIdx
                delegate: Rectangle {
                    id: mrow
                    required property int index
                    required property var modelData
                    readonly property bool sel: index === root.mentionIdx
                    width: mentionList.width
                    height: 32
                    radius: 9
                    color: sel ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : mrm.containsMouse ? Theme.weak : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Text {
                            text: mrow.modelData.kind === "thread" ? "💬" : mrow.modelData.kind === "dir" ? "📁" : mrow.modelData.kind === "skill" ? "⚡" : "📄"
                            font { pixelSize: 12 }
                        }
                        Text {
                            text: mrow.modelData.label
                            color: Theme.text
                            font { family: "MedeoMono Nerd Font Mono"; pixelSize: 12; weight: Font.Medium }
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: mrow.modelData.desc || mrow.modelData.detail || ""
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    MouseArea {
                        id: mrm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.mentionIdx = mrow.index
                        onClicked: root.applyMention(mrow.modelData)
                    }
                }
            }
        }

        // 6.2 Меню слэш-команд (/)
        Rectangle {
            id: slashPopup
            visible: root.slashOpen
            anchors { left: parent.left; bottom: composer.top; bottomMargin: 6 }
            width: Math.min(parent.width, 580)
            height: Math.min(340, slashList.contentHeight + 38)
            z: 60
            radius: 16
            color: Qt.rgba(0.04, 0.04, 0.06, 0.96)
            border { width: 1; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) }

            Row {
                id: slashHeader
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 8; leftMargin: 14; rightMargin: 14 }
                height: 20
                spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 4; color: root.provColor(Ai.provider) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Команды · " + root.provName(Ai.provider) + " (" + root.slashMatches.length + ")"
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↑↓ выбор · Tab подставить · Enter выполнить"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 10 }
                }
            }

            ListView {
                id: slashList
                anchors { top: slashHeader.bottom; topMargin: 4; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.slashMatches
                currentIndex: root.slashIdx
                delegate: Rectangle {
                    id: srow
                    required property int index
                    required property var modelData
                    readonly property bool sel: index === root.slashIdx
                    readonly property string tagText: modelData.tag ?? ""
                    readonly property color tagColor: tagText === "Claude" ? "#d97757" : tagText === "Codex" ? "#10a37f" : tagText === "AGY" ? "#5b8def" : tagText === "Skill" ? Theme.accent : Theme.muted
                    width: slashList.width
                    height: 34
                    radius: 10
                    color: sel ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : srm.containsMouse ? Theme.weak : "transparent"

                    Row {
                        id: scmdRow
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Rectangle {
                            visible: srow.tagText !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18; width: stagTxt.implicitWidth + 10; radius: 5
                            color: Qt.rgba(srow.tagColor.r, srow.tagColor.g, srow.tagColor.b, 0.16)
                            border { width: 1; color: Qt.rgba(srow.tagColor.r, srow.tagColor.g, srow.tagColor.b, 0.35) }
                            Text { id: stagTxt; anchors.centerIn: parent; text: srow.tagText; color: srow.tagColor; font { family: "MedeoMono Nerd Font Mono"; pixelSize: 9; weight: Font.DemiBold } }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: srow.modelData.cmd; color: Theme.primary; font { family: "MedeoMono Nerd Font Mono"; pixelSize: 12; weight: Font.DemiBold } }
                        Text { visible: (srow.modelData.args ?? "") !== ""; anchors.verticalCenter: parent.verticalCenter; text: srow.modelData.args; color: Theme.faint; font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 } }
                    }

                    Text {
                        anchors { left: scmdRow.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        text: srow.modelData.desc
                        color: srow.sel ? Theme.text : Theme.muted
                        font { family: Theme.font; pixelSize: 12 }
                    }

                    MouseArea {
                        id: srm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.slashIdx = srow.index
                        onClicked: root.applySlash(srow.modelData, true)
                    }
                }
            }
        }

        // 6.3 Меню управления Git-ветками и Worktree (BranchToolbar)
        Rectangle {
            id: gitPopup
            visible: root.gitPopupOpen
            anchors { right: parent.right; top: row1.bottom; topMargin: 6 }
            width: 340
            height: gitCol.implicitHeight + 24
            z: 70
            radius: 16
            color: Qt.rgba(0.04, 0.04, 0.06, 0.97)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.16) }

            Column {
                id: gitCol
                x: 12; y: 12
                width: parent.width - 24
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 8
                    Text { text: "⑂ Git · " + (Ai.gitInfo?.branch || ""); color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                    Chip {
                        visible: !Ai.gitInfo?.isWorktree
                        height: 22
                        label: "+ Создать Worktree"
                        tint: "#10a37f"
                        tip: "Создать изолированный git worktree для безопасной работы агента в отдельной ветке"
                        onClicked: { Ai.createWorktreeForChat(""); root.gitPopupOpen = false }
                    }
                    Chip {
                        visible: !!Ai.gitInfo?.isWorktree
                        height: 22
                        label: "Слить в основную ветку ↵"
                        tint: "#30d158"
                        onClicked: { Ai.mergeWorktreeBack(); root.gitPopupOpen = false }
                    }
                }

                Rectangle {
                    width: parent.width; height: 26; radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)
                    TextInput {
                        id: newBranchInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        color: Theme.text
                        font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 }
                        onAccepted: {
                            if (text.trim() !== "") {
                                Ai.switchGitBranch(text.trim(), true)
                                text = ""
                                root.gitPopupOpen = false
                            }
                        }
                        Text { visible: newBranchInput.text === ""; text: "Новая ветка (Enter — создать и перейти)…"; color: Theme.faint; font: newBranchInput.font }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: (Ai.gitInfo?.branches ?? []).slice(0, 14)
                        Chip {
                            required property string modelData
                            height: 22
                            label: modelData
                            on: modelData === Ai.gitInfo?.branch
                            onClicked: { Ai.switchGitBranch(modelData, false); root.gitPopupOpen = false }
                        }
                    }
                }
            }
        }

        // 6.4 Попап сохранённых черновиков (Prompt Stash)
        Rectangle {
            id: stashPopup
            visible: root.stashPopupOpen
            anchors { left: parent.left; bottom: composer.top; bottomMargin: 6 }
            width: Math.min(parent.width, 460)
            height: Math.min(280, stashCol.implicitHeight + 24)
            z: 70
            radius: 16
            color: Qt.rgba(0.04, 0.04, 0.06, 0.97)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.16) }

            Column {
                id: stashCol
                x: 12; y: 12
                width: parent.width - 24
                spacing: 6
                Text { text: " Черновики (Stash · Ctrl+S)"; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                Text {
                    visible: Ai.stashList.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Нет отложенных черновиков. Нажмите Ctrl+S в поле ввода, чтобы сохранить черновик."
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
                Repeater {
                    model: Ai.stashList
                    Rectangle {
                        id: stRow
                        required property var modelData
                        width: stashCol.width; height: 32; radius: 8
                        color: Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 60; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: stRow.modelData.text || "(вложения)"
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Chip {
                                height: 22
                                label: "Вернуть"
                                onClicked: {
                                    input.text = Ai.popStash(stRow.modelData.id)
                                    input.cursorPosition = input.text.length
                                    root.stashPopupOpen = false
                                    input.forceActiveFocus()
                                }
                            }
                            IconBtn {
                                width: 22; height: 22; radius: 11
                                icon: ""
                                tint: Theme.danger
                                onClicked: Ai.removeStash(stRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══════════ 7. МОДАЛЬНОЕ ОКНО ПРОСМОТРА DIFF (TURN DIFF VIEWER)
    Rectangle {
        id: diffModal
        visible: Ai.diffOpen
        anchors.fill: parent
        z: 95
        radius: 18
        color: Qt.rgba(0.03, 0.03, 0.05, 0.96)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.16) }

        Item {
            id: diffHead
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            height: 30
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "⑂ " + Ai.diffTitle
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Chip {
                    label: "Скопировать diff"
                    onClicked: Quickshell.execDetached(["wl-copy", Ai.diffText])
                }
                IconBtn {
                    icon: ""
                    tip: "Закрыть diff (Esc)"
                    onClicked: Ai.closeDiff()
                }
            }
        }

        ListView {
            anchors { left: parent.left; right: parent.right; top: diffHead.bottom; bottom: parent.bottom; margins: 12; topMargin: 6 }
            clip: true
            model: Ai.diffLoading ? ["Загрузка diff…"] : (Ai.diffText || "").split("\n")
            delegate: Rectangle {
                required property string modelData
                width: ListView.view.width
                height: 19
                color: modelData.startsWith("+") && !modelData.startsWith("+++") ? Qt.rgba(0.19, 0.82, 0.35, 0.14)
                     : modelData.startsWith("-") && !modelData.startsWith("---") ? Qt.rgba(1.0, 0.27, 0.23, 0.14)
                     : modelData.startsWith("@@") ? Qt.rgba(0.36, 0.55, 0.94, 0.14)
                     : "transparent"
                Text {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData
                    color: parent.modelData.startsWith("+") ? "#4ade80"
                         : parent.modelData.startsWith("-") ? "#f87171"
                         : parent.modelData.startsWith("@@") ? "#60a5fa"
                         : Theme.text
                    font { family: "MedeoMono Nerd Font Mono"; pixelSize: 11 }
                }
            }
        }
    }

    // ═══════════ 8. DRAG & DROP И ПРОСМОТР ИЗОБРАЖЕНИЙ (LIGHTBOX)
    DropArea {
        id: dropArea
        anchors.fill: parent
        z: 80
        onDropped: drop => {
            const items = []
            if (drop.hasUrls) {
                for (let i = 0; i < drop.urls.length; i++) items.push(drop.urls[i].toString())
            } else if (drop.hasText && drop.text) {
                items.push(drop.text)
            }
            if (items.length > 0) root.inspectDropped(items)
            drop.accept()
        }

        Rectangle {
            visible: dropArea.containsDrag
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(0.04, 0.05, 0.08, 0.84)
            border { width: 2; color: Theme.primary }
            Column {
                anchors.centerIn: parent
                spacing: 10
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf0c6"; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 38 } }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Отпустите, чтобы прикрепить изображения или файлы"; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }
            }
        }
    }

    Rectangle {
        id: lightbox
        visible: root.previewPath !== ""
        anchors.fill: parent
        z: 90
        radius: 18
        color: Qt.rgba(0.03, 0.03, 0.05, 0.92)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }

        MouseArea { anchors.fill: parent; onClicked: { root.previewPath = ""; input.forceActiveFocus() } }

        Item {
            id: lbHead
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            height: 32
            z: 2
            Text {
                anchors { left: parent.left; right: lbActions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                elide: Text.ElideMiddle
                text: root.previewTitle || root.previewPath.split("/").pop()
                color: Theme.text
                font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
            }
            Row {
                id: lbActions
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Chip { label: "Скопировать"; onClicked: Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "cp", root.previewPath]) }
                Chip { label: "Открыть"; onClicked: Quickshell.execDetached(["xdg-open", root.previewPath]) }
                IconBtn { icon: ""; tip: "Закрыть (Esc)"; onClicked: { root.previewPath = ""; input.forceActiveFocus() } }
            }
        }

        Image {
            anchors { left: parent.left; right: parent.right; top: lbHead.bottom; bottom: parent.bottom; margins: 16; topMargin: 8 }
            source: root.previewPath !== "" ? "file://" + root.previewPath : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
    }
}
