import QtQuick
import qs

// CPU / GPU для MiniDash, как в окне «Система»: значок, загрузка, крупная температура цветом,
// график за 2 минуты (Spark) и строка фактов (мощность, частота…).
Column {
    id: chip
    property string icon
    property string title
    property real temp
    property int warm
    property int hot
    property real load
    property string loadKey
    property string tempKey
    property var facts: []
    property int sparkH: 68

    width: parent ? parent.width : 0
    spacing: 6

    Item {
        width: parent.width
        height: 46
        Text {
            id: chipIcon
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: chip.icon
            color: Theme.primary
            font { family: Theme.iconFont; pixelSize: 26 }
        }
        Column {
            anchors { left: chipIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            Text { text: chip.title; color: Theme.text; font { family: Theme.font; pixelSize: 18; weight: Font.DemiBold } }
            Text { text: "загрузка " + Math.round(chip.load) + "%"; color: chip.load >= 90 ? Theme.danger : Theme.muted; font { family: Theme.font; pixelSize: 15; features: ({ "tnum": 1 }) } }
        }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: Math.round(chip.temp) + "°"
            color: chip.temp >= chip.hot ? Theme.danger : chip.temp >= chip.warm ? Theme.warning : Theme.text
            font { family: Theme.font; pixelSize: 38; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
        }
    }
    Spark {
        width: parent.width
        height: chip.sparkH
        labelPx: 13
        history: Cooling.history
        loadKey: chip.loadKey
        tempKey: chip.tempKey
    }
    Flow {
        width: parent.width
        spacing: 14
        Repeater {
            model: chip.facts
            Text { required property string modelData; text: modelData; color: Theme.muted; font { family: Theme.font; pixelSize: 15; features: ({ "tnum": 1 }) } }
        }
    }
}
