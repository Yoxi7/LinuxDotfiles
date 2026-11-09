pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Календарь по клику на часы: месяц с номерами недель, листание, сегодня и ближайшие задачи.
// ←/→ — месяц, ↑/↓ — год, Home / T — вернуться на сегодня, Esc — закрыть.
ModalWindow {
    id: root
    name: "calendar"
    dropdown: true
    cardWidth: 372
    cardHeight: col.implicitHeight + 32

    readonly property var today: new Date()
    property date shown: new Date(today.getFullYear(), today.getMonth(), 1)
    property int selected: today.getDate()          // выбранный день в показанном месяце (0 — нет)
    readonly property bool thisMonth: shown.getFullYear() === today.getFullYear() && shown.getMonth() === today.getMonth()
    readonly property int lead: (new Date(shown.getFullYear(), shown.getMonth(), 1).getDay() + 6) % 7   // с понедельника
    readonly property int daysInMonth: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()
    readonly property int rows: Math.ceil((lead + daysInMonth) / 7)
    readonly property var loc: Qt.locale("ru_RU")

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7))
        return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7)
    }
    function shift(months) {
        shown = new Date(shown.getFullYear(), shown.getMonth() + months, 1)
        selected = thisMonth ? today.getDate() : 0
    }
    function goToday() { shown = new Date(today.getFullYear(), today.getMonth(), 1); selected = today.getDate() }
    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }

    // дата, показанная в шапке: выбранный день, иначе первое число месяца
    readonly property date headDate: new Date(shown.getFullYear(), shown.getMonth(), selected || 1)

    onKeyPressed: e => {
        if (e.key === Qt.Key_Left) shift(-1)
        else if (e.key === Qt.Key_Right) shift(1)
        else if (e.key === Qt.Key_Up) shift(-12)
        else if (e.key === Qt.Key_Down) shift(12)
        else if (e.key === Qt.Key_Home || e.key === Qt.Key_T) goToday()
        else return
        e.accepted = true
    }

    component Nav: Rectangle {
        id: nav
        property string icon
        signal clicked
        width: 28; height: 28; radius: 8
        color: navMouse.containsMouse ? Theme.strong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: nav.icon
            color: navMouse.containsMouse ? Theme.text : Theme.muted
            font { family: Theme.iconFont; pixelSize: 12 }
        }
        MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nav.clicked() }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 14

        // шапка: большой день недели и дата
        Item {
            width: col.width
            height: headCol.implicitHeight
            Column {
                id: headCol
                anchors { left: parent.left; right: parent.right }
                spacing: 2
                Text {
                    text: root.cap(root.loc.dayName(root.headDate.getDay() , Locale.LongFormat))
                    color: Theme.primary
                    font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 1 }
                }
                Text {
                    text: root.headDate.getDate() + " " + root.loc.monthName(root.headDate.getMonth(), Locale.LongFormat) + " " + root.headDate.getFullYear()
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 26; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                }
                Text {
                    text: "неделя " + root.isoWeek(root.headDate) + " · день года "
                          + Math.round((root.headDate - new Date(root.headDate.getFullYear(), 0, 0)) / 86400000)
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                }
            }
        }

        // месяц
        Glass {
            width: col.width
            height: monthCol.implicitHeight + 24
            radius: 12                       // концентрично: окно 28 − отступ 16
            color: Qt.rgba(0, 0, 0, 0.22)
            sheen: false
            interactive: false
            fresnel: 0.5
            rimColor: Qt.rgba(1, 1, 1, 0.07)
            glintColor: Qt.rgba(1, 1, 1, 0.55)
            rimWidth: 1

            Column {
                id: monthCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8

                Item {
                    width: parent.width
                    height: 28
                    Text {
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        text: root.cap(root.loc.standaloneMonthName(root.shown.getMonth())) + " " + root.shown.getFullYear()
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Nav { icon: ""; onClicked: root.shift(-1) }
                        Nav { visible: !root.thisMonth; icon: ""; onClicked: root.goToday() }
                        Nav { icon: ""; onClicked: root.shift(1) }
                    }
                }

                Grid {
                    id: grid
                    columns: 8                // номер недели + 7 дней
                    width: parent.width
                    readonly property real cw: width / 8

                    // заголовок дней недели
                    Item { width: grid.cw; height: 22 }
                    Repeater {
                        model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                        Text {
                            required property string modelData
                            required property int index
                            width: grid.cw
                            height: 22
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: index >= 5 ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.7) : Theme.faint
                            font { family: Theme.font; pixelSize: 11 }
                        }
                    }

                    // недели: слева номер, дальше дни
                    Repeater {
                        model: root.rows * 8
                        Item {
                            id: cell
                            required property int index
                            readonly property int row: Math.floor(index / 8)
                            readonly property int dow: index % 8 - 1                  // −1 — колонка недели
                            readonly property int day: dow < 0 ? 0 : row * 7 + dow - root.lead + 1
                            readonly property bool valid: dow >= 0 && day >= 1 && day <= root.daysInMonth
                            readonly property bool isToday: valid && root.thisMonth && day === root.today.getDate()
                            readonly property bool isSelected: valid && day === root.selected
                            width: grid.cw
                            height: 34

                            // номер недели
                            Text {
                                visible: cell.dow < 0
                                anchors.centerIn: parent
                                text: root.isoWeek(new Date(root.shown.getFullYear(), root.shown.getMonth(), 1 - root.lead + cell.row * 7 + 3))
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 10; features: ({ "tnum": 1 }) }
                                opacity: 0.7
                            }
                            // выбранный день — тонкое кольцо, сегодня — заливка акцентом
                            Rectangle {
                                visible: cell.valid
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                color: cell.isToday ? Theme.accent : dayMouse.containsMouse ? Theme.strong : "transparent"
                                border { width: cell.isSelected && !cell.isToday ? 1 : 0; color: Theme.primary }
                                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            }
                            Text {
                                visible: cell.valid
                                anchors.centerIn: parent
                                text: cell.day
                                color: cell.isToday ? Theme.text : cell.dow >= 5 ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.85) : Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: cell.isToday ? Font.Bold : Font.Normal; features: ({ "tnum": 1 }) }
                            }
                            MouseArea {
                                id: dayMouse
                                anchors.fill: parent
                                enabled: cell.valid
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selected = cell.day
                            }
                        }
                    }
                }
            }
        }

        // ближайшие задачи (из органайзера)
        Item {
            width: col.width
            height: tasksCol.implicitHeight
            visible: Todo.pending.length > 0
            Column {
                id: tasksCol
                width: parent.width
                spacing: 2
                Item {
                    width: parent.width
                    height: 22
                    Text {
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        text: "Задачи"
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        text: "Все " + Todo.pending.length + "…"
                        color: allMouse.containsMouse ? Theme.text : Theme.muted
                        font { family: Theme.font; pixelSize: 11 }
                        MouseArea {
                            id: allMouse
                            anchors { fill: parent; margins: -4 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Session.ccTab = 1; Modal.toggleAt("control", Modal.anchorX, Modal.anchorScreen) }
                        }
                    }
                }
                Repeater {
                    model: Todo.pending.slice(0, 3)
                    Item {
                        id: task
                        required property var modelData
                        required property int index
                        width: tasksCol.width
                        height: 28
                        Rectangle {
                            id: dot
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 6; height: 6; radius: 3
                            color: task.index === 0 ? Theme.primary : Theme.faint
                        }
                        Text {
                            anchors { left: dot.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: task.modelData.text
                            color: task.index === 0 ? Theme.text : Theme.muted
                            font { family: Theme.font; pixelSize: 13 }
                        }
                    }
                }
            }
        }
    }
}
