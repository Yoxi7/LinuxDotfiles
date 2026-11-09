import QtQuick
import Quickshell
import qs

// Раскладка mango на этом мониторе: значок; в монокле и deck — сколько окон спрятано табами.
// Клик — следующая раскладка (tile → monocle → grid), ПКМ — сразу плитка, колесо — по кругу.
Item {
    id: root
    required property ShellScreen screen
    readonly property var mon: Mango.monitors[screen?.name] ?? null
    readonly property bool stacked: mon !== null && (mon.layout === "monocle" || mon.layout.endsWith("deck")) && mon.count > 1
    readonly property var icons: ({ tile: "\u{f056e}", center_tile: "\u{f056e}", right_tile: "\u{f056e}", grid: "\u{f0570}",
        vertical_grid: "\u{f0570}", monocle: "\u{f0293}", deck: "\u{f0638}", vertical_deck: "\u{f0638}",
        scroller: "\u{f0574}", vertical_scroller: "\u{f0574}", vertical_tile: "\u{f0575}",
        dwindle: "\u{f0574}", fair: "\u{f0573}", vertical_fair: "\u{f0573}" })
    readonly property var names: ({ tile: "Плитка", monocle: "Монокль", grid: "Сетка", deck: "Колода", scroller: "Лента",
        vertical_tile: "Плитка (верт.)", vertical_scroller: "Лента (верт.)", vertical_grid: "Сетка (верт.)",
        vertical_deck: "Колода (верт.)", center_tile: "По центру", right_tile: "Плитка справа", dwindle: "Спираль",
        fair: "Поровну", vertical_fair: "Поровну (верт.)" })

    visible: mon !== null
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: 24

    function dispatch(cmd) {
        // раскладка меняется на мониторе с фокусом — сначала перевести фокус сюда
        Quickshell.execDetached(["bash", "-c", 'mmsg dispatch "focusmon,$1" >/dev/null; mmsg dispatch "$2"', "lay", root.screen.name, cmd])
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icons[root.mon?.layout] ?? "\u{f0570}"
            color: root.stacked ? Theme.primary : mouse.containsMouse ? Theme.text : Theme.muted
            font { family: Theme.iconFont; pixelSize: 15 }
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }
        // в монокле: «2» — окон на теге, видно одно
        Rectangle {
            visible: root.stacked
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(18, cnt.implicitWidth + 10)
            height: 18
            radius: 9
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            border { width: 1; color: Theme.rim }
            Text {
                id: cnt
                anchors.centerIn: parent
                text: root.mon?.count ?? 0
                color: Theme.primary
                font { family: Theme.font; pixelSize: 11; weight: Font.Bold; features: ({ "tnum": 1 }) }
            }
        }
    }

    // подсказка — название раскладки
    Rectangle {
        visible: mouse.containsMouse
        anchors { top: parent.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
        width: tip.implicitWidth + 16
        height: 24
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.75)
        Text {
            id: tip
            anchors.centerIn: parent
            text: root.names[root.mon?.layout] ?? root.mon?.layout ?? ""
            color: Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
    }

    MouseArea {
        id: mouse
        anchors { fill: parent; margins: -6 }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => root.dispatch(e.button === Qt.RightButton ? "setlayout,tile" : "switch_layout")
        onWheel: w => root.dispatch("switch_layout")
    }
}
