import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs

// Значки состояния, как в строке меню macOS: одноцветные; цвет — только у настоящей проблемы
// (нет сети, микрофон выключен). Кто пишет микрофон / экран — маленькая точка слева
// (оранжевая — микрофон, фиолетовая — экран). Наведение — подсказка, что это и чьё.
// Клик по острову — пункт управления (обрабатывает Bar).
Row {
    id: root
    spacing: 12
    anchors.verticalCenter: parent?.verticalCenter

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool micMuted: source?.audio?.muted ?? false
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btDevices: (bt?.devices?.values ?? []).filter(d => d.connected)

    // приватность — список в Privacy.qml; здесь только точки и клик
    readonly property var micUsers: Privacy.mic.map(u => u.name)

    Tip { id: tip }

    component Glyph: Text {
        id: g
        property string tipText
        color: Qt.rgba(1, 1, 1, 0.86)
        font { family: Theme.iconFont; pixelSize: 15 }
        anchors.verticalCenter: parent?.verticalCenter
        HoverHandler { onHoveredChanged: tip.request(hovered ? g : null, g.tipText) }
    }

    // точки приватности: оранжевая — микрофон, фиолетовая — экран, зелёная — камера; клик — список
    Item {
        id: privacy
        visible: Privacy.count > 0
        anchors.verticalCenter: parent.verticalCenter
        width: dots.implicitWidth
        height: 16
        Row {
            id: dots
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Rectangle { visible: Privacy.mic.length > 0; width: 7; height: 7; radius: 3.5; color: "#ff9f0a" }
            Rectangle { visible: Privacy.screen.length > 0; width: 7; height: 7; radius: 3.5; color: "#bf5af2" }
            Rectangle { visible: Privacy.camera.length > 0; width: 7; height: 7; radius: 3.5; color: "#30d158" }
        }
        HoverHandler {
            id: privHover
            onHoveredChanged: tip.request(hovered ? privacy : null,
                [Privacy.mic.length ? "Микрофон: " + Privacy.mic.map(u => u.name).join(", ") : "",
                 Privacy.screen.length ? "Экран: " + Privacy.screen.map(u => u.name).join(", ") : "",
                 Privacy.camera.length ? "Камера: " + Privacy.camera.map(u => u.name).join(", ") : ""].filter(s => s).join("\n"))
        }
        MouseArea {
            anchors { fill: parent; margins: -6 }
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const p = privacy.mapToItem(null, privacy.width / 2, 0)
                Modal.toggleAt("privacy", p.x + 10, QsWindow.window?.screen ?? null)
            }
        }
    }

    Glyph {
        visible: Session.idleInhibit
        text: ""
        tipText: "Экран не гаснет"
    }
    Glyph {
        text: Net.wired ? "\u{f0200}" : Net.wifi ? "" : ""
        color: Net.wired || Net.wifi ? Qt.rgba(1, 1, 1, 0.86) : Theme.danger
        tipText: Net.wired ? "Сеть: " + Net.wired.name : Net.wifi ? "Wi-Fi: " + Net.wifi.name : "Нет подключения"
    }
    Glyph {
        visible: Net.vpns.length > 0
        text: ""
        tipText: "VPN: " + Net.vpns.map(v => v.name).join(", ")
    }
    Glyph {
        visible: root.btDevices.length > 0
        text: ""
        tipText: "Bluetooth: " + root.btDevices.map(d => d.name + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")).join("\n")
    }
    Glyph {
        visible: root.micMuted
        text: ""
        color: Theme.danger
        tipText: "Микрофон выключен"
    }
    Volume {
        id: vol
        HoverHandler {
            onHoveredChanged: tip.request(hovered ? vol : null,
                "Звук: " + (Pipewire.defaultAudioSink?.description || "—") + "\nколесо — громкость, СКМ — без звука")
        }
    }
}
