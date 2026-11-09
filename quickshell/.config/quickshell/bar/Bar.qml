import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick.Effects
import qs

// Бар на каждом мониторе: прозрачная полоса с «островами».
// Что и где стоит — в BarLayout (bar-layout.json); правится в окне «Настроить бар» (ПКМ по пустому месту бара).
Variants {
    model: Quickshell.screens.filter(s => s.name !== "HDMI-A-1")   // мини-дисплей — дашборд MiniDash, без бара

    PanelWindow {
        id: bar
        required property ShellScreen modelData
        screen: modelData
        readonly property bool primary: modelData.name === Theme.primaryMonitor
        readonly property string scope: primary ? "primary" : "secondary"
        property var widgetItems: ({})

        Component.onCompleted: BarLayout.registerBar(modelData.name, bar)
        Component.onDestruction: BarLayout.unregisterBar(modelData.name, bar)

        function widgetCenterX(id) {
            const it = widgetItems[id]
            if (it && it.visible && it.width > 0) return it.mapToItem(null, it.width / 2, 0).x + 10
            for (const z of [leftZone, centerZone, rightZone]) {
                for (let i = 0; i < z.rep.count; i++) {
                    const isl = z.rep.itemAt(i)
                    if (isl && isl.visible && isl.modelData && isl.modelData.indexOf(id) >= 0)
                        return isl.mapToItem(null, isl.width / 2, 0).x + 10
                }
            }
            return -1
        }
        function triggerTray(query, button) {
            const tr = widgetItems["tray"]
            if (tr && typeof tr.trigger === "function") return tr.trigger(query, button)
            return "err: системный трей не размещён на панели монитора " + modelData.name
        }

        anchors { top: true; left: true; right: true }
        margins { top: 6; left: 10; right: 10 }
        implicitHeight: Theme.barHeight
        exclusiveZone: Theme.barHeight
        color: "transparent"
        WlrLayershell.namespace: "qs-bar"
        WlrLayershell.layer: WlrLayer.Top

        // ПКМ по пустому месту — настройка бара
        MouseArea {
            anchors.fill: parent
            z: -10
            acceptedButtons: Qt.RightButton
            onClicked: Modal.toggle("barconfig")
        }

        // ── показывать ли элемент (условия те же, что были у жёстко заданных островов)
        readonly property var activeTop: ToplevelManager.activeToplevel
        function shown(id) {
            switch (id) {
            case "title": return (activeTop?.title ?? "") !== "" && (activeTop?.screens ?? []).some(s => s.name === modelData.name)
            case "recording": return Shot.recording
            case "pomodoro": return Pomodoro.running
            case "weather": return Weather.loaded
            case "media": return Player.label !== ""
            case "tray": return SystemTray.items.values.length > 0
            default: return true
            }
        }

        // ширина, которую может занять заголовок: до центрального острова, за вычетом соседей слева
        readonly property real leftOthers: {
            let w = 0
            const rep = leftZone.rep
            for (let i = 0; i < rep.count; i++) {
                const it = rep.itemAt(i)
                if (it && it.visible && !it.hasTitle) w += it.width + 6
            }
            return w
        }
        readonly property real titleMax: Math.max(110, (bar.width - centerZone.width) / 2 - leftOthers - 40)

        // ── элементы
        Component { id: cTags; Workspaces { screen: bar.modelData } }
        Component { id: cLayout; LayoutIndicator { screen: bar.modelData } }
        Component { id: cTitle; WindowTitle { maxWidth: bar.titleMax } }
        Component {
            id: cLauncher
            IconButton {
                icon: ""
                color: Theme.primary
                onClicked: Modal.toggle("launcher")
                onRightClicked: Modal.toggle("overview")
            }
        }
        Component { id: cClock; Clock {} }
        Component {
            id: cKbd
            Item {
                implicitWidth: kbdText.implicitWidth
                width: implicitWidth
                height: kbdText.implicitHeight
                Text {
                    id: kbdText
                    anchors.centerIn: parent
                    text: Mango.layoutShort
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Mango.switchLayout() }
            }
        }
        Component { id: cRecording; Recording {} }
        Component { id: cPomodoro; PomodoroPill {} }
        Component { id: cWeather; WeatherPill {} }
        Component { id: cMedia; Media {} }
        Component { id: cStats; SystemStats {} }
        Component { id: cTray; Tray { window: bar } }
        Component { id: cPeriph; Peripherals {} }
        Component { id: cNet; NetPill {} }
        Component { id: cAi; AiButton {} }
        Component { id: cAudioSwap; AudioSwapButton {} }
        Component { id: cTuya; TuyaButton {} }
        Component { id: cBell; Bell {} }
        Component { id: cStatus; StatusIcons {} }
        function comp(id) {
            switch (id) {
            case "tags": return cTags
            case "layout": return cLayout
            case "title": return cTitle
            case "launcher": return cLauncher
            case "clock": return cClock
            case "kbd": return cKbd
            case "recording": return cRecording
            case "pomodoro": return cPomodoro
            case "weather": return cWeather
            case "media": return cMedia
            case "stats": return cStats
            case "tray": return cTray
            case "periph": return cPeriph
            case "net": return cNet
            case "ai": return cAi
            case "audioswap": return cAudioSwap
            case "tuya": return cTuya
            case "bell": return cBell
            case "status": return cStatus
            }
            return null
        }

        // зона: ряд островов
        component Zone: RowLayout {
            id: zone
            property string name
            property alias rep: islands
            spacing: 6
            Repeater {
                id: islands
                model: BarLayout.islands(bar.scope, zone.name)
                Island {
                    id: isl
                    required property var modelData            // [id, id, …]
                    readonly property bool hasTitle: modelData.indexOf("title") >= 0
                    readonly property bool hasStatus: modelData.indexOf("status") >= 0
                    visible: modelData.some(id => bar.shown(id))
                    Repeater {
                        model: isl.modelData
                        Loader {
                            id: wloader
                            required property string modelData
                            sourceComponent: bar.comp(modelData)
                            // приватный режим: заголовок окна, трек и погода размыты, под курсором — чётко
                            readonly property bool sensitive: modelData === "title" || modelData === "media" || modelData === "weather"
                            layer.enabled: Session.privacy && sensitive && !privHover.hovered
                            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; saturation: -0.5 }
                            HoverHandler { id: privHover }
                            active: bar.shown(modelData)
                            anchors.verticalCenter: parent?.verticalCenter
                            visible: active
                            onLoaded: {
                                const m = Object.assign({}, bar.widgetItems)
                                m[wloader.modelData] = item
                                bar.widgetItems = m
                            }
                            Component.onDestruction: {
                                const m = Object.assign({}, bar.widgetItems)
                                if (m[wloader.modelData] === item) {
                                    delete m[wloader.modelData]
                                    bar.widgetItems = m
                                }
                            }
                        }
                    }
                    // остров со статусом открывает пункт управления
                    MouseArea {
                        parent: isl
                        enabled: isl.hasStatus
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = isl.mapToItem(null, isl.width / 2, 0)
                            Modal.toggleAt("control", p.x + 10, bar.modelData)
                        }
                    }
                }
            }
        }

        Zone { id: leftZone; name: "left"; anchors { left: parent.left; verticalCenter: parent.verticalCenter } }
        Zone { id: centerZone; name: "center"; anchors.centerIn: parent }
        Zone { id: rightZone; name: "right"; anchors { right: parent.right; verticalCenter: parent.verticalCenter } }

        // «не гасить экран» из быстрых настроек — держит окно бара основного монитора
        IdleInhibitor {
            window: bar
            enabled: Session.idleInhibit && bar.modelData.name === Theme.primaryMonitor
        }
    }
}
