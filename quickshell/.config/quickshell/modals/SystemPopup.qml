pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// «Система»: CPU и GPU (температуры, загрузка, мощность, частоты, графики за 2 минуты),
// память и охлаждение — выбор профиля вентиляторов CoolerControl и обороты.
ModalWindow {
    id: root
    name: "system"
    dropdown: true
    cardWidth: 440
    cardHeight: col.implicitHeight + 32

    function heat(t, warm, hot) { return t >= hot ? Theme.danger : t >= warm ? Theme.warning : Theme.text }
    function ghz(mhz) { return (mhz / 1000).toFixed(2) + " ГГц" }
    function fanName(f) {
        if (/pump/i.test(f.label)) return "Помпа"
        const m = /^fan(\d+)$/.exec(f.label)
        return m ? "Вентилятор " + m[1] : f.label
    }

    component Module: Glass {
        radius: 12                 // концентрично: окно 28 − отступ 16
        // вложенное стекло: плотность держат карточки, а не окно; кромка — та же направленная фаска, но тише
        color: Qt.rgba(0, 0, 0, 0.22)
        sheen: false
        interactive: false
        fresnel: 0.5
        rimColor: Qt.rgba(1, 1, 1, 0.07)
        glintColor: Qt.rgba(1, 1, 1, 0.55)
        rimWidth: 1
    }
    // маленькая подпись-значение: «80 Вт», «4.70 ГГц»
    component Fact: Row {
        property string icon
        property string value
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            color: Theme.faint
            font { family: Theme.iconFont; pixelSize: 11 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: Theme.muted
            font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
        }
    }
    // карточка процессора / видеокарты
    component Chip: Module {
        id: chip
        property string icon
        property string title
        property real temp
        property int warm
        property int hot
        property real load
        property string loadKey
        property string tempKey
        default property alias facts: factRow.data
        width: col.width
        height: chipCol.implicitHeight + 24

        Column {
            id: chipCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8

            Item {
                width: parent.width
                height: 40
                Text {
                    id: chipIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: chip.icon
                    color: Theme.primary
                    font { family: Theme.iconFont; pixelSize: 20 }
                }
                Column {
                    anchors { left: chipIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    Text {
                        text: chip.title
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
                    }
                    Text {
                        text: "загрузка " + Math.round(chip.load) + "%"
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                    }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: Math.round(chip.temp) + "°"
                    color: root.heat(chip.temp, chip.warm, chip.hot)
                    font { family: Theme.font; pixelSize: 30; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
                }
            }

            Spark {
                width: parent.width
                height: 70
                history: Cooling.history
                loadKey: chip.loadKey
                tempKey: chip.tempKey
            }

            Flow {
                id: factRow
                width: parent.width
                spacing: 14
            }
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 10

        Item {
            width: col.width
            height: 22
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Система"
                color: Theme.text
                font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                // легенда графиков
                Row {
                    spacing: 4
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 6; radius: 2; color: Theme.accent }
                    Text { text: "загрузка"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                }
                Row {
                    spacing: 4
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 2; color: Theme.primary }
                    Text { text: "температура"; color: Theme.faint; font { family: Theme.font; pixelSize: 11 } }
                }
            }
        }

        Text {
            visible: !Cooling.available
            width: col.width
            wrapMode: Text.Wrap
            text: "CoolerControl не отвечает — проверь, что coolercontrold запущен и токен в coolercontrol.token верный."
            color: Theme.danger
            font { family: Theme.font; pixelSize: 12 }
        }

        Chip {
            visible: Cooling.available
            icon: ""
            title: Cooling.cpuName || "Процессор"
            temp: Cooling.cpuTemp; warm: 75; hot: 88
            load: Cooling.cpuLoad
            loadKey: "cpuLoad"; tempKey: "cpuTemp"
            Fact { icon: "\u{f06a5}"; value: Math.round(Cooling.cpuPower) + " Вт" }
            Fact { icon: ""; value: root.ghz(Cooling.cpuFreq) }
            Fact { icon: ""; value: "CCD " + Math.round(Cooling.cpuCcd) + "°" }
        }

        // каждое ядро: загрузка, частота, температура — раз в 100 мс
        Module {
            width: col.width
            height: sysCores.implicitHeight + 24
            CoreGrid {
                id: sysCores
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            }
        }

        Chip {
            visible: Cooling.available
            icon: "\u{f08ae}"
            title: Cooling.gpuName || "Видеокарта"
            temp: Cooling.gpuTemp; warm: 72; hot: 83
            load: Cooling.gpuLoad
            loadKey: "gpuLoad"; tempKey: "gpuTemp"
            Fact { icon: "\u{f06a5}"; value: Math.round(Cooling.gpuPower) + " Вт" }
            Fact { icon: ""; value: root.ghz(Cooling.gpuFreq) }
            Fact { icon: ""; value: "горячая точка " + Math.round(Cooling.gpuHotspot) + "°" }
            Fact { icon: "\u{f0210}"; value: Cooling.gpuFanRpm > 0 ? Cooling.gpuFanRpm + " об/мин" : "вентилятор стоит" }
        }

        // память
        Module {
            width: col.width
            height: 52
            Text {
                id: ramIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: ""
                color: Theme.primary
                font { family: Theme.iconFont; pixelSize: 18 }
            }
            Column {
                anchors { left: ramIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 6
                Item {
                    width: parent.width
                    height: 16
                    Text {
                        text: "Память"
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.right: parent.right
                        text: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(0) + " ГиБ"
                        color: Theme.muted
                        font { family: Theme.font; pixelSize: 12; features: ({ "tnum": 1 }) }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.strong
                    Rectangle {
                        width: parent.width * SysInfo.mem / 100
                        height: parent.height
                        radius: 3
                        color: SysInfo.mem >= 90 ? Theme.danger : Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.dSlow } }
                    }
                }
            }
        }

        // охлаждение
        Module {
            visible: Cooling.available
            width: col.width
            height: coolCol.implicitHeight + 24
            Column {
                id: coolCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10

                Item {
                    width: parent.width
                    height: 18
                    Text {
                        text: "Охлаждение"
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.right: parent.right
                        text: Cooling.switching ? "применяю…" : Cooling.currentProfile ? "" : Cooling.managed.length ? "разные профили" : "нет управляемых вентиляторов"
                        color: Theme.faint
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }

                // профили — сегменты
                Rectangle {
                    visible: Cooling.profiles.length > 0
                    width: parent.width
                    height: 34
                    radius: 17
                    color: Theme.strong
                    Row {
                        anchors { fill: parent; margins: 3 }
                        Repeater {
                            model: Cooling.profiles
                            Rectangle {
                                id: seg
                                required property var modelData
                                readonly property bool on: Cooling.currentProfile === modelData.uid
                                readonly property bool busy: Cooling.switching === modelData.uid
                                width: (parent.width) / Cooling.profiles.length
                                height: parent.height
                                radius: height / 2
                                color: busy ? Theme.border : segMouse.containsMouse && !on ? Theme.strong : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                                // выбранный профиль — светлая капля: прозрачная, с яркой верхней гранью
                                Glass {
                                    anchors.fill: parent
                                    radius: height / 2
                                    opacity: seg.on ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.dBase } }
                                    color: Qt.rgba(1, 1, 1, 0.16)
                                    sheen: false
                                    interactive: false
                                    fresnel: 0.9
                                    rimColor: Qt.rgba(1, 1, 1, 0.22)
                                    glintColor: Qt.rgba(1, 1, 1, 0.9)
                                    rimWidth: 1.2
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: seg.modelData.name
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: seg.on ? Font.DemiBold : Font.Medium }
                                }
                                MouseArea {
                                    id: segMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!seg.on) Cooling.setProfile(seg.modelData.uid)
                                }
                            }
                        }
                    }
                }

                // обороты
                Repeater {
                    model: Cooling.fans
                    Item {
                        id: fan
                        required property var modelData
                        width: coolCol.width
                        height: 30
                        Text {
                            id: fanLabel
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 110
                            elide: Text.ElideRight
                            text: root.fanName(fan.modelData)
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        Rectangle {
                            anchors { left: fanLabel.right; leftMargin: 8; right: rpm.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            height: 6
                            radius: 3
                            color: Theme.strong
                            Rectangle {
                                width: parent.width * Math.min(1, fan.modelData.duty / 100)
                                height: parent.height
                                radius: 3
                                color: fan.modelData.profile ? Theme.accent : Theme.muted
                                Behavior on width { NumberAnimation { duration: Theme.dSlow } }
                            }
                        }
                        Text {
                            id: rpm
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 120
                            horizontalAlignment: Text.AlignRight
                            text: fan.modelData.rpm + " об/мин · " + Math.round(fan.modelData.duty) + "%"
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                        }
                    }
                }
            }
        }

        Item {
            width: col.width
            height: 20
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Открыть CoolerControl…"
                color: ccMouse.containsMouse ? Theme.text : Theme.muted
                font { family: Theme.font; pixelSize: 11 }
                MouseArea {
                    id: ccMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Modal.close(); Quickshell.execDetached(["coolercontrol"]) }
                }
            }
        }
    }
}
