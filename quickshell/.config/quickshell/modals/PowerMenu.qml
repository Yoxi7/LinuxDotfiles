pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Повер-меню: ←/→ или буква (L E S R B P) — выбрать, Enter / пробел / клик — выполнить, Esc — отмена.
// Буквы сами ничего не запускают, а первые 300 мс после открытия клавиши игнорируются:
// если меню открылось посреди набора текста, напечатанное ничего не сделает.
// «Перезагрузка», когда на ней курсор или выбор, делится пополам:
// сверху обычная перезагрузка, снизу — в BIOS (UEFI); ↑/↓ — между половинками.
ModalWindow {
    id: root
    name: "power"
    cardWidth: actions.length * 132 + (actions.length - 1) * 12 + 24
    cardHeight: 172                       // отступ 12: плитки 16 + 12 = радиус окна 28

    readonly property var actions: [
        { key: "L", icon: "", label: "Блокировка", cmd: ["loginctl", "lock-session"] },
        { key: "E", icon: "", label: "Выход", cmd: ["mmsg", "dispatch", "quit"] },
        { key: "S", icon: "", label: "Сон", cmd: ["systemctl", "suspend"] },
        { key: "R", icon: "", label: "Перезагрузка", cmd: ["systemctl", "reboot"],
          alt: { key: "B", icon: "", label: "В BIOS", cmd: ["systemctl", "reboot", "--firmware-setup"] } },
        { key: "P", icon: "", label: "Выключение", cmd: ["systemctl", "poweroff"], danger: true }
    ]
    property int current: 0
    property bool alt: false              // выбрана нижняя половинка
    property bool ready: false            // клавиатура принимается через 300 мс после открытия
    Timer { interval: 300; running: true; onTriggered: root.ready = true }

    // блокировка — сразу; остальное — через 10-секундный отсчёт на весь экран (Countdown)
    readonly property var verbs: ({ E: "Сеанс завершится через", S: "Уход в сон через", R: "Перезагрузка через",
                                    B: "Перезагрузка в BIOS через", P: "Выключение через" })
    function run(i, useAlt) {
        const base = actions[i]
        if (!base) return
        const a = useAlt && base.alt ? base.alt : base
        Modal.close()
        if (a.key === "L") { Quickshell.execDetached(a.cmd); return }
        Countdown.start({ key: a.key, icon: a.icon, label: a.label, verb: verbs[a.key] ?? "", cmd: a.cmd,
                          tint: a.key === "P" ? Theme.danger : a.key === "B" ? Theme.warning : Theme.primary })
    }
    property bool picked: false         // буква уже выбирала пункт: следующая такая же подтвердит
    function select(i) {
        picked = false
        if (i !== current) alt = false
        current = i
    }

    onKeyPressed: e => {
        e.accepted = true
        if (!ready) return
        const n = actions.length
        const hasAlt = !!actions[current].alt
        if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) select((current + n - 1) % n)
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) select((current + 1) % n)
        else if (e.key === Qt.Key_Down && hasAlt) alt = true
        else if (e.key === Qt.Key_Up && hasAlt) alt = false
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) run(current, alt)
        else {
            // по физической клавише, чтобы работало и в русской раскладке
            const letters = { [Qt.Key_L]: "L", [Qt.Key_E]: "E", [Qt.Key_S]: "S", [Qt.Key_R]: "R", [Qt.Key_B]: "B", [Qt.Key_P]: "P" }
            const byCode = { 46: "L", 26: "E", 39: "S", 27: "R", 56: "B", 33: "P" }   // xkb keycodes
            const k = letters[e.key] ?? byCode[e.nativeScanCode]
            if (!k) return
            let i = actions.findIndex(a => a.key === k), useAlt = false
            if (i < 0) { i = actions.findIndex(a => a.alt?.key === k); useAlt = i >= 0 }
            if (i < 0) return
            // повторное нажатие буквы уже выбранного пункта — подтверждение (автоповтор при удержании не считается)
            if (i === current && useAlt === alt && !e.isAutoRepeat && picked) { run(i, useAlt); return }
            select(i)
            alt = useAlt
            picked = true
        }
        e.accepted = true
    }

    // половинка / целая кнопка: значок, подпись, клавиша
    component Face: Rectangle {
        id: face
        property var action
        property bool on: false
        property bool compact: false
        property color tint: Theme.primary
        signal hovered
        signal clicked
        radius: 16
        clip: true
        color: on ? Theme.strong : Theme.weak
        border { width: on ? 2 : 1; color: on ? tint : Theme.strong }
        Behavior on color { ColorAnimation { duration: Theme.dFast } }

        // большой вид — по центру столбиком
        Column {
            anchors.centerIn: parent
            spacing: 10
            opacity: face.compact ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.action?.icon ?? ""
                color: face.on ? face.tint : Theme.text
                font { family: Theme.iconFont; pixelSize: 34 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.action?.label ?? ""
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.Medium }
            }
        }
        // компактный — в половинке: значок и подпись в строку, клавиша под ними
        Column {
            anchors.centerIn: parent
            spacing: 6
            opacity: face.compact ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: face.action?.icon ?? ""
                    color: face.on ? face.tint : Theme.text
                    font { family: Theme.iconFont; pixelSize: 18 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: face.action?.label ?? ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                }
            }
        }
        // буква-подсказка — тихо в углу, а не капсулой под подписью
        Text {
            anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 12 }
            text: face.action?.key ?? ""
            color: face.on ? Theme.muted : Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: face.hovered()
            onPositionChanged: face.hovered()
            onClicked: face.clicked()
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            model: root.actions

            Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool selected: root.current === index
                readonly property bool split: selected && !!modelData.alt
                readonly property real gap: 8
                width: 132
                height: 148

                // верх: основное действие (на всю высоту, пока не разделено)
                Face {
                    id: top
                    width: parent.width
                    height: slot.split ? (parent.height - slot.gap) / 2 : parent.height
                    Behavior on height { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                    action: slot.modelData
                    compact: slot.split
                    on: slot.selected && !(slot.split && root.alt)
                    tint: slot.modelData.danger ? Theme.danger : Theme.primary
                    onHovered: { root.select(slot.index); root.alt = false }
                    onClicked: root.run(slot.index, false)
                }
                // низ: альтернатива (BIOS) — выезжает при выборе
                Face {
                    visible: !!slot.modelData.alt
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: slot.split ? (parent.height - slot.gap) / 2 : 0
                    opacity: slot.split ? 1 : 0
                    Behavior on height { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                    action: slot.modelData.alt ?? null
                    compact: true
                    on: slot.split && root.alt
                    tint: Theme.warning
                    onHovered: { root.select(slot.index); root.alt = true }
                    onClicked: root.run(slot.index, true)
                }
            }
        }
    }
}
