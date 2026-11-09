pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Обзор тегов (воркспейсов) текущего монитора: все 10 тегов миниатюрами,
// окна на своих местах с превью (захват окна через mango) или значком.
//   клик по тегу — перейти; клик по окну — фокус; СКМ по окну — закрыть;
//   окно можно перетащить на другой тег; ←→↑↓ + Enter, 1…0 — сразу на тег; Esc — закрыть.
PanelWindow {
    id: win
    property var monitor: null        // монитор mango с фокусом: { name, x, y, width, height, active_tags, ... }
    property var clients: []
    property string wallpaper: ""
    property int cursor: -1           // тег под клавиатурным курсором (0…9)
    property var dragged: null        // окно, которое тащат

    readonly property int cols: 5
    readonly property real gap: 22
    readonly property real cardW: monitor ? Math.min((width - 160 - gap * (cols - 1)) / cols, (height - 260) / 2 * monitor.width / monitor.height) : 0
    readonly property real cardH: monitor ? cardW * monitor.height / monitor.width : 0
    readonly property real k: monitor ? cardW / monitor.width : 1
    readonly property int activeTag: monitor?.active_tags?.[0] ?? 1

    screen: Quickshell.screens.find(s => s.name === monitor?.name) ?? null
    visible: monitor !== null && thumbsReady
    // превью окон: при открытии снимаем видимые окна (grim, ¼ размера) в кэш — у окон на скрытых
    // тегах остаются последние снимки. Живой захват окон (ScreencopyView) mango+quickshell не умеют.
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-overview"
    property bool thumbsReady: false
    property real stamp: 0
    property bool gotClients: false
    onGotClientsChanged: {
        const vis = clients.filter(c => c.is_visible && !c.is_minimized && c.width > 0 && c.tags.length)
        const jobs = vis.map(c => `grim -s 0.3 -g "${c.x},${c.y} ${c.width}x${c.height}" "$1/${c.id}.png" &`).join(" ")
        thumbs.command = ["bash", "-c", 'mkdir -p "$1"; ' + jobs + " wait", "thumbs", thumbDir]
        thumbs.running = true
    }
    Process {
        id: thumbs
        onExited: { win.stamp = Date.now(); win.thumbsReady = true }
    }
    Timer { interval: 800; running: true; onTriggered: win.thumbsReady = true }
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    function dispatch(...args) { Quickshell.execDetached(["mmsg", "dispatch"].concat(args)) }
    function viewTag(n) { dispatch("view," + n + ",0"); Modal.close() }
    function focusClient(c) { dispatch("view," + c.tags[0] + ",0"); dispatch("focusid", "client," + c.id); Modal.close() }
    function tagClients(n) {
        return clients.filter(c => c.monitor === monitor?.name && c.tags.includes(n) && !c.is_minimized && !c.is_scratchpad)
                      // плитки снизу, плавающие и полноэкранные — сверху
                      .sort((a, b) => (a.is_floating + a.is_fullscreen * 2) - (b.is_floating + b.is_fullscreen * 2))
    }
    function appIcon(app) {
        return Quickshell.iconPath(DesktopEntries.heuristicLookup(app)?.icon ?? app, "application-x-executable")
    }

    // живые данные: mango присылает всё состояние при подключении и на каждое изменение
    Process {
        running: true
        command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line).monitors
                    const pref = Modal.anchorScreen?.name || (Demo.active ? Demo.screenName : "")
                    const cur = win.monitor ? m.find(x => x.name === win.monitor.name) : (pref ? m.find(x => x.name === pref) : m.find(x => x.active))
                    win.monitor = cur ?? m[0]
                    if (win.cursor < 0) win.cursor = win.activeTag - 1
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["mmsg", "watch", "all-clients"]
        stdout: SplitParser {
            onRead: line => { try { win.clients = JSON.parse(line).clients; win.gotClients = true } catch (e) {} }
        }
    }
    // обои монитора — фоном миниатюр
    Process {
        running: win.monitor !== null && win.wallpaper === ""
        command: ["awww", "query"]
        stdout: SplitParser {
            onRead: line => {
                const m = /: ([^:]+): .*image: (.+)$/.exec(line)
                if (m && m[1] === win.monitor?.name) win.wallpaper = m[2]
            }
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const n = e.key === Qt.Key_0 ? 10 : e.key - Qt.Key_0
            if (e.key === Qt.Key_Escape) Modal.close()
            else if (n >= 1 && n <= 10) win.viewTag(n)
            else if (e.key === Qt.Key_Left) win.cursor = (win.cursor + 9) % 10
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) win.cursor = (win.cursor + 1) % 10
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) win.cursor = (win.cursor + 5) % 10
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.viewTag(win.cursor + 1)
            else return
            e.accepted = true
        }

        // затемнение — полупрозрачное, mango размывает под ним весь экран
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
        }
        MouseArea { anchors.fill: parent; onClicked: Modal.close() }

        Column {
            id: content
            anchors.centerIn: parent
            spacing: 18
            scale: 0.96
            opacity: 0
            Component.onCompleted: { scale = 1; opacity = 1 }
            Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Рабочие столы"
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 22; weight: Font.DemiBold }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (win.monitor?.name ?? "") + " · " + win.clients.filter(c => c.monitor === win.monitor?.name && c.tags.length).length + " " + Theme.plural(win.clients.filter(c => c.monitor === win.monitor?.name && c.tags.length).length, "окно", "окна", "окон")
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 14 }
                }
            }

            Grid {
                id: grid
                columns: win.cols
                spacing: win.gap

                Repeater {
                    model: 10
                    Item {
                        id: card
                        required property int index
                        readonly property int tag: index + 1
                        readonly property var wins: win.tagClients(tag)
                        readonly property bool current: win.activeTag === tag
                        readonly property bool dropHere: win.dragged !== null && drop.containsDrag
                        width: win.cardW
                        height: win.cardH + 30

                        // номер и число окон
                        Row {
                            spacing: 8
                            x: 4
                            Text {
                                text: card.tag
                                color: card.current ? Theme.primary : Theme.text
                                font { family: Theme.font; pixelSize: 15; weight: Font.Bold; features: ({ "tnum": 1 }) }
                            }
                            Text {
                                anchors.baseline: parent.children[0].baseline
                                visible: card.wins.length > 0
                                text: card.wins.map(c => DesktopEntries.heuristicLookup(c.appid)?.name ?? c.appid)
                                               .filter((v, i, a) => a.indexOf(v) === i).join(", ")
                                width: win.cardW - 30
                                elide: Text.ElideRight
                                color: Theme.muted
                                font { family: Theme.font; pixelSize: 12 }
                            }
                        }

                        ClippingRectangle {
                            id: screenBox
                            y: 30
                            width: win.cardW
                            height: win.cardH
                            radius: 16
                            color: Qt.rgba(0, 0, 0, 0.5)
                            border { width: card.current || win.cursor === card.index || card.dropHere ? 2 : 1
                                     color: card.dropHere ? Theme.accent : card.current ? Theme.primary
                                          : win.cursor === card.index ? Theme.text : Theme.rimSoft }

                            Image {
                                anchors.fill: parent
                                source: win.wallpaper ? "file://" + win.wallpaper : ""
                                sourceSize { width: win.cardW; height: win.cardH }
                                fillMode: Image.PreserveAspectCrop
                                opacity: card.wins.length ? 0.35 : 0.55
                                asynchronous: true
                            }
                            Text {
                                visible: card.wins.length === 0
                                anchors.centerIn: parent
                                text: card.tag
                                color: Qt.rgba(1, 1, 1, 0.25)
                                font { family: Theme.font; pixelSize: win.cardH * 0.4; weight: Font.Bold }
                            }

                            MouseArea {
                                id: tagMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.viewTag(card.tag)
                            }
                            DropArea { id: drop; anchors.fill: parent; keys: ["qs-window"] }

                            // окна
                            Repeater {
                                model: card.wins
                                Item {
                                    id: tile
                                    required property var modelData
                                    readonly property bool hovered: tileMouse.containsMouse
                                    x: (modelData.x - win.monitor.x) * win.k
                                    y: (modelData.y - win.monitor.y) * win.k
                                    width: Math.max(16, modelData.width * win.k)
                                    height: Math.max(16, modelData.height * win.k)
                                    opacity: win.dragged === modelData ? 0.3 : 1

                                    ClippingRectangle {
                                        anchors { fill: parent; margins: 1 }
                                        radius: 8
                                        color: Qt.rgba(0.12, 0.12, 0.15, 0.9)
                                        border { width: tile.hovered ? 2 : 1; color: tile.hovered ? Theme.primary : Qt.rgba(1, 1, 1, 0.14) }

                                        Image {
                                            id: shot
                                            readonly property bool hasContent: status === Image.Ready
                                            anchors.fill: parent
                                            source: win.thumbsReady ? "file://" + win.thumbDir + "/" + tile.modelData.id + ".png" : ""
                                            fillMode: Image.PreserveAspectCrop
                                            cache: false
                                            asynchronous: true
                                            layer.enabled: Session.privacy && !tile.hovered
                                            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.5; brightness: -0.05 }
                                        }
                                        // без превью — крупный значок по центру
                                        Image {
                                            visible: !shot.hasContent
                                            anchors.centerIn: parent
                                            width: Math.min(48, parent.width * 0.45, parent.height * 0.45)
                                            height: width
                                            sourceSize { width: 96; height: 96 }
                                            source: win.appIcon(tile.modelData.appid)
                                        }
                                        // с превью — значок в углу
                                        Rectangle {
                                            visible: shot.hasContent && parent.width > 50
                                            anchors { left: parent.left; bottom: parent.bottom; margins: 5 }
                                            width: 24; height: 24; radius: 7
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            Image {
                                                anchors.centerIn: parent
                                                width: 18; height: 18
                                                sourceSize { width: 36; height: 36 }
                                                source: win.appIcon(tile.modelData.appid)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: tileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onContainsMouseChanged: {
                                            if (containsMouse) win.hoveredClient = tile.modelData
                                            else if (win.hoveredClient === tile.modelData) win.hoveredClient = null
                                        }
                                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        drag.target: ghost
                                        drag.threshold: 8
                                        onPressed: e => {
                                            if (e.button !== Qt.LeftButton) return
                                            const p = mapToItem(win.contentItem, e.x, e.y)
                                            ghost.app = tile.modelData.appid
                                            ghost.x = p.x - ghost.width / 2
                                            ghost.y = p.y - ghost.height / 2
                                        }
                                        drag.onActiveChanged: {
                                            if (drag.active) { win.dragged = tile.modelData; ghost.Drag.active = true; return }
                                            const target = ghost.Drag.target
                                            ghost.Drag.drop()
                                            ghost.Drag.active = false
                                            const c = win.dragged
                                            win.dragged = null
                                            // перенос на другой тег без переключения
                                            const dest = target ? target.parent.parent : null
                                            if (c && dest && dest.tag && !c.tags.includes(dest.tag))
                                                win.dispatch("tagsilent," + dest.tag, "client," + c.id)
                                        }
                                        onClicked: e => {
                                            if (e.button === Qt.MiddleButton) win.dispatch("killclient", "client," + tile.modelData.id)
                                            else win.focusClient(tile.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // заголовок окна под курсором / подсказка
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, grid.width)
                elide: Text.ElideRight
                text: win.hoveredClient?.title || "клик — перейти · СКМ по окну — закрыть окно · окна перетаскиваются между рабочими столами · 1…0, стрелки, Enter"
                color: win.hoveredClient ? Theme.text : Theme.faint
                font { family: Theme.font; pixelSize: 13 }
                layer.enabled: Session.privacy && !!win.hoveredClient
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48; saturation: -0.5; brightness: -0.05 }
            }
        }

        // «призрак» перетаскиваемого окна
        Rectangle {
            id: ghost
            property string app
            visible: win.dragged !== null
            width: 64; height: 64; radius: 18
            color: Qt.rgba(0.1, 0.1, 0.12, 0.85)
            border { width: 1; color: Theme.rim }
            Drag.keys: ["qs-window"]
            Drag.hotSpot.x: 32
            Drag.hotSpot.y: 32
            Image {
                anchors.centerIn: parent
                width: 40; height: 40
                sourceSize { width: 80; height: 80 }
                source: ghost.app ? win.appIcon(ghost.app) : ""
            }
        }
    }

    property var hoveredClient: null
}
