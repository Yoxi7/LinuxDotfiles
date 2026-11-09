pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs

// Пункт управления в духе macOS, три вкладки (Ctrl+Tab / Alt+1…3), внизу всегда — состояние и сессия.
//   Пульт:      связь · «не беспокоить» · «не гасить экран» · задача в фокусе · плеер ·
//               экран (яркость по DDC, ночной свет) · звук с микшером приложений · микрофон · инструменты
//   Органайзер: задачи (Todo, ~/.local/share/quickshell/todos.json) с помодоро · календарь · уведомления
//   Система:    память и диски · топ процессов (с завершением) · перезапуск служб
// Шевроны раскрывают подробности: устройства BT, подключения, выходы/входы звука, мониторы.
ModalWindow {
    id: root
    name: "control"
    dropdown: true
    cardWidth: 420
    cardHeight: col.implicitHeight + 2 * pad

    readonly property int pad: 16
    property string expanded: ""          // "" | bt | net | sink | source | display
    property int tab: Session.ccTab       // 0 управление · 1 органайзер · 2 система · 3 помощник
    onTabChanged: { Session.ccTab = tab; expanded = "" }
    readonly property var tabs: ["Управление", "Органайзер", "Система", "Помощник"]

    onKeyPressed: e => {
        const ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier
        if (ctrl && (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab))
            tab = (tab + (e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier) ? 3 : 1)) % 4
        else if (alt && e.key >= Qt.Key_1 && e.key <= Qt.Key_4) tab = e.key - Qt.Key_1
        else return
        e.accepted = true
    }
    Connections {
        target: Demo
        function onCcExpandChanged() { root.expanded = Demo.ccExpand }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: bt?.enabled ?? false
    readonly property var btDevices: (bt?.devices?.values ?? []).filter(d => d.paired)
                                        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var btConnected: btDevices.filter(d => d.connected)
    // программы, которые сейчас играют звук
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && !n.isSink)

    PwObjectTracker { objects: [root.sink, root.source].concat(root.streams).filter(x => x) }
    Component.onCompleted: { Net.refresh(); Player.refreshVolume(false) }

    function streamName(n) { return n?.properties?.["application.name"] || n?.description || n?.name || "?" }
    function streamIcon(n) {
        const p = n?.properties ?? {}
        const name = p["application.icon-name"] || (p["application.name"] ?? "").toLowerCase()
        return Quickshell.iconPath(DesktopEntries.heuristicLookup(name)?.icon ?? name, "audio-volume-high")
    }
    // инструменты: окно закрывается, инструмент стартует, когда кадр уже чистый
    function tool(cmd) { Modal.close(); Quickshell.execDetached(["bash", "-c", "sleep 0.25; " + cmd]) }

    function run(cmd) { Modal.close(); Quickshell.execDetached(cmd) }
    function toggleExpand(what) { expanded = expanded === what ? "" : what }
    function nodeName(n) { return n?.description || n?.nickname || n?.name || "?" }
    function fmt(sec) {
        const s = Math.max(0, Math.floor(sec))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    // ───────────────────────── строительные блоки

    // модуль — полупрозрачная плашка внутри стеклянной карточки
    component Module: Glass {
        radius: 12                 // концентрично: окно 28 − отступ 16
        // вложенное стекло: плотность держат карточки, а не окно; кромка — та же направленная фаска, но тише
        color: Qt.rgba(0, 0, 0, 0.22)
        sheen: false
        interactive: false
        fresnel: 0.5
        rimColor: Qt.rgba(1, 1, 1, 0.07)
        glintColor: Qt.rgba(1, 1, 1, 0.55)
        rimWidth: 1
    }

    // круглый переключатель: синий, когда включён
    component Round: Rectangle {
        id: round
        property string icon
        property bool on: false
        property int size: 34
        signal clicked
        width: size; height: size; radius: size / 2
        color: on ? Theme.accent : roundMouse.containsMouse ? Theme.border : Theme.strong
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: round.icon
            color: Theme.text
            font { family: Theme.iconFont; pixelSize: round.size * 0.44 }
        }
        MouseArea {
            id: roundMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: round.clicked()
            onPressed: round.scale = 0.92
            onReleased: round.scale = 1
        }
        Behavior on scale { NumberAnimation { duration: Theme.dFast } }
    }

    // строка модуля связи: кружок + название/состояние + шеврон, раскрывающий список
    component ConnRow: Item {
        id: conn
        property string icon
        property string label
        property string sub
        property bool on: false
        property bool canToggle: true
        property string expandKey: ""
        signal toggled
        width: parent?.width ?? 0
        height: 44

        Round {
            id: connRound
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            icon: conn.icon
            on: conn.on
            onClicked: conn.canToggle ? conn.toggled() : root.toggleExpand(conn.expandKey)
        }
        Column {
            anchors { left: connRound.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: conn.label
                color: Theme.text
                font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: conn.sub
                color: Theme.muted
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        MouseArea {
            anchors { left: connRound.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            enabled: conn.expandKey !== ""
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleExpand(conn.expandKey)
        }
    }

    // толстый ползунок как в macOS: значок внутри дорожки, клик по значку — mute
    component BigSlider: Item {
        id: big
        property real value: 0
        property bool muted: false
        property string icon
        property string mutedIcon: icon
        signal moved(real v)
        signal released
        signal iconClicked
        width: parent?.width ?? 0
        height: 24                 // тоньше: ползунки не должны перекрикивать содержимое

        readonly property real shown: muted ? 0 : Math.min(1, value)
        function set(x) { big.moved(Math.max(0, Math.min(1, x / width))) }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.strong
        }
        Rectangle {
            width: Math.max(big.height, big.width * big.shown)
            height: parent.height
            radius: height / 2
            color: big.muted ? Theme.border : Qt.rgba(1, 1, 1, 0.80)
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: e => big.set(e.x)
            onPositionChanged: e => { if (pressed) big.set(e.x) }
            onReleased: big.released()
            onWheel: w => { big.moved(Math.max(0, Math.min(1, big.value + (w.angleDelta.y > 0 ? 0.05 : -0.05)))); big.released() }
        }
        Item {
            width: big.height; height: big.height
            Text {
                anchors.centerIn: parent
                text: big.muted ? big.mutedIcon : big.icon
                color: big.muted ? Theme.danger : Theme.base
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: big.iconClicked() }
        }
        Text {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: big.muted ? "выкл" : Math.round(big.value * 100) + "%"
            color: big.shown > 0.86 ? Theme.base : Theme.muted
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
            font.features: ({ "tnum": 1 })
        }
    }

    // заголовок модуля с кнопкой-шевроном справа
    component Header: Item {
        id: header
        property string title
        property string detail
        property string expandKey
        width: parent?.width ?? 0
        height: 20
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: header.title
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            visible: header.expandKey !== ""
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, header.width * 0.6)
                elide: Text.ElideRight
                text: header.detail
                color: hdrMouse.containsMouse ? Theme.text : Theme.muted
                font { family: Theme.font; pixelSize: 11 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                rotation: root.expanded === header.expandKey ? 90 : 0
                color: hdrMouse.containsMouse ? Theme.text : Theme.muted
                font { family: Theme.iconFont; pixelSize: 10 }
                Behavior on rotation { NumberAnimation { duration: Theme.dFast } }
            }
        }
        MouseArea {
            id: hdrMouse
            anchors.fill: parent
            enabled: header.expandKey !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleExpand(header.expandKey)
        }
    }

    // строка списка (устройство / подключение) с галочкой у выбранного
    component Choice: Rectangle {
        id: choice
        property string icon
        property string label
        property string note
        property bool checked: false
        signal clicked
        width: parent?.width ?? 0
        height: 32
        radius: 10
        color: choiceMouse.containsMouse ? Theme.strong : "transparent"
        Text {
            id: choiceIcon
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 18
            text: choice.icon
            color: choice.checked ? Theme.accent : Theme.muted
            font { family: Theme.iconFont; pixelSize: 13 }
        }
        Text {
            anchors { left: choiceIcon.right; leftMargin: 6; right: noteText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: choice.label
            color: Theme.text
            font { family: Theme.font; pixelSize: 12; weight: choice.checked ? Font.DemiBold : Font.Normal }
        }
        Text {
            id: noteText
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: choice.checked && choice.note === "" ? "" : choice.note
            color: choice.checked ? Theme.accent : Theme.muted
            font { family: choice.note === "" ? Theme.iconFont : Theme.font; pixelSize: 11 }
        }
        MouseArea { id: choiceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: choice.clicked() }
    }

    component Link: Text {
        id: link
        property var cmd
        color: linkMouse.containsMouse ? Theme.text : Theme.muted
        font { family: Theme.font; pixelSize: 11 }
        MouseArea { id: linkMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.run(link.cmd) }
    }

    // раскрывающийся блок: плавно меняет высоту
    component Drawer: Item {
        id: drawer
        property string key
        default property alias content: drawerCol.data
        width: parent?.width ?? 0
        height: root.expanded === key ? drawerCol.implicitHeight + 8 : 0
        visible: height > 0
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
        Column {
            id: drawerCol
            y: 8
            width: parent.width
            spacing: 2
        }
    }


    // подпись раздела внутри модуля
    component Caption: Text {
        leftPadding: 8
        topPadding: 6
        bottomPadding: 2
        color: Theme.faint
        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
    }

    // строка с подписью и тонким ползунком (микшер, мониторы)
    component SliderRow: Item {
        id: sr
        property string label
        property string iconSource
        property string glyph
        property real value
        property string valueText: Math.round(value * 100) + "%"
        signal moved(real v)
        signal released
        width: parent?.width ?? 0
        height: 34
        Image {
            id: srIcon
            visible: sr.iconSource !== ""
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 18; height: 18
            sourceSize { width: 36; height: 36 }
            source: sr.iconSource
        }
        Text {
            visible: sr.glyph !== ""
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: sr.glyph
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 13 }
        }
        Text {
            id: srLabel
            anchors { left: parent.left; leftMargin: 34; verticalCenter: parent.verticalCenter }
            width: 112
            elide: Text.ElideRight
            text: sr.label
            color: Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
        Slider {
            anchors { left: srLabel.right; leftMargin: 8; right: srValue.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            value: sr.value
            onMoved: v => sr.moved(v)
            onReleased: sr.released()
        }
        Text {
            id: srValue
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 40
            horizontalAlignment: Text.AlignRight
            text: sr.valueText
            color: Theme.muted
            font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
        }
    }

    // тихая кнопка: значок + подпись, подсветка фоном
    component Ghost: Rectangle {
        id: gh
        property string icon
        property string label
        property color tint: Theme.text
        signal clicked
        height: 36
        radius: 10
        color: ghMouse.pressed ? Theme.border : ghMouse.containsMouse ? Theme.strong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: gh.icon
                color: gh.tint === Theme.text ? Theme.muted : gh.tint
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: gh.label
                color: gh.tint
                font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
            }
        }
        MouseArea { id: ghMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gh.clicked() }
    }

    // кнопка-значок 28×28 для действий в строках
    component IconAct: Rectangle {
        id: ia
        property string icon
        property color tint: Theme.muted
        property bool armed: false             // первое нажатие опасного действия — подтвердить
        signal clicked
        width: armed ? iaText.implicitWidth + 20 : 28
        height: 28
        radius: 8
        color: armed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22) : iaMouse.containsMouse ? Theme.strong : "transparent"
        Behavior on width { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
        Text {
            id: iaText
            anchors.centerIn: parent
            text: ia.armed ? "завершить" : ia.icon
            color: ia.armed ? Theme.danger : iaMouse.containsMouse ? Theme.text : ia.tint
            font { family: ia.armed ? Theme.font : Theme.iconFont; pixelSize: ia.armed ? 11 : 12; weight: ia.armed ? Font.DemiBold : Font.Normal }
        }
        MouseArea { id: iaMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ia.clicked() }
    }

    // ───────────────────────── раскладка

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
        spacing: 12

        // вкладки
        Rectangle {
            width: col.width
            height: 36
            radius: 12
            color: Theme.weak
            border { width: 1; color: Theme.rimSoft }
            // «линза» выбранной вкладки едет между ними
            Rectangle {
                x: 4 + root.tab * (parent.width - 8) / 4
                y: 4
                width: (parent.width - 8) / 4
                height: parent.height - 8
                radius: 8                      // концентрично: 12 − 4
                color: Theme.strong
                border { width: 1; color: Theme.border }
                Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors { fill: parent; margins: 4 }
                Repeater {
                    model: root.tabs
                    Item {
                        id: tabItem
                        required property string modelData
                        required property int index
                        width: (col.width - 8) / 4
                        height: parent.height
                        Text {
                            anchors.centerIn: parent
                            text: tabItem.modelData
                            color: root.tab === tabItem.index ? Theme.text : tabMouse.containsMouse ? Theme.text : Theme.muted
                            font { family: Theme.font; pixelSize: 13; weight: root.tab === tabItem.index ? Font.DemiBold : Font.Medium }
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = tabItem.index }
                    }
                }
            }
        }

        // страницы: видна одна, смена — короткое затухание со сдвигом в сторону вкладки
        Item {
            id: pages
            width: col.width
            height: [pultPage, orgPage, sysPage, aiPage][root.tab].implicitHeight

            component Page: Column {
                id: page
                required property int index
                width: pages.width
                spacing: 10
                opacity: root.tab === index ? 1 : 0
                visible: opacity > 0
                enabled: root.tab === index
                transform: Translate {
                    x: (page.index - root.tab) * 24
                    Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                }
                Behavior on opacity { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
            }

            Page {
                id: pultPage
                index: 0
            // связь + два больших переключателя
            Row {
                width: col.width
                spacing: 10

                Module {
                    id: connModule
                    width: (col.width - 10) / 2
                    height: connCol.implicitHeight + 20
                    Column {
                        id: connCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 2
                        ConnRow {
                            icon: ""; label: "Wi-Fi"
                            on: Networking.wifiEnabled
                            canToggle: Networking.wifiHardwareEnabled
                            sub: !Networking.wifiHardwareEnabled ? "нет адаптера" : Net.wifi?.name ?? (Networking.wifiEnabled ? "вкл" : "выкл")
                            expandKey: "net"
                            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        }
                        ConnRow {
                            icon: ""; label: "Bluetooth"
                            on: root.btOn
                            canToggle: root.bt !== null
                            sub: !root.bt ? "нет адаптера" : !root.btOn ? "выкл"
                                : root.btConnected.map(d => d.name).join(", ") || "вкл"
                            expandKey: "bt"
                            onToggled: root.bt.enabled = !root.bt.enabled
                        }
                        ConnRow {
                            icon: Net.vpns.length > 0 ? "" : "\u{f0200}"
                            label: Net.vpns.length > 0 ? "VPN" : "Сеть"
                            on: Net.vpns.length > 0 || !!Net.wired
                            canToggle: false
                            sub: Net.vpns.length > 0 ? Net.vpns.map(v => v.name).join(", ")
                                : Net.wired?.name ?? Net.wifi?.name ?? "нет подключения"
                            expandKey: "net"
                        }
                    }
                }

                Column {
                    width: (col.width - 10) / 2
                    spacing: 10

                    component BigToggle: Module {
                        id: tgl
                        property string icon
                        property string label
                        property string sub
                        property bool on: false
                        signal clicked
                        width: parent?.width ?? 0
                        height: (connModule.height - 20) / 3
                        color: on ? Qt.rgba(1, 1, 1, 0.12) : tglMouse.containsMouse ? Theme.strong : Theme.weak
                        Round {
                            id: tglRound
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            icon: tgl.icon
                            on: tgl.on
                            onClicked: tgl.clicked()
                        }
                        Column {
                            anchors { left: tglRound.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: tgl.label
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: tgl.sub
                                color: Theme.muted
                                font { family: Theme.font; pixelSize: 11 }
                            }
                        }
                        MouseArea { id: tglMouse; anchors.fill: parent; z: -1; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tgl.clicked() }
                    }

                    BigToggle {
                        icon: Session.dnd ? "" : ""
                        label: "Не беспокоить"
                        sub: Session.dnd ? "только важные" : "все уведомления"
                        on: Session.dnd
                        onClicked: Session.dnd = !Session.dnd
                    }
                    BigToggle {
                        icon: ""
                        label: "Не гасить экран"
                        sub: Session.idleInhibit ? "экран не уснёт" : "по таймеру"
                        on: Session.idleInhibit
                        onClicked: Session.idleInhibit = !Session.idleInhibit
                    }
                    BigToggle {
                        icon: "\u{f00ae}"
                        label: "Размытие"
                        sub: Session.blurOff ? "выключено везде" : "окна и оболочка"
                        on: !Session.blurOff
                        onClicked: Session.blurOff = !Session.blurOff
                    }
                }
            }

            // подробности связи
            Module {
                width: col.width
                height: root.expanded === "bt" || root.expanded === "net" ? detailCol.implicitHeight + 20 : 0
                visible: height > 0
                clip: true
                Behavior on height { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

                Column {
                    id: detailCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 2

                    Header { title: root.expanded === "bt" ? "Устройства Bluetooth" : "Подключения"; expandKey: "" }
                    Item { width: 1; height: 4 }

                    Repeater {
                        model: root.expanded === "bt" && root.btOn ? root.btDevices : []
                        Choice {
                            required property var modelData
                            icon: ""
                            label: modelData.name + (modelData.batteryAvailable ? "  ·  " + Math.round(modelData.battery * 100) + "%" : "")
                            checked: modelData.connected
                            note: modelData.state === BluetoothDeviceState.Connecting ? "подключение…"
                                : modelData.state === BluetoothDeviceState.Disconnecting ? "отключение…"
                                : modelData.connected ? "отключить" : "подключить"
                            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                        }
                    }
                    Text {
                        visible: root.expanded === "bt" && (!root.btOn || root.btDevices.length === 0)
                        text: root.btOn ? "нет сопряжённых устройств" : "Bluetooth выключен"
                        color: Theme.muted
                        leftPadding: 8
                        font { family: Theme.font; pixelSize: 12 }
                    }

                    Repeater {
                        model: root.expanded === "net" ? Net.active : []
                        Choice {
                            required property var modelData
                            readonly property bool vpn: /^(vpn|wireguard|tun)$/.test(modelData.type)
                            icon: vpn ? "" : modelData.type === "802-11-wireless" ? "" : "\u{f0200}"
                            label: modelData.name
                            note: modelData.device
                            checked: true
                        }
                    }
                    Text {
                        visible: root.expanded === "net" && Net.active.length === 0
                        text: "нет подключения"
                        color: Theme.danger
                        leftPadding: 8
                        font { family: Theme.font; pixelSize: 12 }
                    }

                    Item {
                        width: parent.width; height: 24
                        Link {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: root.expanded === "bt" ? "Настройки Bluetooth…" : "Настройки сети…"
                            cmd: root.expanded === "bt" ? ["blueman-manager"] : ["nm-connection-editor"]
                        }
                    }
                }
            }

            // задача в фокусе и помодоро — тонкой строкой; клик — в органайзер
            Module {
                width: col.width
                visible: Todo.current !== null || Pomodoro.running
                height: visible ? 44 : 0
                color: focusMouse.containsMouse ? Theme.strong : Theme.weak
                MouseArea { id: focusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = 1 }
                Text {
                    id: focusLabel
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: Pomodoro.running ? Pomodoro.label : "Сейчас"
                    color: Pomodoro.running ? Theme.primary : Theme.faint
                    font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                }
                Text {
                    anchors { left: focusLabel.right; leftMargin: 12; right: focusDone.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: Pomodoro.running ? (Pomodoro.task || "Помодоро") : Todo.current?.text ?? ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13 }
                }
                IconAct {
                    id: focusDone
                    visible: Todo.current !== null
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    icon: "\uf00c"
                    onClicked: Todo.toggle(Todo.current.id)
                }
            }

            // сейчас играет
            Module {
                width: col.width
                visible: Player.available
                height: visible ? mediaCol.implicitHeight + 24 : 0

                Column {
                    id: mediaCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 12
                        Cover { size: 56; radius: 12; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            width: parent.width - 56 - 12 - controls.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: Player.title
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: Player.artist
                                color: Theme.muted
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: Player.playerName
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 10; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
                            }
                        }
                        Row {
                            id: controls
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            component MediaButton: Text {
                                id: mb
                                signal clicked
                                width: 32; height: 32
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: mbMouse.containsMouse ? Theme.text : Theme.muted
                                font { family: Theme.iconFont; pixelSize: 15 }
                                MouseArea { id: mbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.clicked() }
                            }
                            MediaButton { text: ""; onClicked: Player.previous() }
                            MediaButton { text: Player.playing ? "" : ""; font.pixelSize: 19; color: Theme.text; onClicked: Player.toggle() }
                            MediaButton { text: ""; onClicked: Player.next() }
                        }
                    }

                    // прогресс трека
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: Player.duration > 0
                        Rectangle {
                            width: parent.width; height: 4; radius: 2
                            color: Theme.strong
                            Rectangle {
                                width: parent.width * Math.min(1, Player.livePosition / Math.max(1, Player.duration))
                                height: parent.height; radius: 2
                                color: Theme.muted
                                Behavior on width { NumberAnimation { duration: 1000 } }
                            }
                        }
                        Item {
                            width: parent.width; height: 12
                            Text { text: root.fmt(Player.livePosition); color: Theme.faint; font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) } }
                            Text { anchors.right: parent.right; text: "-" + root.fmt(Player.duration - Player.livePosition); color: Theme.faint; font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) } }
                        }
                    }

                    BigSlider {
                        icon: "\u{f075a}"
                        value: Player.volume
                        onMoved: v => Player.setVolume(v)
                    }
                }
            }

            // экран: яркость (DDC) и ночной свет
            Module {
                width: col.width
                visible: Display.monitors.length > 0 || Display.nightLight
                height: visible ? dispCol.implicitHeight + 24 : 0
                Column {
                    id: dispCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    Header {
                        title: "Экран"
                        detail: Display.nightLight ? "ночной свет · " + Session.nightTemp + " K" : Display.monitors.length + " монитора"
                        expandKey: "display"
                    }
                    Item {
                        width: parent.width
                        height: 24
                        BigSlider {
                            anchors { left: parent.left; right: nightBtn.left; rightMargin: 8 }
                                icon: "\uf185"
                            value: Display.average
                            onMoved: v => Display.setAll(v)
                            onReleased: Display.commit()
                        }
                        Round {
                            id: nightBtn
                            anchors.right: parent.right
                            size: 24
                            icon: "\uf186"
                            on: Display.nightLight
                            onClicked: Display.setNightLight(!Display.nightLight)
                        }
                    }
                    Drawer {
                        key: "display"
                        Repeater {
                            model: Display.monitors
                            SliderRow {
                                required property var modelData
                                glyph: "\uf108"
                                label: modelData.output || modelData.model
                                value: (Display.values[modelData.bus] ?? 0) / 100
                                onMoved: v => Display.set(modelData.bus, v)
                            onReleased: Display.commit()
                            }
                        }
                        SliderRow {
                            glyph: "\uf186"
                            label: "Ночной свет"
                            value: (Session.nightTemp - 2500) / 3500
                            valueText: Session.nightTemp + " K"
                            onMoved: v => Display.setNightTemp(2500 + v * 3500)
                        }
                    }
                }
            }

            // звук
            Module {
                width: col.width
                height: soundCol.implicitHeight + 24
                Column {
                    id: soundCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    Header { title: "Звук"; detail: root.nodeName(root.sink); expandKey: "sink" }
                    BigSlider {
                        icon: (root.sink?.audio?.volume ?? 0) > 0.5 ? "" : ""
                        mutedIcon: ""
                        value: root.sink?.audio?.volume ?? 0
                        muted: root.sink?.audio?.muted ?? false
                        onMoved: v => { if (root.sink?.audio) root.sink.audio.volume = v }
                        onIconClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
                    }
                    Drawer {
                        key: "sink"
                        Caption { visible: root.streams.length > 0; text: "Приложения" }
                        Repeater {
                            model: root.streams
                            SliderRow {
                                required property var modelData
                                iconSource: root.streamIcon(modelData)
                                label: root.streamName(modelData)
                                value: modelData.audio?.volume ?? 0
                                valueText: modelData.audio?.muted ? "выкл" : Math.round(value * 100) + "%"
                                onMoved: v => { if (modelData.audio) modelData.audio.volume = v }
                            }
                        }
                        Caption { text: "Выход" }
                        Repeater {
                            model: root.sinks
                            Choice {
                                required property var modelData
                                icon: ""
                                label: root.nodeName(modelData)
                                checked: modelData === root.sink
                                onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            }
                        }
                        Item {
                            width: parent.width; height: 24
                            Link {
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: "Все устройства…"
                                cmd: ["qs", "-c", "lite", "ipc", "call", "modal", "toggle", "audio"]
                            }
                        }
                    }
                }
            }

            // микрофон
            Module {
                width: col.width
                height: micCol.implicitHeight + 24
                Column {
                    id: micCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    Header { title: "Микрофон"; detail: root.nodeName(root.source); expandKey: "source" }
                    BigSlider {
                        icon: ""
                        mutedIcon: ""
                        value: root.source?.audio?.volume ?? 0
                        muted: root.source?.audio?.muted ?? false
                        onMoved: v => { if (root.source?.audio) root.source.audio.volume = v }
                        onIconClicked: if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted
                    }
                    Drawer {
                        key: "source"
                        Repeater {
                            model: root.sources
                            Choice {
                                required property var modelData
                                icon: ""
                                label: root.nodeName(modelData)
                                checked: modelData === root.source
                                onClicked: Pipewire.preferredDefaultAudioSource = modelData
                            }
                        }
                    }
                }
            }

            // инструменты
            Row {
                width: col.width
                spacing: 4
                Ghost { width: (col.width - 8) / 3; icon: "\uf1fb"; label: "Пипетка"
                        onClicked: root.tool('c=$(hyprpicker -a -f hex) && [ -n "$c" ] && notify-send -a "Пипетка" "Цвет скопирован" "$c"') }
                Ghost { width: (col.width - 8) / 3; icon: "\uf031"; label: "Текст с экрана"; onClicked: root.tool("quickshell ipc call region ocr") }
                Ghost { width: (col.width - 8) / 3; icon: "\uf030"; label: "Скриншот"; onClicked: root.tool("quickshell ipc call region menu") }
            }
            }

            Page {
                id: orgPage
                index: 1
            // новая задача
            Rectangle {
                width: col.width
                height: 40
                radius: 12
                color: Theme.weak
                border { width: 1; color: todoInput.activeFocus ? Theme.primary : Theme.rimSoft }
                Text {
                    id: plus
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: ""
                    color: Theme.muted
                    font { family: Theme.iconFont; pixelSize: 12 }
                }
                TextInput {
                    id: todoInput
                    anchors { left: plus.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Theme.text
                    selectionColor: Theme.primary
                    clip: true
                    font { family: Theme.font; pixelSize: 13 }
                    Keys.onReturnPressed: { Todo.add(text); text = "" }
                    Keys.onEnterPressed: { Todo.add(text); text = "" }
                    Text {
                        visible: !todoInput.text
                        text: "Новая задача — Enter, чтобы добавить"
                        color: Theme.faint
                        font: todoInput.font
                    }
                }
            }

            // помодоро идёт
            Module {
                width: col.width
                visible: Pomodoro.running
                height: visible ? 52 : 0
                Item {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    Text {
                        id: pomoTime
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: Pomodoro.label
                        color: Theme.primary
                        font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                    }
                    Text {
                        anchors { left: pomoTime.right; leftMargin: 14; right: pomoStop.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: Pomodoro.task || "Помодоро"
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 13 }
                    }
                    Ghost {
                        id: pomoStop
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 76
                        icon: ""
                        label: "Стоп"
                        onClicked: Pomodoro.stop()
                    }
                }
                // оставшееся время — тонкая линия по низу
                Rectangle {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 1; leftMargin: 12 }
                    width: (parent.width - 24) * Pomodoro.progress
                    height: 2
                    radius: 1
                    color: Theme.primary
                }
            }

            // список задач
            Module {
                width: col.width
                height: todoCol.implicitHeight + 12
                Column {
                    id: todoCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                    Text {
                        visible: Todo.items.length === 0
                        width: parent.width
                        padding: 12
                        text: "Задач нет. Впиши первую в поле выше."
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    ListView {
                        id: todoList
                        width: parent.width
                        height: Math.min(contentHeight, 7 * 36)
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        model: Todo.items
                        delegate: Rectangle {
                            id: task
                            required property var modelData
                            required property int index
                            readonly property bool first: !modelData.done && index === 0
                            width: todoList.width
                            height: 36
                            radius: 8
                            color: taskMouse.containsMouse ? Theme.strong : "transparent"
                            MouseArea {
                                id: taskMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: e => e.button === Qt.RightButton ? Todo.remove(task.modelData.id) : Todo.toggle(task.modelData.id)
                            }
                            // чекбокс
                            Rectangle {
                                id: box
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 18; height: 18; radius: 9
                                color: task.modelData.done ? Theme.accent : "transparent"
                                border { width: task.modelData.done ? 0 : 1.5; color: task.first ? Theme.primary : Theme.muted }
                                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                                Text {
                                    anchors.centerIn: parent
                                    visible: task.modelData.done
                                    text: ""
                                    color: Theme.text
                                    font { family: Theme.iconFont; pixelSize: 9 }
                                }
                            }
                            Text {
                                anchors { left: box.right; leftMargin: 12; right: acts.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: task.modelData.text
                                color: task.modelData.done ? Theme.faint : Theme.text
                                font { family: Theme.font; pixelSize: 13; strikeout: task.modelData.done; weight: task.first ? Font.Medium : Font.Normal }
                                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            }
                            Row {
                                id: acts
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                opacity: taskMouse.containsMouse || actMouse.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                                HoverHandler { id: actMouse }
                                IconAct { visible: !task.modelData.done; icon: ""; onClicked: { Pomodoro.start(task.modelData.text); Todo.focus(task.modelData.id) } }
                                IconAct { visible: !task.modelData.done && !task.first; icon: ""; onClicked: Todo.focus(task.modelData.id) }
                                IconAct { icon: ""; onClicked: Todo.remove(task.modelData.id) }
                            }
                        }
                    }
                    Item {
                        visible: Todo.finished.length > 0
                        width: parent.width
                        height: 30
                        Text {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "Выполнено: " + Todo.finished.length
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                        }
                        Link {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "Очистить"
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Todo.clearDone() }
                        }
                    }
                }
            }

            // календарь месяца
            Module {
                id: cal
                width: col.width
                height: calCol.implicitHeight + 24
                property date shownMonth: new Date()
                readonly property date today: new Date()
                readonly property var days: {
                    const y = shownMonth.getFullYear(), m = shownMonth.getMonth()
                    const first = new Date(y, m, 1)
                    const lead = (first.getDay() + 6) % 7          // с понедельника
                    const n = new Date(y, m + 1, 0).getDate()
                    const out = []
                    for (let i = 0; i < lead; i++) out.push(0)
                    for (let d = 1; d <= n; d++) out.push(d)
                    while (out.length % 7) out.push(0)
                    return out
                }
                readonly property bool isThisMonth: shownMonth.getFullYear() === today.getFullYear() && shownMonth.getMonth() === today.getMonth()
                function shift(d) { shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + d, 1) }

                Column {
                    id: calCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    Item {
                        width: parent.width
                        height: 24
                        Text {
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            text: Qt.locale("ru_RU").standaloneMonthName(cal.shownMonth.getMonth()).replace(/^./, c => c.toUpperCase()) + " " + cal.shownMonth.getFullYear()
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            IconAct { icon: ""; onClicked: cal.shift(-1) }
                            IconAct { visible: !cal.isThisMonth; icon: ""; tint: Theme.faint; onClicked: cal.shownMonth = new Date() }
                            IconAct { icon: ""; onClicked: cal.shift(1) }
                        }
                    }
                    Grid {
                        columns: 7
                        width: parent.width
                        Repeater {
                            model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                            Text {
                                required property string modelData
                                required property int index
                                width: calCol.width / 7
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: index >= 5 ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.7) : Theme.faint
                                font { family: Theme.font; pixelSize: 11 }
                            }
                        }
                        Repeater {
                            model: cal.days
                            Item {
                                id: day
                                required property int modelData
                                required property int index
                                readonly property bool isToday: cal.isThisMonth && modelData === cal.today.getDate()
                                width: calCol.width / 7
                                height: 30
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 28; height: 28; radius: 14
                                    visible: day.isToday
                                    color: Theme.accent
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: day.modelData > 0
                                    text: day.modelData
                                    color: day.isToday ? Theme.text : day.index % 7 >= 5 ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.85) : Theme.text
                                    font { family: Theme.font; pixelSize: 12; weight: day.isToday ? Font.Bold : Font.Normal; features: ({ "tnum": 1 }) }
                                }
                            }
                        }
                    }
                }
            }

            // последние уведомления
            Module {
                width: col.width
                height: notifCol.implicitHeight + 24
                Column {
                    id: notifCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 4
                    Item {
                        width: parent.width
                        height: 22
                        Text {
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            text: "Уведомления"
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            spacing: 14
                            Link { visible: Notifs.count > 0; text: "Очистить"; MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.clearAll() } }
                            Link { visible: Notifs.count > 0; text: Notifs.count > 3 ? "Все " + Notifs.count + "…" : "Все…"; MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: Modal.toggle("notifications") } }
                        }
                    }
                    Text {
                        visible: Notifs.count === 0
                        leftPadding: 4
                        text: "Новых нет"
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    Repeater {
                        model: Notifs.history.slice(0, 3)
                        Rectangle {
                            id: nrow
                            required property var modelData
                            width: notifCol.width
                            height: 44
                            radius: 8
                            color: nMouse.containsMouse ? Theme.strong : "transparent"
                            MouseArea { id: nMouse; anchors.fill: parent; hoverEnabled: true; onClicked: nrow.modelData.dismiss() }
                            Column {
                                anchors { left: parent.left; leftMargin: 8; right: nTime.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: nrow.modelData.summary || nrow.modelData.appName
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (nrow.modelData.appName || "") + (nrow.modelData.body ? " · " + nrow.modelData.body.replace(/<[^>]*>/g, "").replace(/\s+/g, " ") : "")
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                            }
                            Text {
                                id: nTime
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: Notifs.timeOf(nrow.modelData)
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                            }
                        }
                    }
                }
            }
            }

            Page {
                id: sysPage
                index: 2
                property var procs: []           // [{ pid, name, cpu, mem }]
                property var disks: []           // [{ mount, size, used }]
                property int armedPid: -1
                property int termedPid: -1       // этому процессу уже отправлен SIGTERM
                onVisibleChanged: if (!visible) { armedPid = -1; termedPid = -1 }

                // top: второй замер мгновенный (первый — среднее с запуска)
                Process {
                    id: procProc
                    command: ["bash", "-c", "HOME=/nonexistent XDG_CONFIG_HOME=/nonexistent top -b -n 2 -d 0.5 -w 512 -o %CPU | awk '/^top -/{n++} n==2 && $1 ~ /^[0-9]+$/ {c=$12; for(i=13;i<=NF;i++) c=c\" \"$i; print $1\"\\t\"$9\"\\t\"$10\"\\t\"c}' | head -n 6"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            sysPage.procs = text.trim().split("\n").filter(l => l).map(l => {
                                const f = l.split("\t")
                                return { pid: parseInt(f[0]), cpu: parseFloat(f[1].replace(",", ".")) || 0, mem: parseFloat(f[2].replace(",", ".")) || 0, name: f[3] ?? "?" }
                            })
                        }
                    }
                }
                Timer {
                    id: procTimer
                    interval: 2500
                    repeat: true
                    running: sysPage.visible
                    triggeredOnStart: true
                    onTriggered: {
                        if (!procProc.running) procProc.running = true
                        if (!sysPage.disks.length && !diskProc.running) diskProc.running = true
                    }
                }
                Process {
                    id: diskProc
                    command: ["df", "-B1", "--output=target,size,used", "/", "/home"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const seen = new Set(), out = []
                            for (const l of text.trim().split("\n").slice(1)) {
                                const f = l.trim().split(/\s+/)
                                if (f.length < 3 || seen.has(f[0])) continue
                                seen.add(f[0])
                                out.push({ mount: f[0], size: parseFloat(f[1]), used: parseFloat(f[2]) })
                            }
                            sysPage.disks = out
                        }
                    }
                }
            // память и диски
            Module {
                width: col.width
                height: memCol.implicitHeight + 24
                Column {
                    id: memCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 12
                    component Usage: Column {
                        id: use
                        property string label
                        property string detail
                        property real frac
                        width: parent?.width ?? 0
                        spacing: 6
                        Item {
                            width: parent.width
                            height: 16
                            Text {
                                text: use.label
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                            }
                            Text {
                                anchors.right: parent.right
                                text: use.detail
                                color: Theme.muted
                                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.strong
                            Rectangle {
                                width: parent.width * Math.min(1, use.frac)
                                height: parent.height
                                radius: 2
                                color: use.frac >= 0.9 ? Theme.danger : Theme.accent
                                Behavior on width { NumberAnimation { duration: Theme.dSlow; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    Usage {
                        label: "Память"
                        detail: SysInfo.memUsed.toFixed(1) + " из " + SysInfo.memTotal.toFixed(0) + " ГиБ"
                        frac: SysInfo.mem / 100
                    }
                    Repeater {
                        model: sysPage.disks
                        Usage {
                            required property var modelData
                            label: modelData.mount === "/" ? "Диск /" : "Диск " + modelData.mount
                            detail: (modelData.used / 1073741824).toFixed(0) + " из " + (modelData.size / 1073741824).toFixed(0) + " ГиБ"
                            frac: modelData.used / Math.max(1, modelData.size)
                        }
                    }
                }
            }

            // каждое ядро: загрузка, частота, температура — раз в 100 мс
            Module {
                width: col.width
                height: ccCores.implicitHeight + 24
                CoreGrid {
                    id: ccCores
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                }
            }

            // процессы
            Module {
                width: col.width
                height: procCol.implicitHeight + 24
                Column {
                    id: procCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 2
                    Item {
                        width: parent.width
                        height: 24
                        Text {
                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                            text: "Процессы"
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 44; verticalCenter: parent.verticalCenter }
                            Text { width: 52; horizontalAlignment: Text.AlignRight; text: "CPU"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                            Text { width: 52; horizontalAlignment: Text.AlignRight; text: "RAM"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                        }
                    }
                    Text {
                        visible: sysPage.procs.length === 0
                        leftPadding: 4
                        text: "Подсчёт…"
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    Repeater {
                        model: sysPage.procs
                        Rectangle {
                            id: proc
                            required property var modelData
                            width: procCol.width
                            height: 32
                            radius: 8
                            color: pMouse.containsMouse ? Theme.strong : "transparent"
                            MouseArea { id: pMouse; anchors.fill: parent; hoverEnabled: true }
                            Text {
                                anchors { left: parent.left; leftMargin: 8; right: nums.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: proc.modelData.name
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 12 }
                            }
                            Row {
                                id: nums
                                anchors { right: kill.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: 52
                                    horizontalAlignment: Text.AlignRight
                                    text: proc.modelData.cpu.toFixed(1) + "%"
                                    color: proc.modelData.cpu >= 50 ? Theme.warning : Theme.text
                                    font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                                }
                                Text {
                                    width: 52
                                    horizontalAlignment: Text.AlignRight
                                    text: proc.modelData.mem.toFixed(1) + "%"
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                                }
                            }
                            // завершение: первый клик — подтверждение, второй — SIGTERM, третий (если процесс жив) — kill -9
                            IconAct {
                                id: kill
                                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                icon: ""
                                armed: sysPage.armedPid === proc.modelData.pid
                                opacity: pMouse.containsMouse || armed || hovered ? 1 : 0
                                readonly property bool hovered: killHover.hovered
                                HoverHandler { id: killHover }
                                onClicked: {
                                    const pid = String(proc.modelData.pid)
                                    if (!armed) sysPage.armedPid = proc.modelData.pid
                                    else if (sysPage.termedPid !== proc.modelData.pid) {
                                        Quickshell.execDetached(["kill", "-15", pid])
                                        sysPage.termedPid = proc.modelData.pid
                                        procTimer.restart()
                                    } else { Quickshell.execDetached(["kill", "-9", pid]); sysPage.armedPid = -1; sysPage.termedPid = -1; procTimer.restart() }
                                }
                            }
                        }
                    }
                }
            }

            // службы
            Row {
                width: col.width
                spacing: 4
                Ghost { width: (col.width - 8) / 3; icon: ""; label: "Звук"
                        onClicked: Quickshell.execDetached(["systemctl", "--user", "restart", "pipewire", "pipewire-pulse", "wireplumber"]) }
                Ghost { width: (col.width - 8) / 3; icon: ""; label: "Оболочка"; onClicked: { Modal.close(); Quickshell.execDetached(["sh", "-c", "killall quickshell; quickshell -c lite &"]) } }
                Ghost { width: (col.width - 8) / 3; icon: ""; label: "Конфиг mango"; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "reload_config"]) }
            }
            Text {
                width: col.width
                horizontalAlignment: Text.AlignHCenter
                text: "перезапуск служб"
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
            }

            // ИИ-помощник: тот же чат, что в окне из бара
            Page {
                id: aiPage
                index: 3
                Module {
                    width: col.width
                    height: 640
                    AssistantView {
                        anchors { fill: parent; margins: 14 }
                        compact: true
                        active: root.tab === 3 && !Modal.closing
                    }
                }
            }
        }

        // нижняя строка: состояние системы и сессия
        Item {
            width: col.width
            height: 36

            // состояние — клик открывает вкладку «Система»
            Row {
                id: stats
                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 12
                component Stat: Row {
                    property string icon
                    property string value
                    property bool hot: false
                    spacing: 5
                    Text { text: parent.icon; color: parent.hot ? Theme.danger : Theme.faint; font { family: Theme.iconFont; pixelSize: 11 } }
                    Text { text: parent.value; color: parent.hot ? Theme.danger : Theme.muted; font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) } }
                }
                Stat { icon: ""; value: SysInfo.cpu + "%"; hot: SysInfo.cpu >= 90 }
                Stat { icon: "\u{f035b}"; value: SysInfo.mem + "%"; hot: SysInfo.mem >= 90 }
                Stat { icon: ""; value: SysInfo.temp + "°"; hot: SysInfo.temp >= 85; visible: SysInfo.temp > 0 }
                Stat { icon: "\u{f08ae}"; value: Math.round(Cooling.gpuTemp) + "°"; hot: Cooling.gpuTemp >= 83; visible: Cooling.available }
            }

            MouseArea {
                anchors { left: stats.left; right: stats.right; top: parent.top; bottom: parent.bottom; margins: -4 }
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tab = 2
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Round { size: 32; icon: ""; onClicked: root.run(["loginctl", "lock-session"]) }
                Round { size: 32; icon: ""; onClicked: root.run(["mmsg", "dispatch", "quit"]) }
                Round { size: 32; icon: ""; onClicked: Modal.toggle("power") }
            }
        }
    }
}
