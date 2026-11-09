pragma ComponentBehavior: Bound
import QtQuick
import qs

// Погода подробно: сейчас, за день, ветер/влажность/давление, 6 часов вперёд
// и сетка по дням с понедельника этой недели (~16 дней вперёд), как у Яндекса.
// Окно создаётся по клику и уничтожается при закрытии (LazyLoader в shell.qml).
ModalWindow {
    id: root
    name: "weather"
    dropdown: true
    cardWidth: 520
    cardHeight: col.implicitHeight + 36

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 14

        // город + обновить
        Item {
            width: col.width
            height: 20
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.glyph(0xf034e) + "  " + Weather.city
                color: Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.failed ? "нет связи" : Weather.loaded ? Weather.sources + "  ·  " + Qt.formatTime(Weather.updated, "HH:mm") : ""
                    color: Weather.failed ? Theme.danger : Theme.faint
                    font { family: Theme.font; pixelSize: 11 }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.glyph(0xf0450)
                    color: refresh.containsMouse ? Theme.text : Theme.muted
                    font { family: Theme.iconFont; pixelSize: 15 }
                    MouseArea { id: refresh; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Weather.update() }
                }
            }
        }

        // сейчас
        Row {
            width: col.width
            spacing: 16
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.icon
                renderType: Text.NativeRendering   // иначе широкий значок обрезается справа
                color: Weather.iconColor
                font { family: Theme.iconFont; pixelSize: 52 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 52 - 16 - 16
                spacing: 2
                Text {
                    text: Weather.fmt(Weather.temp)
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 38; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: Weather.description
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13 }
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: "ощущается " + Weather.fmt(Weather.feelsLike) + "  ·  " + Weather.fmt(Weather.todayMax) + " / " + Weather.fmt(Weather.todayMin)
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }

        // ветер, влажность, давление
        Glass {
            width: col.width
            height: 40
            radius: 12
            color: Qt.rgba(0, 0, 0, 0.22)
            sheen: false
            interactive: false
            fresnel: 0.5
            rimColor: Qt.rgba(1, 1, 1, 0.07)
            glintColor: Qt.rgba(1, 1, 1, 0.55)
            rimWidth: 1
            Row {
                anchors.centerIn: parent
                spacing: 22
                component Metric: Row {
                    property int cp
                    property string value
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.glyph(parent.cp)
                        color: Theme.muted
                        font { family: Theme.iconFont; pixelSize: 14 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.value
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 12 }
                    }
                }
                Metric { cp: 0xf059d; value: Weather.wind + " м/с" }
                Metric { cp: 0xf058e; value: Weather.humidity + "%" }
                Metric { cp: 0xf0874; value: Weather.pressure + " мм" }
            }
        }

        // 6 часов вперёд
        Row {
            width: col.width
            spacing: 6
            visible: Weather.hourly.length > 0
            Repeater {
                model: Weather.hourly
                Rectangle {
                    id: hour
                    required property var modelData
                    width: (col.width - 5 * 6) / 6
                    height: 74
                    color: "transparent"      // без коробок: колонки разделяет воздух
                    Column {
                        anchors.centerIn: parent
                        spacing: 5
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hour.modelData.time; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hour.modelData.icon; renderType: Text.NativeRendering; color: hour.modelData.color; font { family: Theme.iconFont; pixelSize: 18 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: hour.modelData.temp; color: Theme.text; font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold } }
                    }
                }
            }
        }
            // ── по дням
        Column {
            width: col.width
            spacing: 6
            visible: Weather.calendar.length > 0

            Row {
                Repeater {
                    model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                    Text {
                        required property string modelData
                        required property int index
                        width: col.width / 7
                        leftPadding: 6
                        text: modelData
                        color: index >= 5 ? Theme.danger : Theme.muted
                        font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                    }
                }
            }

            Grid {
                columns: 7
                Repeater {
                    model: Weather.calendar
                    Item {
                        id: day
                        required property var modelData
                        required property int index
                        readonly property var d: modelData
                        width: col.width / 7
                        height: 64
                        opacity: d?.past ? 0.4 : 1

                        // разделитель между неделями
                        Rectangle {
                            visible: day.index >= 7
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.07)
                        }
                        Rectangle {
                            visible: day.d?.today ?? false
                            x: 2; y: 6
                            width: dayNum.implicitWidth + 12; height: 18; radius: 9
                            color: Theme.accent
                        }
                        Text {
                            id: dayNum
                            visible: day.d !== null
                            x: 8; y: 7
                            text: !day.d ? "" : day.d.day === 1 ? day.d.day + " " + day.d.month.slice(0, 3) : day.d.day
                            color: day.d?.today ? Theme.text : (day.d?.weekday ?? 0) >= 5 ? Theme.danger : Theme.muted
                            font { family: Theme.font; pixelSize: 11; weight: day.d?.today ? Font.Bold : Font.Medium }
                        }
                        Row {
                            visible: day.d !== null
                            x: 6; y: 28
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: day.d?.icon ?? ""
                                renderType: Text.NativeRendering
                                color: day.d?.color ?? Theme.text
                                font { family: Theme.iconFont; pixelSize: 20 }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: day.d?.max ?? ""
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                                }
                                Text {
                                    text: day.d?.min ?? ""
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: 11 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
