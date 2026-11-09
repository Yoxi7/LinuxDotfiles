import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Мини-дашборд на вспомогательном мониторе HDMI-A-1 (Soogeen 800×1280, повёрнут в альбом):
// слева плеер; в середине часы, CPU/GPU с графиками за 2 минуты (как окно «Система»), память, погода;
// справа последние уведомления и календарь.
// Слой Bottom — под окнами, без клавиатуры и без резерва места. Вкл/выкл: qs -c lite ipc call minidash toggle
Scope {
    id: root
    readonly property string outputName: "HDMI-A-1"

    Variants {
        model: Quickshell.screens.filter(s => s.name === root.outputName)

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: Session.miniOn
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "#050507"
            WlrLayershell.namespace: "qs-minidash"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property int m: 20
            readonly property int gap: 14
            readonly property int colL: 470
            readonly property int colM: 380
            readonly property int usable: height - 2 * m

            function mmss(sec) {
                const s = Math.max(0, Math.floor(sec))
                return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
            }
            function heat(t, warm, hot) { return t >= hot ? Theme.danger : t >= warm ? Theme.warning : Theme.text }

            // карточка: стекло-подложка и содержимое с внутренними отступами
            component Card: Rectangle {
                default property alias content: holder.data
                radius: 22
                color: Theme.weak
                border { width: 1; color: Theme.rimSoft }
                Item { id: holder; anchors.fill: parent; anchors.margins: 18; clip: true }
            }

            // кнопка плеера: глиф из MedeoMono Nerd Font, нажатие — сигнал
            component Ctl: Text {
                id: ctl
                property string glyph
                property color tint: Theme.text
                property bool big: false
                signal tapped()
                text: glyph
                color: tint
                font { family: Theme.iconFont; pixelSize: big ? 64 : 34 }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    enabled: Player.available
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ctl.tapped()
                }
            }

            // ── левая колонка: плеер
            Card {
                x: win.m; y: win.m
                width: win.colL
                height: win.usable
                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 20
                    Cover {
                        size: 400; radius: 26; showPause: true
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Column {
                        width: parent.width
                        spacing: 4
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: Player.available ? Player.title : "Нет плеера"
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 28; weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: Player.artist
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 18 }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 10
                        Text { id: posTxt; anchors.verticalCenter: parent.verticalCenter; text: win.mmss(Player.livePosition); color: Theme.faint; font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) } }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - posTxt.implicitWidth - durTxt.implicitWidth - 20
                            height: 6; radius: 3; color: Theme.strong
                            Rectangle {
                                width: Player.duration > 0 ? parent.width * Math.min(1, Player.livePosition / Player.duration) : 0
                                height: parent.height; radius: 3; color: Theme.primary
                            }
                        }
                        Text { id: durTxt; anchors.verticalCenter: parent.verticalCenter; text: win.mmss(Player.duration); color: Theme.faint; font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) } }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 38
                        Ctl { anchors.verticalCenter: parent.verticalCenter; glyph: Player.liked ? "\u{f004}" : "\u{f08a}"; tint: Player.liked ? Theme.danger : Theme.muted; onTapped: Player.toggleLike() }
                        Ctl { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{f048}"; onTapped: Player.previous() }
                        Ctl { anchors.verticalCenter: parent.verticalCenter; glyph: Player.playing ? "\u{f04c}" : "\u{f04b}"; big: true; onTapped: Player.toggle() }
                        Ctl { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{f051}"; onTapped: Player.next() }
                    }
                }
            }

            // ── средняя колонка: часы, CPU/GPU, память, погода
            Column {
                id: midCol
                x: win.m + win.colL + win.gap; y: win.m
                width: win.colM
                spacing: win.gap
                readonly property int clockH: 140
                readonly property int weatherH: 192

                SystemClock { id: clk; precision: SystemClock.Seconds }
                Card {
                    id: clockCard
                    width: midCol.width; height: midCol.clockH
                    // МСК = UTC+3: сдвигаем момент так, чтобы локальные часы показывали московское время
                    readonly property var msk: new Date(clk.date.getTime() + (clk.date.getTimezoneOffset() + 180) * 60000)
                    Column {
                        anchors.fill: parent
                        spacing: 4
                        Row {
                            spacing: 22
                            Column {
                                Text { text: "НСК"; color: Theme.primary; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }
                                Text { text: Qt.formatTime(clk.date, "HH:mm"); color: Theme.text; font { family: Theme.font; pixelSize: 46; weight: Font.Light; features: ({ "tnum": 1 }) } }
                            }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 56; color: Theme.border }
                            Column {
                                Text { text: "МСК"; color: Theme.muted; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold } }
                                Text { text: Qt.formatTime(clockCard.msk, "HH:mm"); color: Theme.muted; font { family: Theme.font; pixelSize: 46; weight: Font.Light; features: ({ "tnum": 1 }) } }
                            }
                        }
                        Text { text: clk.date.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM"); color: Theme.muted; font { family: Theme.font; pixelSize: 18 } }
                    }
                }

                Card {
                    width: midCol.width
                    height: win.usable - midCol.clockH - midCol.weatherH - 2 * win.gap
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        // без CoolerControl — только процессор из /proc, без графика
                        Row {
                            visible: !Cooling.available
                            spacing: 12
                            Text { text: "CPU"; color: Theme.muted; font { family: Theme.font; pixelSize: 18 } }
                            Text { text: SysInfo.cpu + "%  ·  " + SysInfo.temp + "°"; color: win.heat(SysInfo.temp, 75, 88); font { family: Theme.font; pixelSize: 30; weight: Font.DemiBold; features: ({ "tnum": 1 }) } }
                        }
                        MiniChip {
                            visible: Cooling.available
                            icon: "\u{f4bc}"
                            title: "Процессор"
                            temp: Cooling.cpuTemp; warm: 75; hot: 88
                            load: Cooling.cpuLoad
                            loadKey: "cpuLoad"; tempKey: "cpuTemp"
                            facts: [Math.round(Cooling.cpuPower) + " Вт", (Cooling.cpuFreq / 1000).toFixed(2) + " ГГц"]
                        }
                        MiniChip {
                            visible: Cooling.available
                            icon: "\u{f08ae}"
                            title: "Видеокарта"
                            temp: Cooling.gpuTemp; warm: 72; hot: 83
                            load: Cooling.gpuLoad
                            loadKey: "gpuLoad"; tempKey: "gpuTemp"
                            facts: [Math.round(Cooling.gpuPower) + " Вт", (Cooling.gpuFreq / 1000).toFixed(2) + " ГГц", "hotspot " + Math.round(Cooling.gpuHotspot) + "°"]
                        }
                        // память
                        Column {
                            width: parent.width
                            spacing: 5
                            Item {
                                width: parent.width
                                height: 22
                                Text { anchors.left: parent.left; text: "Память"; color: Theme.text; font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold } }
                                Text { anchors.right: parent.right; text: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(0) + " ГиБ"; color: Theme.muted; font { family: Theme.font; pixelSize: 16; features: ({ "tnum": 1 }) } }
                            }
                            Rectangle {
                                width: parent.width; height: 6; radius: 3; color: Theme.strong
                                Rectangle {
                                    width: parent.width * Math.min(1, SysInfo.mem / 100)
                                    height: parent.height; radius: 3
                                    color: SysInfo.mem >= 90 ? Theme.danger : Theme.primary
                                }
                            }
                        }
                    }
                }

                Card {
                    width: midCol.width; height: midCol.weatherH
                    Column {
                        anchors.fill: parent
                        spacing: 10
                        Row {
                            spacing: 12
                            Text { visible: Weather.loaded; anchors.verticalCenter: parent.verticalCenter; text: Weather.icon; color: Weather.iconColor; font { family: Theme.iconFont; pixelSize: 44 } }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: Weather.loaded ? Weather.fmt(Weather.temp) : "…"; color: Theme.text; font { family: Theme.font; pixelSize: 36; weight: Font.DemiBold } }
                                Text { text: Weather.description ?? ""; color: Theme.muted; font { family: Theme.font; pixelSize: 16 } }
                            }
                        }
                        Row {
                            width: parent.width
                            Repeater {
                                model: Weather.hourly.slice(0, 6)
                                Column {
                                    required property var modelData
                                    width: parent.width / 6
                                    spacing: 2
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.time; color: Theme.faint; font { family: Theme.font; pixelSize: 14 } }
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.icon; color: modelData.color; font { family: Theme.iconFont; pixelSize: 24 } }
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.temp; color: Theme.text; font { family: Theme.font; pixelSize: 15; features: ({ "tnum": 1 }) } }
                                }
                            }
                        }
                    }
                }
            }

            // ── правая колонка: уведомления (одна строка на заголовок и тело) и календарь
            Column {
                id: rightCol
                x: win.m + win.colL + win.gap + win.colM + win.gap; y: win.m
                width: win.width - x - win.m
                spacing: win.gap
                readonly property int calH: 270

                Card {
                    width: rightCol.width
                    height: win.usable - rightCol.calH - win.gap
                    Column {
                        anchors.fill: parent
                        spacing: 12
                        Text { text: "Уведомления"; color: Theme.text; font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold } }
                        Text { visible: Notifs.history.length === 0; text: "Пусто"; color: Theme.faint; font { family: Theme.font; pixelSize: 15 } }
                        Repeater {
                            model: Notifs.history.slice(0, 5)
                            Column {
                                required property var modelData
                                width: parent.width
                                spacing: 1
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Text { width: parent.width - timeTxt.implicitWidth - 6; elide: Text.ElideRight; text: modelData.appName ?? ""; color: Theme.faint; font { family: Theme.font; pixelSize: 13 } }
                                    Text { id: timeTxt; text: Notifs.timeOf(modelData); color: Theme.faint; font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) } }
                                }
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.summary ?? ""; color: Theme.text; font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold } }
                                Text { width: parent.width; visible: text !== ""; elide: Text.ElideRight; maximumLineCount: 1; text: (modelData.body ?? "").replace(/<[^>]*>/g, ""); color: Theme.muted; font { family: Theme.font; pixelSize: 14 } }
                            }
                        }
                    }
                }

                Card {
                    id: calCard
                    width: rightCol.width; height: rightCol.calH
                    readonly property date now: clk.date
                    readonly property int first: { const d = new Date(now.getFullYear(), now.getMonth(), 1).getDay(); return (d + 6) % 7 }
                    readonly property int days: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
                    Column {
                        anchors.fill: parent
                        spacing: 4
                        Text {
                            text: calCard.now.toLocaleString(Qt.locale("ru_RU"), "MMMM yyyy")
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold; capitalization: Font.Capitalize }
                        }
                        Grid {
                            columns: 7
                            width: parent.width
                            Repeater {
                                model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                                Text { required property string modelData; width: parent.width / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.faint; font { family: Theme.font; pixelSize: 14 } }
                            }
                            Repeater {
                                model: 42
                                Rectangle {
                                    required property int index
                                    readonly property int day: index - calCard.first + 1
                                    readonly property bool valid: day >= 1 && day <= calCard.days
                                    readonly property bool today: valid && day === calCard.now.getDate()
                                    width: parent.width / 7; height: 30; radius: 8
                                    color: today ? Theme.primary : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.valid
                                        text: parent.day
                                        color: parent.today ? Theme.base : Theme.text
                                        font { family: Theme.font; pixelSize: 16; weight: parent.today ? Font.DemiBold : Font.Normal; features: ({ "tnum": 1 }) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
