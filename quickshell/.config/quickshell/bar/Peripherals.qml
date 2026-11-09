import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs

// Заряд беспроводной периферии (мышь, клавиатура, геймпад, наушники) из UPower; нет устройств — элемент скрыт.
Item {
    id: root
    readonly property var devs: {
        const out = []
        const m = UPower.devices.values
        for (let i = 0; i < m.length; i++) {
            const d = m[i]
            if (d.powerSupply || d.isLaptopBattery || !d.isPresent || d.percentage <= 0) continue
            out.push(d)
        }
        return out
    }
    visible: devs.length > 0
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    anchors.verticalCenter: parent?.verticalCenter

    function icon(d) {
        const t = UPowerDeviceType.toString(d.type).toLowerCase()
        return t.indexOf("mouse") >= 0 ? "\u{f037d}" : t.indexOf("keyboard") >= 0 ? "\uf11c" : t.indexOf("gaming") >= 0 ? "\uf11b"
             : t.indexOf("headset") >= 0 || t.indexOf("headphone") >= 0 ? "\uf025" : "\uf240"
    }

    Tip { id: tip }
    Row {
        id: row
        spacing: 10
        Repeater {
            model: root.devs
            Item {
                id: it
                required property var modelData
                readonly property int pct: Math.round(modelData.percentage * 100)
                implicitWidth: inner.implicitWidth
                implicitHeight: inner.implicitHeight
                width: implicitWidth
                height: implicitHeight
                Row {
                    id: inner
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.icon(it.modelData)
                        color: Theme.muted
                        font { family: Theme.iconFont; pixelSize: 13 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: it.pct + "%"
                        color: it.pct <= 15 ? Theme.danger : it.pct <= 30 ? Theme.warning : Theme.text
                        font { family: Theme.font; pixelSize: 13; features: ({ "tnum": 1 }) }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: tip.request(containsMouse ? it : null, (it.modelData.model || "Устройство") + " — " + it.pct + "%")
                }
            }
        }
    }
}
