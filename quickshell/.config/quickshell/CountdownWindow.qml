pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Экран обратного отсчёта (см. Countdown.qml). На каждом мониторе — его же кадр, который
// плавно расплывается (mango с blur_optimized размывает под слоями только обои, поэтому кадр
// снимаем grim и размываем сами). На основном мониторе — кольцо, секунды и кнопки,
// на остальных — короткая подпись.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property string mainMon: (Demo.active && Demo.screenName !== "") ? Demo.screenName : Theme.primaryMonitor
            readonly property bool main: modelData.name === mainMon || Quickshell.screens.length === 1
            readonly property string shot: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-countdown/" + modelData.name + ".png"
            readonly property color tint: Countdown.action?.tint ?? Theme.primary
            property bool ready: false
            readonly property bool shown: ready && !Countdown.closing

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "qs-countdown"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // кадр монитора; окно пока прозрачное — в снимок не попадает
            Process {
                running: true
                command: ["bash", "-c", 'mkdir -p "$(dirname "$2")" && grim -s 0.5 -o "$1" "$2"', "cd", win.modelData.name, win.shot]
                onExited: win.ready = true
            }

            // ── фон: кадр расплывается и темнеет; к концу отсчёта — ещё темнее
            Item {
                anchors.fill: parent
                opacity: win.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: win.shown ? 260 : 300; easing.type: Easing.OutCubic } }

                Image {
                    id: frame
                    anchors.fill: parent
                    source: win.ready ? "file://" + win.shot : ""
                    cache: false
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: frame
                    visible: frame.status === Image.Ready
                    blurEnabled: true
                    blurMax: 64
                    blur: win.shown ? 1 : 0
                    saturation: win.shown ? -0.35 : 0
                    brightness: win.shown ? -0.08 : 0
                    scale: win.shown ? 1.04 : 1
                    Behavior on blur { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                    Behavior on saturation { NumberAnimation { duration: 700 } }
                    Behavior on brightness { NumberAnimation { duration: 700 } }
                    Behavior on scale { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                }
                // затемнение плавно густеет весь отсчёт
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: 0.18 + 0.30 * (1 - Countdown.progress)
                }
                MouseArea { anchors.fill: parent }     // клики мимо ничего не делают
            }

            // ── клавиатура (только основной монитор); первые 400 мс — мимо, чтобы не поймать дребезг
            FocusScope {
                anchors.fill: parent
                focus: win.main
                property bool armed: false
                Timer { interval: 400; running: true; onTriggered: parent.armed = true }
                Keys.onPressed: e => {
                    e.accepted = true
                    if (!armed) return
                    if (e.key === Qt.Key_Escape) Countdown.cancel()
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) Countdown.now()
                    else if (!e.isAutoRepeat) {
                        // та же буква, что выбрала действие (P, S, R, E, B), — сократить ожидание до 5 секунд
                        const letters = { [Qt.Key_E]: "E", [Qt.Key_S]: "S", [Qt.Key_R]: "R", [Qt.Key_B]: "B", [Qt.Key_P]: "P" }
                        const byCode = { 26: "E", 39: "S", 27: "R", 56: "B", 33: "P" }
                        const k = letters[e.key] ?? byCode[e.nativeScanCode]
                        if (k && k === Countdown.action?.key) Countdown.expedite()
                    }
                }
            }

            // ── основной монитор: название, большая цифра, тонкая линия; подсказка внизу
            Column {
                id: stage
                visible: win.main
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -20
                spacing: 10
                opacity: win.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: win.shown ? 600 : 200; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: win.shown ? 0 : 14
                    Behavior on y { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (Countdown.action?.label ?? "").toUpperCase()
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font { family: Theme.font; pixelSize: 15; weight: Font.Medium; letterSpacing: 6 }
                }

                // цифра-«счётчик»: старая уезжает вверх за край, новая выезжает снизу
                Item {
                    id: drum
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 320
                    height: 176
                    clip: true
                    property int value: Countdown.seconds
                    property int shown: value
                    property real shift: 0                 // 0 — на месте, 1 — сдвиг на высоту
                    onValueChanged: { roll.stop(); prevDigit.text = String(shown); shown = value; roll.start() }
                    NumberAnimation {
                        id: roll
                        target: drum; property: "shift"
                        from: 1; to: 0
                        duration: 520
                        easing.type: Easing.OutQuart
                    }
                    Text {
                        id: prevDigit
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (drum.height - height) / 2 - drum.height * (1 - drum.shift)
                        opacity: drum.shift
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 200; weight: Font.Normal; features: ({ "tnum": 1 }) }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (drum.height - height) / 2 + drum.height * drum.shift
                        opacity: 1 - drum.shift * 0.6
                        text: drum.shown
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 200; weight: Font.Normal; features: ({ "tnum": 1 }) }
                    }
                }

                // время — линия, сжимающаяся к центру
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220
                    height: 12
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 2
                        radius: 1
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * Countdown.progress
                        height: 2
                        radius: 1
                        color: win.tint
                    }
                }
            }

            // подсказка внизу: слова кликабельны
            Row {
                visible: win.main
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 72 }
                spacing: 28
                opacity: win.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

                component Hint: Item {
                    id: hint
                    property string keyName
                    property string label
                    signal clicked
                    implicitWidth: hintRow.implicitWidth
                    implicitHeight: hintRow.implicitHeight
                    Row {
                        id: hintRow
                        spacing: 8
                        Text {
                            text: hint.keyName
                            color: hm.containsMouse ? Theme.text : Qt.rgba(1, 1, 1, 0.75)
                            font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                        }
                        Text {
                            text: hint.label
                            color: hm.containsMouse ? Theme.text : Qt.rgba(1, 1, 1, 0.4)
                            font { family: Theme.font; pixelSize: 14 }
                        }
                    }
                    MouseArea {
                        id: hm
                        anchors { fill: parent; margins: -10 }
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hint.clicked()
                    }
                }
                Hint { keyName: "Esc"; label: "отменить"; onClicked: Countdown.cancel() }
                Text { text: "·"; color: Qt.rgba(1, 1, 1, 0.25); font { family: Theme.font; pixelSize: 14 } }
                Hint { keyName: "Enter"; label: "сейчас"; onClicked: Countdown.now() }
                Text { text: "·"; color: Qt.rgba(1, 1, 1, 0.25); font { family: Theme.font; pixelSize: 14 } }
                Hint { keyName: Countdown.action?.key ?? ""; label: "ещё раз — 5 с"; onClicked: Countdown.expedite() }
            }
        }
    }
}
