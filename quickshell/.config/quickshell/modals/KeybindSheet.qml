pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Шпаргалка: читает ~/.config/mango/binds.conf, разделы — заголовки «# ── Имя ──».
// Описание берётся из комментария в конце строки бинда (… # Описание),
// иначе генерируется из действия. Набор текста — фильтр, Esc — закрыть.
ModalWindow {
    id: root
    name: "cheatsheet"
    cardWidth: 1340
    cardHeight: 900

    property string query: ""
    Connections {
        target: Demo
        function onQueryChanged() { root.query = Demo.query }
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/mango/binds.conf"
        blockLoading: true
    }

    readonly property var keyNames: ({
        "return": "Enter", "space": "Space", "grave": "`", "slash": "/", "minus": "−", "equal": "=",
        "period": ".", "comma": ",", "tab": "Tab", "page_up": "PgUp", "page_down": "PgDn", "print": "Print",
        "left": "←", "right": "→", "up": "↑", "down": "↓", "escape": "Esc",
        "xf86audioraisevolume": "Vol +", "xf86audiolowervolume": "Vol −", "xf86audiomute": "Mute",
        "xf86audiomicmute": "Mic Mute", "xf86monbrightnessup": "Bright +", "xf86monbrightnessdown": "Bright −",
        "btn_left": "ЛКМ", "btn_right": "ПКМ", "btn_middle": "СКМ"
    })
    readonly property var actionNames: ({
        killclient: "Закрыть окно", togglefloating: "Плавающее / плитка", togglemaximizescreen: "Развернуть",
        togglefullscreen: "Полный экран", reload_config: "Перезагрузить конфиг mango",
        toggle_named_scratchpad: "Выпадающий терминал", minimized: "Свернуть в скретчпад",
        toggle_scratchpad: "Показать скретчпад", restore_minimized: "Вернуть из скретчпада",
        toggleglobal: "Окно на всех рабочих столах", toggleoverview: "Обзор", togglejump: "Прыжок к окну",
        switcher: "Переключатель окон", zoom: "Сделать главным", switch_layout: "Следующая раскладка окон",
        quit: "Выйти из mango"
    })
    readonly property var dirNames: ({ left: "влево", right: "вправо", up: "вверх", down: "вниз", next: "следующий", prev: "предыдущий" })
    readonly property var spawnNames: ({
        "clip-pick": "Буфер обмена", "mango-keys": "Шпаргалка", "waypaper": "Обои", "powermenu": "Меню питания",
        "alacritty": "Терминал", "alacritty -e yazi": "Файлы (Yazi)", "yazi": "Файлы (Yazi)", "dolphin": "Файлы", "fuzzel": "Лаунчер", "emoji-pick": "Эмодзи",
        "ocr": "Распознать текст с экрана", "pavucontrol-qt": "Микшер", "loginctl lock-session": "Заблокировать",
        "wm kill-focused": "Завершить зависшее окно",
        "quickshell ipc call modal dismissOrKill || mmsg dispatch killclient": "Закрыть окно",
        "qs -c lite ipc call modal dismissOrKill || mmsg dispatch killclient": "Закрыть окно",
        "quickshell ipc call modal toggle settings": "Настройки оболочки", "quickshell ipc call modal toggle barconfig": "Настройка панели",
        "qs -c lite ipc call modal toggle settings": "Настройки оболочки", "qs -c lite ipc call modal toggle barconfig": "Настройка панели",
        "quickshell ipc call privacy toggle": "Приватный режим", "quickshell ipc call ai toggle": "ИИ-помощник",
        "qs -c lite ipc call privacy toggle": "Приватный режим", "qs -c lite ipc call ai toggle": "ИИ-помощник",
        "cider-vol up": "Громкость плеера +", "cider-vol down": "Громкость плеера −",
        "cider-ctl next": "Следующий трек", "cider-ctl previous": "Предыдущий трек", "cider-ctl play-pause": "Пауза / играть", "cider-ctl like": "Мне нравится",
        "ashell msg volume-up": "Громкость +", "ashell msg volume-down": "Громкость −",
        "ashell msg volume-toggle-mute": "Звук вкл/выкл", "ashell msg microphone-toggle-mute": "Микрофон вкл/выкл",
        "ashell msg brightness-up": "Яркость +", "ashell msg brightness-down": "Яркость −",
        "discord-keys mute": "Discord: микрофон", "discord-keys deafen": "Discord: звук",
        "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+": "Громкость +", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-": "Громкость −",
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle": "Звук вкл/выкл", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle": "Микрофон вкл/выкл",
        "brightnessctl set 5%+": "Яркость +", "brightnessctl set 5%-": "Яркость −",
        "quickshell ipc call modal toggle launcher": "Лаунчер", "quickshell ipc call modal toggle power": "Меню питания",
        "quickshell ipc call modal toggle cheatsheet": "Шпаргалка", "quickshell ipc call modal toggle clipboard": "Буфер обмена", "quickshell ipc call modal toggle wallpapers": "Обои",
        "quickshell ipc call modal toggle overview": "Обзор рабочих столов", "quickshell ipc call modal toggle wininfo": "Сведения об окне", "quickshell ipc call modal toggle emoji": "Эмодзи", "quickshell ipc call switcher next": "Переключатель окон", "quickshell ipc call switcher prev": "Переключатель окон (назад)", "quickshell ipc call region menu": "Скриншот (выделение)", "quickshell ipc call region edit": "Скриншот + редактор", "quickshell ipc call region ocr": "Распознать текст с экрана", "quickshell ipc call region record": "Запись области / стоп", "quickshell ipc call region recordSound": "Запись со звуком / стоп",
        "qs -c lite ipc call modal toggle launcher": "Лаунчер", "qs -c lite ipc call modal toggle power": "Меню питания",
        "qs -c lite ipc call modal toggle cheatsheet": "Шпаргалка", "qs -c lite ipc call modal toggle clipboard": "Буфер обмена", "qs -c lite ipc call modal toggle wallpapers": "Обои",
        "qs -c lite ipc call modal toggle overview": "Обзор рабочих столов", "qs -c lite ipc call modal toggle wininfo": "Сведения об окне", "qs -c lite ipc call modal toggle emoji": "Эмодзи", "qs -c lite ipc call switcher next": "Переключатель окон", "qs -c lite ipc call switcher prev": "Переключатель окон (назад)", "qs -c lite ipc call region menu": "Скриншот (выделение)", "qs -c lite ipc call region edit": "Скриншот + редактор", "qs -c lite ipc call region ocr": "Распознать текст с экрана", "qs -c lite ipc call region record": "Запись области / стоп", "qs -c lite ipc call region recordSound": "Запись со звуком / стоп",
        "shot region": "Скриншот области", "shot screen": "Скриншот экрана", "shot annotate": "Скриншот + разметка"
    })

    function describe(action, args) {
        const a = args.filter(x => x !== "")
        if (action === "spawn" || action === "spawn_shell") {
            const cmd = a.join(",").replace(/^\S*\//, "")          // без пути к скрипту
            const known = spawnNames[cmd] ?? spawnNames[cmd.split(" ")[0]]
            if (known) return known
            const m = cmd.match(/^(?:qs|quickshell)(?: -c lite)? ipc call (\w+)(?: (\w+))?/)
            if (m) return "Оболочка: " + m[1] + (m[2] ? " " + m[2] : "")
            return cmd
        }
        if (actionNames[action]) return actionNames[action]
        switch (action) {
        case "view": return "Рабочий стол " + a[0]
        case "tag": return "Окно → рабочий стол " + a[0]
        case "focusdir": return "Фокус " + (dirNames[a[0]] ?? a[0])
        case "exchange_client": return "Поменять местами " + (dirNames[a[0]] ?? a[0])
        case "focusmon": return "Фокус на монитор " + (dirNames[a[0]] ?? a[0])
        case "tagmon": return "Окно → монитор " + (dirNames[a[0]] ?? a[0])
        case "setmfact": return "Ширина главной области " + a[0]
        case "incnmaster": return "Окон в главной области " + a[0]
        case "setlayout": return "Раскладка: " + a[0]
        case "focusstack": return "Фокус: " + (dirNames[a[0]] ?? a[0]) + " окно"
        case "moveresize": return a[0] === "curmove" ? "Двигать окно" : "Менять размер окна"
        case "viewtoleft_have_client": return "Предыдущий занятый рабочий стол"
        case "viewtoright_have_client": return "Следующий занятый рабочий стол"
        }
        return [action].concat(a).join(" ")
    }

    function keyLabel(type, mods, key) {
        const parts = mods.toLowerCase() === "none" ? [] : mods.split("+").map(m => m.charAt(0).toUpperCase() + m.slice(1).toLowerCase())
        let k = key.toLowerCase()
        if (type === "axisbind") k = k === "up" ? "Колесо ↑" : k === "down" ? "Колесо ↓" : "Колесо " + key
        else k = keyNames[k] ?? (key.length === 1 ? key.toUpperCase() : key)
        return parts.concat([k])
    }

    // значки разделов — по словам в заголовке
    function sectionIcon(t) {
        const l = t.toLowerCase()
        return l.includes("оверле") ? "" : l.includes("систем") ? "" : l.includes("прилож") ? ""
             : l.includes("громк") ? "" : l.includes("фокус") ? "" : l.includes("перемещ") ? ""
             : l.includes("размер") ? "" : l.includes("раскладк") ? "" : l.includes("скрин") ? ""
             : l.includes("тег") ? "" : l.includes("монитор") ? "" : l.includes("мыш") ? "" : ""
    }

    // понятные названия разделов; одинаковые — склеиваются
    readonly property var titleMap: ({
        "Оверлеи и утилиты": "Окна оболочки", "Система / сессия": "Окна и сеанс", "Приложения": "Запуск",
        "Громкость": "Звук и мультимедиа", "Фокус": "Фокус и расположение", "Перемещение окон": "Фокус и расположение",
        "Размер": "Фокус и расположение", "Раскладки": "Фокус и расположение", "Скриншоты": "Скриншоты",
        "Теги (воркспейсы)": "Рабочие столы", "Мышь": "Мышь и колесо"
    })
    // связанные бинды сворачиваются в одну строку (стрелки, колесо, раскладки)
    readonly property var foldDefs: ({
        focusdir: { id: "focusdir", desc: "Фокус на соседнее окно" },
        exchange_client: { id: "exchange", desc: "Поменять местами с соседним" },
        setmfact: { id: "mfact", desc: "Ширина главной области" },
        incnmaster: { id: "nmaster", desc: "Сколько окон в главной области" },
        focusstack: { id: "wheelfocus", desc: "Переключать фокус между окнами" },
        viewtoleft_have_client: { id: "wheelview", desc: "Листать рабочие столы" },
        viewtoright_have_client: { id: "wheelview", desc: "Листать рабочие столы" },
        setlayout: { id: "layout", desc: "Раскладка: плитка / монокль / сетка" }
    })
    // клавиши мультимедиа сворачиваются в подсказку: на клавиатуре они и так подписаны
    readonly property var hwKeys: ["Vol +", "Vol −", "Mute", "Mic Mute", "Bright +", "Bright −"]
    // раздел определяется по описанию, а не по месту в файле
    readonly property var categories: [
        ["Звук и мультимедиа", /громк|трек|пауза|яркост|микрофон|звук|discord|нравится|мультимедиа/i],
        ["Скриншоты", /скриншот|распознать/i],
        ["Рабочие столы", /рабочий стол|рабочих стол|занятые рабочие/i],
        ["Окна и сеанс", /заблокировать|питания|конфиг|выйти|завершить зависшее/i],
        ["Фокус и расположение", /фокус|раскладк|главн|поменять|переключатель|двигать|размер|ширина|сколько/i],
        ["Управление окнами", /окно|окна|окон|фокус|раскладк|главн|плавающее|развернуть|полный экран|скретчпад|двигать|размер/i],
        ["Запуск", /терминал|файлы|лаунчер|приложени/i],
        ["Окна оболочки", /буфер|эмодзи|шпаргалка|обои|сведения|обзор|переключатель|настройки|панел|приватный|помощник/i]
    ]
    readonly property var sectionOrder: ["Окна оболочки", "Запуск", "Окна и сеанс", "Управление окнами", "Фокус и расположение", "Рабочие столы", "Скриншоты", "Звук и мультимедиа", "Мышь и колесо"]

    readonly property var sections: {
        const out = []
        let sec = { title: "Общее", binds: [] }
        const q = query.trim().toLowerCase()
        const flush = () => {
            // связанные бинды (стрелки, колесо, раскладки) → одна строка с общим описанием
            const folded = [], groups = {}
            for (const b of sec.binds) {
                const def = root.foldDefs[b.action]
                if (def) {
                    const k = def.id + "|" + b.mods
                    const g = groups[k]
                    if (g) { g.names.push(b.keyName); continue }
                    const ng = Object.assign({}, b, { names: [b.keyName], fold: def })
                    groups[k] = ng
                    folded.push(ng)
                } else if (root.hwKeys.indexOf(b.keyName) >= 0) continue
                else folded.push(b)
            }
            sec.binds = folded.map(b => {
                if (!b.fold) return b
                const wheel = b.names.every(n => n.startsWith("Колесо "))
                const label = wheel ? "Колесо " + b.names.map(n => n.slice(7)).join("")
                            : b.names.join(b.names.every(n => n.length === 1 && n !== n.toLowerCase()) ? " / " : " ")
                return Object.assign({}, b, { keys: b.keys.slice(0, -1).concat([label]), keyName: label, desc: b.fold.desc })
            })
            // «Тег 1» … «Тег 10» подряд с одними модификаторами → одна строка «Super + 1…0»
            const merged = []
            for (const b of sec.binds) {
                const prev = merged[merged.length - 1]
                if (prev && b.series && prev.series === b.series && prev.mods === b.mods) { prev.last = b.keyName; prev.count++; continue }
                merged.push(Object.assign({}, b, { first: b.keyName, last: b.keyName, count: 1 }))
            }
            sec.binds = merged.map(b => b.count > 1
                ? { keys: b.keys.slice(0, -1).concat([b.first + "…" + b.last]), desc: b.seriesDesc }
                : { keys: b.keys, desc: b.desc })
                .filter(b => !q || (b.desc + " " + b.keys.join(" ") + " " + sec.title).toLowerCase().includes(q))
            // одинаковые строки (одно действие и клавиши) не повторяем
            const seen = {}
            sec.binds = sec.binds.filter(b => { const k = b.desc + "|" + b.keys.join("+"); if (seen[k]) return false; seen[k] = 1; return true })
            if (!sec.binds.length) return
            for (const b of sec.binds) {
                let t = root.titleMap[sec.title] ?? sec.title
                for (const c of root.categories) if (c[1].test(b.desc)) { t = c[0]; break }
                let tgt = out.find(x => x.title === t)
                if (!tgt) { tgt = { title: t, binds: [] }; out.push(tgt) }
                tgt.binds.push(b)
            }
        }
        for (const raw of file.text().split("\n")) {
            const head = raw.match(/^#\s*──\s*(.+?)\s*─*$/)
            if (head) {
                flush()
                sec = { title: head[1].replace(/:.*$/, ""), binds: [] }
                continue
            }
            const m = raw.match(/^(bind|mousebind|axisbind)[a-z]*\s*=\s*([^#]*?)\s*(?:#\s*(.*))?$/)
            if (!m) continue
            const f = m[2].split(",").map(s => s.trim())
            if (f.length < 3) continue
            const keys = root.keyLabel(m[1], f[0], f[1])
            const series = (f[2] === "view" || f[2] === "tag") && /^\d+$/.test(f[3] ?? "") ? f[2] : ""
            sec.binds.push({ keys: keys, action: f[2], desc: m[3] || root.describe(f[2], f.slice(3)), mods: f[0].toLowerCase(),
                             series: series, keyName: keys[keys.length - 1],
                             seriesDesc: series === "view" ? "Перейти на рабочий стол 1–10" : "Окно на рабочий стол 1–10" })
        }
        flush()
        out.sort((a, b) => {
            const ia = root.sectionOrder.indexOf(a.title), ib = root.sectionOrder.indexOf(b.title)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        })
        return out
    }
    readonly property int total: sections.reduce((n, s) => n + s.binds.length, 0)

    // раскладка «кирпичиками»: раздел — в самую короткую колонку
    readonly property int columns: 3
    readonly property var colSections: {
        const cols = [], h = []
        for (let i = 0; i < columns; i++) { cols.push([]); h.push(0) }
        for (const s of sections) {
            const i = h.indexOf(Math.min(...h))
            cols[i].push(s)
            h[i] += 56 + s.binds.length * 34
        }
        return cols
    }

    // набор текста — фильтр (без отдельного поля: просто печатаешь)
    onKeyPressed: e => {
        if (e.key === Qt.Key_Backspace) { query = query.slice(0, -1); e.accepted = true }
        else if (e.text && e.text.length === 1 && e.text >= " ") { query += e.text; e.accepted = true }
    }

    // ── шапка
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 22 }
        height: 40
        Text {
            id: hIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: ""
            color: Theme.primary
            font { family: Theme.iconFont; pixelSize: 24 }
        }
        Column {
            anchors { left: hIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            Text {
                text: "Горячие клавиши"
                color: Theme.text
                font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
            }
            Text {
                text: "Главная клавиша — Super (Win) · " + root.total + " " + (root.query ? Theme.plural(root.total, "найдено", "найдено", "найдено") : Theme.plural(root.total, "сочетание", "сочетания", "сочетаний"))
                color: Theme.faint
                font { family: Theme.font; pixelSize: 12 }
            }
        }
        // поиск: просто печатай
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 300; height: 38; radius: 19
            color: Theme.weak
            border { width: 1; color: root.query ? Theme.primary : Theme.strong }
            Text {
                id: sIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: ""
                color: root.query ? Theme.primary : Theme.faint
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            Text {
                anchors { left: sIcon.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: root.query || "Печатай для поиска…"
                elide: Text.ElideLeft
                color: root.query ? Theme.text : Theme.faint
                font { family: Theme.font; pixelSize: 14 }
            }
        }
    }

    component Keycap: Rectangle {
        property string label
        width: Math.max(26, capText.implicitWidth + 14)
        height: 24
        radius: 7
        color: Qt.rgba(1, 1, 1, 0.09)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.16) }
        // «нижняя грань» клавиши
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
            height: 2; radius: 1
            color: Qt.rgba(0, 0, 0, 0.25)
        }
        Text {
            id: capText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: parent.label
            color: Theme.text
            font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
        }
    }

    Flickable {
        id: flick
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 16; topMargin: 16 }
        contentHeight: colsRow.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: colsRow
            width: flick.width
            spacing: 14

            Repeater {
                model: root.colSections
                Column {
                    id: column
                    required property var modelData
                    width: (colsRow.width - colsRow.spacing * (root.columns - 1)) / root.columns
                    spacing: 14

                    Repeater {
                        model: column.modelData
                        Glass {
                            id: secCard
                            required property var modelData
                            width: column.width
                            height: col.implicitHeight + 22
                            radius: 12                 // концентрично: окно 28 − отступ 16
                            color: Qt.rgba(0, 0, 0, 0.22)
                            sheen: false
                            interactive: false
                            fresnel: 0.5
                            rimColor: Qt.rgba(1, 1, 1, 0.07)
                            glintColor: Qt.rgba(1, 1, 1, 0.55)
                            rimWidth: 1

                            Column {
                                id: col
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 12 }
                                spacing: 4

                                Row {
                                    spacing: 9
                                    bottomPadding: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.sectionIcon(secCard.modelData.title)
                                        color: Theme.primary
                                        font { family: Theme.iconFont; pixelSize: 14 }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: secCard.modelData.title
                                        color: Theme.text
                                        font { family: Theme.font; pixelSize: 14; weight: Font.Bold }
                                    }
                                }

                                Repeater {
                                    model: secCard.modelData.binds
                                    Rectangle {
                                        id: line
                                        required property var modelData
                                        required property int index
                                        width: col.width
                                        height: 30
                                        radius: 8
                                        color: lm.containsMouse ? Theme.weak : "transparent"
                                        MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true }

                                        Text {
                                            anchors { left: parent.left; leftMargin: 6; right: keysRow.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            text: line.modelData.desc
                                            elide: Text.ElideRight
                                            color: lm.containsMouse ? Theme.text : Qt.rgba(1, 1, 1, 0.78)
                                            font { family: Theme.font; pixelSize: 13 }
                                        }
                                        Row {
                                            id: keysRow
                                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                            spacing: 4
                                            Repeater {
                                                model: line.modelData.keys
                                                Row {
                                                    id: kp
                                                    required property string modelData
                                                    required property int index
                                                    spacing: 4
                                                    Text {
                                                        visible: kp.index > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "+"
                                                        color: Theme.faint
                                                        font { family: Theme.font; pixelSize: 11 }
                                                    }
                                                    Keycap { label: kp.modelData }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
