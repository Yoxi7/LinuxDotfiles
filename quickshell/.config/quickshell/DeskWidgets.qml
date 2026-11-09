import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Виджеты рабочего стола на слое Background — под окнами, виден на пустом теге.
// Настройка — «Настройки оболочки» (Super+,): какие виджеты, на каком мониторе, размер, фон, плотность, свои опции.
// Правка расположения: qs-send desk edit — плитки тащатся мышью, позиции запоминаются. Вне правки окно сквозное.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData
        visible: Session.deskOn
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Desk.editing ? null : emptyRegion
        Region { id: emptyRegion }
        WlrLayershell.namespace: "qs-desk"
        WlrLayershell.layer: WlrLayer.Background

        Rectangle {
            visible: Desk.editing
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 70 }
            width: hint.implicitWidth + 32; height: 38; radius: 19
            color: Qt.rgba(0, 0, 0, 0.6)
            border { width: 1; color: Theme.primary }
            Text { id: hint; anchors.centerIn: parent; text: "Перетащите виджеты на нужные места · завершить: qs-send desk edit"; color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
        }

        // плитка: позиция и вид из Desk.cfg; масштаб — от левого верхнего угла
        component Tile: Item {
            id: tile
            required property string wid
            default property alias content: holder.data
            readonly property real k: Desk.cfg(wid, "scale")
            readonly property bool glass: Desk.cfg(wid, "style") === "glass"
            property bool extraVisible: true
            visible: Desk.has(wid) && Desk.cfg(wid, "monitor") === win.modelData.name && extraVisible
            x: Desk.position(wid).x
            y: Desk.position(wid).y
            width: holder.childrenRect.width + 40
            height: holder.childrenRect.height + 32
            scale: k
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

            Glass {
                anchors.fill: parent
                visible: tile.glass
                radius: 24
                color: Qt.rgba(1, 1, 1, 0.16 * Desk.cfg(tile.wid, "alpha") / 0.6)
            }
            Rectangle {
                anchors.fill: parent
                radius: 24
                color: "transparent"
                visible: Desk.editing
                border { width: 2; color: Theme.primary }
            }
            Item { id: holder; x: 20; y: 16; width: childrenRect.width; height: childrenRect.height }
            MouseArea {
                anchors.fill: parent
                enabled: Desk.editing
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag { target: tile; minimumX: 0; minimumY: 0; maximumX: win.width - tile.width * tile.k; maximumY: win.height - tile.height * tile.k }
                onReleased: Desk.place(tile.wid, tile.x, tile.y)
            }
        }

        // ── часы
        Tile {
            wid: "clock"
            SystemClock { id: clk; precision: Desk.cfg("clock", "seconds") ? SystemClock.Seconds : SystemClock.Minutes }
            Column {
                spacing: 0
                Text {
                    text: Qt.formatTime(clk.date, (Desk.cfg("clock", "h12") ? "h:mm" : "HH:mm") + (Desk.cfg("clock", "seconds") ? ":ss" : "")
                                                 + (Desk.cfg("clock", "h12") ? " AP" : ""))
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 72; weight: Font.Light; features: ({ "tnum": 1 }) }
                }
                Text {
                    visible: Desk.cfg("clock", "date")
                    text: clk.date.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM")
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 16 }
                }
            }
        }

        // ── погода
        Tile {
            wid: "weather"
            extraVisible: Weather.loaded
            Row {
                spacing: 14
                Text { text: Weather.icon; color: Weather.iconColor; font { family: Theme.iconFont; pixelSize: 40 } anchors.verticalCenter: parent.verticalCenter }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: Weather.fmt(Weather.temp); color: Theme.text; font { family: Theme.font; pixelSize: 30; weight: Font.DemiBold } }
                    Text { visible: Desk.cfg("weather", "desc"); text: Weather.description ?? ""; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
                }
            }
        }

        // ── нагрузка
        Tile {
            wid: "stats"
            Column {
                spacing: 8
                component Stat: Row {
                    property string label
                    property string value
                    spacing: 16
                    Text { width: 70; text: parent.label; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
                    Text { text: parent.value; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.Medium; features: ({ "tnum": 1 }) } }
                }
                Stat { visible: Desk.cfg("stats", "cpu"); label: "CPU"; value: (Cooling.available ? Math.round(Cooling.cpuLoad) : SysInfo.cpu) + "%  ·  " + (Cooling.available ? Math.round(Cooling.cpuTemp) : SysInfo.temp) + "°" }
                Stat { visible: Desk.cfg("stats", "gpu") && Cooling.available; label: "GPU"; value: Math.round(Cooling.gpuLoad) + "%  ·  " + Math.round(Cooling.gpuTemp) + "°" }
                Stat { visible: Desk.cfg("stats", "ram"); label: "RAM"; value: SysInfo.mem + "%" }
            }
        }

        // ── плеер
        Tile {
            wid: "player"
            extraVisible: Player.label !== ""
            Row {
                spacing: 14
                Cover { visible: Desk.cfg("player", "cover"); size: 64; radius: 14; anchors.verticalCenter: parent.verticalCenter; showPause: true }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { width: Math.min(implicitWidth, 300); elide: Text.ElideRight; text: Player.title; color: Theme.text; font { family: Theme.font; pixelSize: 17; weight: Font.DemiBold } }
                    Text { width: Math.min(implicitWidth, 300); elide: Text.ElideRight; text: Player.artist; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
                }
            }
        }

        // ── календарь
        Tile {
            wid: "calendar"
            SystemClock { id: calClk; precision: SystemClock.Minutes }
            Column {
                id: calCol
                spacing: 8
                readonly property bool mon: Desk.cfg("calendar", "monday")
                readonly property date now: calClk.date
                readonly property int first: { const d = new Date(now.getFullYear(), now.getMonth(), 1).getDay(); return mon ? (d + 6) % 7 : d }
                readonly property int days: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
                Text {
                    text: calCol.now.toLocaleString(Qt.locale("ru_RU"), "MMMM yyyy")
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold; capitalization: Font.Capitalize }
                }
                Grid {
                    columns: 7
                    columnSpacing: 4
                    rowSpacing: 2
                    Repeater {
                        model: calCol.mon ? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"] : ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
                        Text { required property string modelData; width: 32; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                    }
                    Repeater {
                        model: 42
                        Rectangle {
                            required property int index
                            readonly property int day: index - calCol.first + 1
                            readonly property bool valid: day >= 1 && day <= calCol.days
                            readonly property bool today: valid && day === calCol.now.getDate()
                            width: 32; height: 28; radius: 9
                            color: today ? Theme.primary : "transparent"
                            Text {
                                anchors.centerIn: parent
                                visible: parent.valid
                                text: parent.day
                                color: parent.today ? Theme.base : Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: parent.today ? Font.DemiBold : Font.Normal; features: ({ "tnum": 1 }) }
                            }
                        }
                    }
                }
            }
        }
    }
}
