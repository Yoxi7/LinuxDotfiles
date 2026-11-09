pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Настройка бара: что показывать, в каком порядке, в какой зоне и в каких «островах».
// Изменения применяются сразу (сам бар виден сверху). Открывается ПКМ по пустому месту бара.
//   ↑ ↓ — порядок в зоне · звено — слить с предыдущим элементом в один остров · ◀ ▶ — в соседнюю зону · × — убрать
ModalWindow {
    id: root
    name: "barconfig"
    cardWidth: 1040
    cardHeight: 700

    property string scope: Demo.barScope || "primary"
    readonly property var zones: BarLayout.zones
    Connections {
        target: Demo
        function onBarScopeChanged() { root.scope = Demo.barScope }
    }

    component Btn: Rectangle {
        id: btn
        property string icon
        property string tip
        property bool on: false
        property bool off: false
        property color tint: Theme.muted
        signal clicked
        width: 28; height: 28; radius: 8
        opacity: off ? 0.28 : 1
        color: on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : bm.containsMouse && !off ? Theme.strong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.on ? Theme.primary : bm.containsMouse && !btn.off ? Theme.text : btn.tint
            font { family: Theme.iconFont; pixelSize: 12 }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!btn.off) btn.clicked() }
    }
    component Tab: Rectangle {
        id: tab
        property string label
        property bool on: false
        signal clicked
        height: 34
        width: tl.implicitWidth + 28
        radius: 17
        color: on ? Theme.selected : tm.containsMouse ? Theme.strong : Theme.weak
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
        Text {
            id: tl
            anchors.centerIn: parent
            text: tab.label
            color: tab.on ? Theme.base : Theme.text
            font { family: Theme.font; pixelSize: 13; weight: tab.on ? Font.DemiBold : Font.Medium }
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.clicked() }
    }

    // ── шапка
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20 }
        height: 40
        Text {
            id: title
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Настройка панели"
            color: Theme.text
            font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
        }
        Row {
            anchors { left: title.right; leftMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 6
            Tab { label: "Основной монитор"; on: root.scope === "primary"; onClicked: root.scope = "primary" }
            Tab { label: "Остальные мониторы"; on: root.scope === "secondary"; onClicked: root.scope = "secondary" }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Tab { label: "По умолчанию"; onClicked: BarLayout.reset(root.scope) }
            Tab { label: "Готово"; on: true; onClicked: Modal.close() }
        }
    }
    Text {
        id: hint
        anchors { top: header.bottom; left: parent.left; leftMargin: 22; topMargin: 4 }
        text: "Изменения применяются сразу, панель видна сверху. Кнопка-звено объединяет элемент с предыдущим в один блок."
        color: Theme.faint
        font { family: Theme.font; pixelSize: 12 }
    }

    // ── три зоны
    Row {
        id: cols
        anchors { top: hint.bottom; topMargin: 14; left: parent.left; right: parent.right; margins: 20; bottom: pool.top; bottomMargin: 14 }
        spacing: 12

        Repeater {
            model: root.zones
            Rectangle {
                id: col
                required property string modelData            // left | center | right
                readonly property var items: BarLayout.list(root.scope, modelData)
                width: (cols.width - 24) / 3
                height: cols.height
                radius: 16
                color: Qt.rgba(0, 0, 0, 0.22)
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.07) }

                Text {
                    id: colTitle
                    anchors { left: parent.left; top: parent.top; margins: 14 }
                    text: BarLayout.zoneNames[col.modelData]
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: colTitle.verticalCenter; rightMargin: 14 }
                    text: col.items.length + " " + Theme.plural(col.items.length, "элемент", "элемента", "элементов")
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
                Text {
                    anchors.centerIn: parent
                    visible: col.items.length === 0
                    text: "Пусто"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 13 }
                }

                ListView {
                    anchors { top: colTitle.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                    clip: true
                    spacing: 4
                    model: col.items
                    boundsBehavior: Flickable.StopAtBounds
                    move: Transition { NumberAnimation { properties: "y"; duration: Theme.dBase; easing.type: Easing.OutCubic } }
                    displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.dBase; easing.type: Easing.OutCubic } }

                    delegate: Item {
                        id: cell
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: row.height + (!row.joined && index > 0 ? 12 : 0)        // между островами — зазор

                    Rectangle {
                        id: row
                        readonly property bool joined: cell.modelData.charAt(0) === "+"
                        readonly property var info: BarLayout.info(BarLayout.bare(cell.modelData))
                        property int index: cell.index
                        property string modelData: cell.modelData
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 52
                        radius: 12
                        color: rm.containsMouse ? Theme.strong : Theme.weak
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true }

                        // слитый с предыдущим — общая «капсула»: полоска слева
                        Rectangle {
                            visible: row.joined
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: -4 }
                            width: 3
                            radius: 1.5
                            color: Theme.primary
                        }
                        Text {
                            id: ic
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 18
                            horizontalAlignment: Text.AlignHCenter
                            text: row.info.icon
                            color: Theme.primary
                            font { family: Theme.iconFont; pixelSize: 15 }
                        }
                        Column {
                            anchors { left: ic.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            opacity: ctl.opacity > 0.5 ? 0.25 : 1
                            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.info.label
                                color: Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.joined ? "в одном блоке с предыдущим" : row.info.note
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11 }
                            }
                        }
                        Rectangle {
                            id: ctl
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            height: 36
                            width: ctlRow.implicitWidth + 12
                            radius: 10
                            color: Qt.rgba(0.08, 0.08, 0.1, 0.96)
                            border { width: 1; color: Qt.rgba(1, 1, 1, 0.1) }
                            opacity: rm.containsMouse || ctlHover.hovered ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                            HoverHandler { id: ctlHover }
                            Row {
                                id: ctlRow
                                anchors.centerIn: parent
                            Btn { icon: ""; off: row.index === 0; onClicked: BarLayout.move(root.scope, col.modelData, row.index, -1) }
                            Btn { icon: ""; off: row.index === col.items.length - 1; onClicked: BarLayout.move(root.scope, col.modelData, row.index, 1) }
                            Btn { icon: ""; on: row.joined; off: row.index === 0; onClicked: BarLayout.toggleJoin(root.scope, col.modelData, row.index) }
                            Btn {
                                icon: ""
                                off: root.zones.indexOf(col.modelData) === 0
                                onClicked: BarLayout.moveZone(root.scope, col.modelData, row.index, root.zones[root.zones.indexOf(col.modelData) - 1])
                            }
                            Btn {
                                icon: ""
                                off: root.zones.indexOf(col.modelData) === 2
                                onClicked: BarLayout.moveZone(root.scope, col.modelData, row.index, root.zones[root.zones.indexOf(col.modelData) + 1])
                            }
                            Btn { icon: ""; tint: Theme.danger; onClicked: BarLayout.remove(root.scope, col.modelData, row.index) }
                        }
                            }
                    }
                        }
                }
            }
        }
    }

    // ── спрятанные элементы: добавить в зону
    Rectangle {
        id: pool
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
        readonly property var items: BarLayout.pool(root.scope)
        height: items.length ? poolFlow.implicitHeight + 46 : 0
        visible: items.length > 0
        radius: 16
        color: Qt.rgba(1, 1, 1, 0.04)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Text {
            anchors { left: parent.left; top: parent.top; margins: 14 }
            text: "Скрытые элементы — выбери, где показать"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
        }
        Flow {
            id: poolFlow
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 34 }
            spacing: 8
            Repeater {
                model: pool.items
                Rectangle {
                    id: pi
                    required property var modelData
                    height: 34
                    width: pr.implicitWidth + 12
                    radius: 17
                    color: Theme.weak
                    Row {
                        id: pr
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent?.verticalCenter
                            leftPadding: 8; rightPadding: 4
                            text: pi.modelData.icon + "  " + pi.modelData.label
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Repeater {
                            model: root.zones
                            Rectangle {
                                required property string modelData
                                required property int index
                                anchors.verticalCenter: parent?.verticalCenter
                                height: 24
                                width: zt.implicitWidth + 14
                                radius: 12
                                color: zm.containsMouse ? Theme.border : Theme.strong
                                Text {
                                    id: zt
                                    anchors.centerIn: parent
                                    text: ["Слева", "Центр", "Справа"][index]
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                                MouseArea {
                                    id: zm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BarLayout.add(root.scope, pi.modelData.id, modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
