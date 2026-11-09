pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Выключатели Tuya: по строке на каждую клавишу; офлайн-устройства серые. Данные — из Tuya (локальный tuya-web).
ModalWindow {
    id: root
    name: "tuya"
    dropdown: true
    cardWidth: 380
    cardHeight: Math.min(560, col.implicitHeight + 44)

    Component.onCompleted: { Tuya.watching = true; Tuya.refresh(); again.start() }
    Timer { id: again; interval: 1500; onTriggered: Tuya.refresh() }   // сервис отдаёт кэш сразу и обновляет его в фоне
    Component.onDestruction: Tuya.watching = false

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
        spacing: 12

        Item {
            width: parent.width; height: 30
            Text {
                text: "Свет"
                color: Theme.text
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.font; pixelSize: 20; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Rectangle {
                    height: 28; radius: 14; width: offT.implicitWidth + 24
                    color: offM.containsMouse ? Theme.strong : Theme.weak
                    Text { id: offT; anchors.centerIn: parent; text: "Выключить всё"; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
                    MouseArea { id: offM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Tuya.allOff() }
                }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: refM.containsMouse ? Theme.strong : Theme.weak
                    Text {
                        id: refIcon
                        anchors.centerIn: parent
                        text: ""
                        color: Theme.text
                        font { family: Theme.iconFont; pixelSize: 13 }
                        RotationAnimator on rotation { running: Tuya.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running) refIcon.rotation = 0 }
                    }
                    MouseArea { id: refM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Tuya.refresh() }
                }
            }
        }

        Text {
            visible: Tuya.error !== ""
            width: parent.width
            text: Tuya.error
            wrapMode: Text.WordWrap
            color: Theme.danger
            font { family: Theme.font; pixelSize: 12 }
        }

        Repeater {
            model: Tuya.devices
            delegate: Column {
                id: dev
                required property var modelData
                width: col.width
                spacing: 6
                Text {
                    text: dev.modelData.name + (dev.modelData.online ? "" : " · офлайн")
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold }
                }
                Repeater {
                    model: dev.modelData.switches
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: dev.width; height: 48; radius: 12
                        color: modelData.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : rm.containsMouse ? Theme.strong : Theme.weak
                        Behavior on color { ColorAnimation { duration: Theme.dFast } }
                        Text {
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            text: dev.modelData.name + (dev.modelData.switches.length > 1 ? " · клавиша " + (row.index + 1) : "")
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 14 }
                        }
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 40; height: 22; radius: 11
                            color: row.modelData.on ? Theme.primary : Theme.faint
                            Rectangle {
                                y: 3; width: 16; height: 16; radius: 8; color: Theme.text
                                x: row.modelData.on ? 21 : 3
                                Behavior on x { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: rm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Tuya.set(dev.modelData.id, row.modelData.dp, !row.modelData.on)
                        }
                    }
                }
                Text {
                    visible: dev.modelData.switches.length === 0
                    text: dev.modelData.online ? "нет выключателей" : "не в сети — найдётся сам после включения (tuya resolve)"
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }
        Text {
            visible: Tuya.devices.length === 0 && Tuya.error === ""
            text: Tuya.loading ? "Загрузка…" : "Устройств нет"
            color: Theme.faint
            font { family: Theme.font; pixelSize: 13 }
        }
    }
}
