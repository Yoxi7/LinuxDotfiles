import QtQuick
import Quickshell
import qs

// CPU и GPU: загрузка + температура, и RAM. Данные — CoolerControl (Cooling),
// без него CPU берётся из /proc (SysInfo), GPU прячется. Клик — окно «Система».
Item {
    id: root
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property bool cc: Cooling.available
    readonly property int cpuLoad: cc ? Math.round(Cooling.cpuLoad) : SysInfo.cpu
    readonly property int cpuTemp: cc ? Math.round(Cooling.cpuTemp) : SysInfo.temp

    // цвет температуры: обычная → тёплая → горячая
    function heat(t, warm, hot) { return t >= hot ? Theme.danger : t >= warm ? Theme.warning : Theme.text }

    component Group: Row {
        id: group
        property string icon
        property int load
        property int temp
        property int warm: 70
        property int hot: 85
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: group.icon
            color: Theme.muted
            font { family: Theme.iconFont; pixelSize: 13 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: group.load + "%"
            color: group.load >= 90 ? Theme.danger : Theme.text
            font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: group.temp > 0
            text: group.temp + "°"
            color: root.heat(group.temp, group.warm, group.hot)
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
        }
    }

    Row {
        id: row
        spacing: 14
        anchors.verticalCenter: parent.verticalCenter
        Group { icon: ""; load: root.cpuLoad; temp: root.cpuTemp; warm: 75; hot: 88 }
        Group { visible: root.cc; icon: "\u{f08ae}"; load: Math.round(Cooling.gpuLoad); temp: Math.round(Cooling.gpuTemp); warm: 72; hot: 83 }
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Theme.muted
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: SysInfo.mem + "%"
                color: SysInfo.mem >= 90 ? Theme.danger : Theme.text
                font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const p = mapToItem(null, width / 2, 0)
            Modal.toggleAt("system", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
