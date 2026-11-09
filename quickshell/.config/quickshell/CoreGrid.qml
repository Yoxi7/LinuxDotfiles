import QtQuick
import qs

// Ядра в две колонки, как в htop: номер, полоса загрузки (плавная), частота и процент.
// Пока блок видим — Cores опрашивает систему каждые 100 мс.
Column {
    id: root
    spacing: 10

    property bool counted: false
    function track() {
        const want = visible
        if (want === counted) return
        counted = want
        Cores.users += want ? 1 : -1
    }
    onVisibleChanged: track()
    Component.onCompleted: track()
    Component.onDestruction: if (counted) Cores.users -= 1

    function heat(t) { return t >= 88 ? Theme.danger : t >= 75 ? Theme.warning : Theme.text }

    // заголовок: средняя загрузка, максимальная частота, температуры
    Item {
        width: root.width
        height: 20
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Ядра"
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14
            component Fact: Text {
                color: Theme.muted
                font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
            }
            Fact { text: Math.round(Cores.avgLoad * 100) + "% · до " + (Cores.maxFreq / 1000).toFixed(2) + " ГГц" }
            Fact { text: "Tctl " + Math.round(Cores.tctl) + "°"; color: root.heat(Cores.tctl); visible: Cores.tctl > 0 }
            Fact { text: "CCD " + Math.round(Cores.tccd) + "°"; color: root.heat(Cores.tccd); visible: Cores.tccd > 0 }
        }
    }

    Grid {
        id: grid
        columns: 2
        columnSpacing: 16
        rowSpacing: 5
        width: root.width
        flow: Grid.TopToBottom
        rows: Math.ceil(Cores.count / 2)

        Repeater {
            model: Cores.count
            Item {
                id: core
                required property int index
                readonly property real load: Cores.load[index] ?? 0
                readonly property real freq: Cores.freq[index] ?? 0
                width: (grid.width - grid.columnSpacing) / 2
                height: 16

                Text {
                    id: num
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 16
                    horizontalAlignment: Text.AlignRight
                    text: core.index
                    color: Theme.faint
                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                }
                Rectangle {
                    id: track
                    anchors { left: num.right; leftMargin: 8; right: freqText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    height: 6
                    radius: 3
                    color: Theme.strong
                    Rectangle {
                        width: Math.max(track.height, track.width * Math.min(1, core.load))
                        height: parent.height
                        radius: 3
                        color: core.load >= 0.9 ? Theme.danger : core.load >= 0.6 ? Theme.warning : Theme.accent
                        // опрос раз в 100 мс — полоса доезжает плавно, не дёргается
                        Behavior on width { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutQuad } }
                        Behavior on color { ColorAnimation { duration: Theme.dBase } }
                    }
                }
                Text {
                    id: freqText
                    anchors { right: pct.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    text: (core.freq / 1000).toFixed(2)
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                }
                Text {
                    id: pct
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(core.load * 100) + "%"
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                }
            }
        }
    }
}
