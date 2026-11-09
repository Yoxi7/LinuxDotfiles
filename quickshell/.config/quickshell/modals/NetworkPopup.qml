import QtQuick
import Quickshell
import Quickshell.Networking
import qs

// Сеть: проводные и Wi-Fi устройства, список точек доступа, подключение (пароль — в поле ниже).
ModalWindow {
    id: root
    name: "network"
    cardWidth: 420
    cardHeight: Math.min(560, col.implicitHeight + 48)
    dropdown: true

    property var pending: null          // WifiNetwork, ждущая пароль

    Flickable {
        anchors { fill: parent; margins: 20 }
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 10

            Text { text: "Сеть"; color: Theme.text; font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold } }
            Text {
                text: Networking.connectivity !== undefined ? "Интернет: " + ({ Full: "есть доступ", Limited: "ограничен", Portal: "нужен вход через браузер", None: "нет доступа", Unknown: "не определено" }[NetworkConnectivity.toString(Networking.connectivity)] ?? NetworkConnectivity.toString(Networking.connectivity)) : ""
                color: Theme.faint
                font { family: Theme.font; pixelSize: 12 }
            }

            Repeater {
                model: Networking.devices
                Column {
                    id: dev
                    required property var modelData
                    readonly property bool isWifi: modelData.type === DeviceType.Wifi
                    width: col.width
                    spacing: 6

                    Rectangle {
                        width: parent.width; height: 52; radius: 14
                        color: Theme.weak
                        Text {
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: dev.isWifi ? "\uf1eb" : "\u{f0200}"
                            color: dev.modelData.connected ? Theme.primary : Theme.muted
                            font { family: Theme.iconFont; pixelSize: 17 }
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 46; verticalCenter: parent.verticalCenter }
                            Text { text: dev.modelData.name; color: Theme.text; font { family: Theme.font; pixelSize: 13; weight: Font.Medium } }
                            Text {
                                text: dev.modelData.connected ? "подключено" + (dev.modelData.linkSpeed > 0 ? " · " + dev.modelData.linkSpeed + " Мбит/с" : "") : "не подключено"
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11 }
                            }
                        }
                    }

                    // точки доступа
                    Repeater {
                        model: dev.isWifi ? dev.modelData.networks : []
                        Rectangle {
                            id: ap
                            required property var modelData
                            width: dev.width; height: 40; radius: 10
                            color: apm.containsMouse ? Theme.strong : "transparent"
                            Text {
                                anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 90; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: ap.modelData.name
                                color: ap.modelData.connected ? Theme.primary : Theme.text
                                font { family: Theme.font; pixelSize: 13; weight: ap.modelData.connected ? Font.DemiBold : Font.Normal }
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                text: Math.round(ap.modelData.signalStrength * 100) + "%" + (ap.modelData.known ? " ✓" : "")
                                color: Theme.faint
                                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                            }
                            MouseArea {
                                id: apm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (ap.modelData.connected) ap.modelData.disconnect()
                                    else if (ap.modelData.known || ap.modelData.security === WifiSecurityType.Open) ap.modelData.connect()
                                    else root.pending = ap.modelData
                                }
                            }
                        }
                    }
                }
            }

            // пароль для новой защищённой сети
            Rectangle {
                visible: root.pending !== null
                width: parent.width; height: 44; radius: 14
                color: Theme.weak
                border { width: 2; color: Theme.primary }
                TextInput {
                    id: psk
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 14 }
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                    onAccepted: { if (root.pending) root.pending.connectWithPsk(text); root.pending = null }
                    Keys.onEscapePressed: root.pending = null
                    Text {
                        visible: psk.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Пароль для «" + (root.pending?.name ?? "") + "» — Enter"
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 13 }
                    }
                }
            }
        }
    }
}
