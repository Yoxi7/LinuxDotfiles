import QtQuick
import Quickshell
import qs

// Настройки оболочки: приватный режим, простой, виджеты рабочего стола, бар, автоматизация.
// Super+, — открыть. Всё применяется сразу.
ModalWindow {
    id: root
    name: "settings"
    cardWidth: 720
    cardHeight: 700

    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        signal clicked
        height: 32
        width: ct.implicitWidth + 24
        radius: 16
        color: on ? Theme.selected : cm.containsMouse ? Theme.strong : Theme.weak
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text { id: ct; anchors.centerIn: parent; text: chip.label; color: chip.on ? Theme.base : Theme.text; font { family: Theme.font; pixelSize: 13; weight: chip.on ? Font.DemiBold : Font.Medium } }
        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
    component Section: Column {
        property string title
        property string note
        default property alias content: slot.data
        width: parent.width
        spacing: 8
        Text { text: parent.title; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }
        Text { visible: parent.note !== ""; width: parent.width; wrapMode: Text.Wrap; text: parent.note; color: Theme.faint; font { family: Theme.font; pixelSize: 12 } }
        Column { id: slot; width: parent.width; spacing: 8 }
    }
    component Pick: Row {
        id: pick
        property string label
        property int value
        property string valueS: ""        // значение строкой — для bool/число/строка (используется, если задано)
        property var options: []          // [[подпись, значение], …]
        signal chosen(var v)
        signal chosenS(string v)
        spacing: 6
        Text { width: 200; anchors.verticalCenter: parent.verticalCenter; text: pick.label; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
        Repeater {
            model: pick.options
            Chip {
                required property var modelData
                label: modelData[0]
                on: pick.valueS !== "" ? pick.valueS === String(modelData[1]) : pick.value === modelData[1]
                onClicked: { pick.chosen(modelData[1]); pick.chosenS(String(modelData[1])) }
            }
        }
    }
    function fmt(sec) {
        if (sec <= 0) return "выкл"
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), x = sec % 60
        return (h ? h + " ч " : "") + (m ? m + " мин" : "") + (x ? (m || h ? " " : "") + x + " с" : "")
    }
    // счётчик секунд: − значение +, «выкл» — в ноль
    component Step: Item {
        id: st
        property string label
        property string hint
        property int value
        property int step: 60
        property int max: 3600
        signal changed(int v)
        width: parent.width
        height: 56
        Column {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            Text { text: st.label; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Medium } }
            Text { text: st.hint; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Chip { label: "выкл"; on: st.value === 0; onClicked: st.changed(0) }
            Chip { label: "−"; onClicked: st.changed(Math.max(0, st.value - st.step)) }
            Rectangle {
                width: 120; height: 32; radius: 16
                color: Theme.weak
                Text { anchors.centerIn: parent; text: root.fmt(st.value); color: st.value > 0 ? Theme.text : Theme.faint; font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) } }
            }
            Chip { label: "+"; onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
        }
    }
    component Toggle: Row {
        id: tg
        property string label
        property bool value
        signal toggled
        spacing: 12
        Rectangle {
            width: 44; height: 26; radius: 13
            color: tg.value ? Theme.primary : Theme.strong
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Rectangle {
                width: 20; height: 20; radius: 10; y: 3
                x: tg.value ? 21 : 3
                color: tg.value ? Theme.base : Theme.text
                Behavior on x { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: tg.label; color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
    }

    property string tab: Demo.settingsTab || "general"
    Connections {
        target: Demo
        function onSettingsTabChanged() { root.tab = Demo.settingsTab }
        function onDeskOpenIdChanged() { deskSec.openId = Demo.deskOpenId }
    }
    Text {
        id: title
        anchors { left: parent.left; top: parent.top; margins: 24 }
        text: "Настройки оболочки"
        color: Theme.text
        font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
    }
    Row {
        anchors { right: parent.right; verticalCenter: title.verticalCenter; rightMargin: 24 }
        spacing: 6
        Chip { label: "Общее"; on: root.tab === "general"; onClicked: root.tab = "general" }
        Chip { label: "Простой и сон"; on: root.tab === "idle"; onClicked: root.tab = "idle" }
        Chip { label: "Виджеты"; on: root.tab === "desk"; onClicked: root.tab = "desk" }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: title.bottom; bottom: parent.bottom; margins: 24; topMargin: 16 }
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 24

            Section {
                visible: root.tab === "general"
                title: "Приватный режим"
                note: "Размывает заголовок окна, трек и погоду на панели, текст уведомлений, буфер обмена и превью обоев. Под курсором — чётко. Super+Shift+B."
                Toggle { label: Session.privacy ? "Включён" : "Выключен"; value: Session.privacy; onToggled: Session.privacy = !Session.privacy }
            }

            Section {
                visible: root.tab === "general"
                title: "Скруглённые углы экрана"
                note: "Чёрные уголки поверх всего, включая полноэкранные игры: на OLED они просто не светятся. Клики проходят сквозь."
                Toggle { label: Session.corners ? "Включены" : "Выключены"; value: Session.corners; onToggled: Session.corners = !Session.corners }
                Pick {
                    label: "Радиус"
                    valueS: String(Session.cornerRadius)
                    options: [["12 px", 12], ["18 px", 18], ["24 px", 24], ["32 px", 32], ["44 px", 44]]
                    onChosenS: v => Session.cornerRadius = Number(v)
                }
            }

            // ── простой и сон
            Section {
                visible: root.tab === "idle"
                title: "Простой и сон"
                note: "Время отсчитывается от последнего действия с мышью или клавиатурой. Порядок этапов: затемнение → отключение мониторов → блокировка → спящий режим. Этап можно отключить."
                Toggle { label: Session.idleOn ? "Автоматические действия при простое включены" : "Автоматические действия при простое отключены"; value: Session.idleOn; onToggled: Session.idleOn = !Session.idleOn }

                // шкала: где на оси времени каждый этап
                Item {
                    id: tl
                    width: parent.width
                    height: 66
                    readonly property real maxT: Math.max(60, Session.idleDim, Session.idleDpms, Session.idleLock, Session.idleSuspend) * 1.08
                    readonly property var stages: [
                        { name: "затемнение", t: Session.idleDim, c: Theme.muted },
                        { name: "мониторы", t: Session.idleDpms, c: Theme.warning },
                        { name: "блокировка", t: Session.idleLock, c: Theme.primary },
                        { name: "сон", t: Session.idleSuspend, c: Theme.danger } ]
                    Rectangle { y: 30; width: parent.width; height: 6; radius: 3; color: Theme.strong }
                    Repeater {
                        model: tl.stages
                        Item {
                            required property var modelData
                            required property int index
                            visible: modelData.t > 0
                            x: Math.min(tl.width - 2, modelData.t / tl.maxT * tl.width)
                            Rectangle { x: -1; y: 24; width: 3; height: 18; radius: 1.5; color: parent.modelData.c }
                            Text {
                                x: Math.max(-parent.x, Math.min(-width / 2, tl.width - parent.x - width))
                                y: index % 2 === 0 ? 0 : 44
                                text: parent.modelData.name + " · " + root.fmt(parent.modelData.t)
                                color: parent.modelData.c
                                font { family: Theme.font; pixelSize: 11; weight: Font.Medium }
                            }
                        }
                    }
                }

                Step { label: "Затемнить мониторы"; hint: "плавное затемнение; любое движение мыши возвращает яркость"; value: Session.idleDim; step: 30; max: 3600; onChanged: v => Session.idleDim = v }
                Step { label: "Выключить мониторы"; hint: "полностью гасит дисплеи; любое движение или клавиша включает"; value: Session.idleDpms; step: 60; max: 7200; onChanged: v => Session.idleDpms = v }
                Step { label: "Заблокировать сеанс"; hint: "показывает экран блокировки"; value: Session.idleLock; step: 60; max: 7200; onChanged: v => Session.idleLock = v }
                Step { label: "Перейти в спящий режим"; hint: "приостанавливает компьютер (suspend)"; value: Session.idleSuspend; step: 300; max: 14400; onChanged: v => Session.idleSuspend = v }

                Text { text: "Поведение"; color: Theme.text; topPadding: 6; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                Toggle { label: "Блокировать сеанс перед сном"; value: Session.idleLockSleep; onToggled: Session.idleLockSleep = !Session.idleLockSleep }
                Toggle { label: "Не срабатывать при просмотре видео и в играх"; value: Session.idleRespect; onToggled: Session.idleRespect = !Session.idleRespect }
                Toggle { label: "Не срабатывать, пока окно открыто на весь экран"; value: Session.idleSkipFs; onToggled: Session.idleSkipFs = !Session.idleSkipFs }
                Pick {
                    label: "Уровень затемнения"
                    valueS: String(Session.idleDimLevel)
                    options: [["30%", 0.3], ["50%", 0.5], ["72%", 0.72], ["90%", 0.9]]
                    onChosenS: v => Session.idleDimLevel = Number(v)
                }

                Text { text: "Проверить"; color: Theme.text; topPadding: 6; font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold } }
                Flow {
                    width: parent.width
                    spacing: 6
                    Chip { label: "Затемнить на 3 секунды"; onClicked: Quickshell.execDetached(["qs", "-c", "lite", "ipc", "call", "idle", "dimNow"]) }
                    Chip { label: "Заблокировать сейчас"; onClicked: Quickshell.execDetached(["loginctl", "lock-session"]) }
                    Chip { label: "Выключить мониторы"; onClicked: Quickshell.execDetached(["qs", "-c", "lite", "ipc", "call", "idle", "screensOff"]) }
                }
            }

            Section {
                id: deskSec
                visible: root.tab === "desk"
                title: "Виджеты рабочего стола"
                note: "Виджеты лежат под окнами и видны на пустом рабочем столе. Раскрой виджет, чтобы настроить монитор, размер, фон и содержимое."
                property string openId: ""
                Flow {
                    width: parent.width
                    spacing: 12
                    Toggle { label: Session.deskOn ? "Показывать" : "Скрыты"; value: Session.deskOn; onToggled: Session.deskOn = !Session.deskOn }
                    Chip { label: Desk.editing ? "Готово" : "Изменить расположение"; on: Desk.editing; onClicked: { Session.deskOn = true; Desk.editing = !Desk.editing } }
                    Chip { label: "Сбросить расположение"; onClicked: Desk.resetPos() }
                }
                Repeater {
                    model: Desk.catalog
                    Column {
                        id: dw
                        required property var modelData
                        readonly property bool open: deskSec.openId === modelData.id
                        width: col.width
                        spacing: 8

                        Rectangle {
                            width: parent.width; height: 48; radius: 14
                            color: hm.containsMouse ? Theme.strong : Theme.weak
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            Text { id: wic; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } width: 20; horizontalAlignment: Text.AlignHCenter; text: dw.modelData.icon; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 16 } }
                            Text { anchors { left: wic.right; leftMargin: 12; verticalCenter: parent.verticalCenter } text: dw.modelData.label; color: Theme.text; font { family: Theme.font; pixelSize: 14; weight: Font.Medium } }
                            MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: deskSec.openId = dw.open ? "" : dw.modelData.id }
                            Row {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Chip { label: Desk.has(dw.modelData.id) ? "Показан" : "Скрыт"; on: Desk.has(dw.modelData.id); onClicked: Desk.toggle(dw.modelData.id) }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: dw.open ? "\uf077" : "\uf078"; color: Theme.muted; font { family: Theme.iconFont; pixelSize: 12 } }
                            }
                        }

                        Column {
                            visible: dw.open
                            width: parent.width
                            leftPadding: 8
                            spacing: 8
                            Pick {
                                label: "Монитор"
                                readonly property string cur: Desk.cfg(dw.modelData.id, "monitor")
                                options: Quickshell.screens.map(s => [s.name, s.name])
                                valueS: cur
                                onChosenS: v => Desk.set(dw.modelData.id, "monitor", v)
                            }
                            Repeater {
                                model: Desk.common.concat(dw.modelData.opts)
                                Pick {
                                    required property var modelData
                                    visible: !modelData.when || Desk.cfg(dw.modelData.id, "style") === modelData.when
                                    label: modelData.label
                                    options: modelData.values
                                    valueS: String(Desk.cfg(dw.modelData.id, modelData.key))
                                    onChosenS: v => {
                                        const hit = modelData.values.find(x => String(x[1]) === v)
                                        Desk.set(dw.modelData.id, modelData.key, hit ? hit[1] : v)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                visible: root.tab === "general"
                title: "Панель и окна"
                Row {
                    spacing: 6
                    Chip { label: "Расположение элементов панели"; onClicked: Modal.toggle("barconfig") }
                    Chip { label: "Обои"; onClicked: Modal.toggle("wallpapers") }
                }
            }

            Section {
                visible: root.tab === "general"
                title: "Автоматизация"
                note: "Команды можно слать из скриптов и игр: qs-send toast \"Заголовок | текст\", qs-send privacy toggle, qs-send desk edit, qs-send modal launcher."
            }
        }
    }
}
