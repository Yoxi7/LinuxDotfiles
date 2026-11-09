import QtQuick
import Quickshell
import Quickshell.Networking
import qs

// Сеть в баре: проводное / Wi-Fi + скорость линка; клик — окно «Сеть».
Item {
    id: root
    readonly property var wifi: {
        for (let i = 0; i < Networking.devices.values.length; i++) { const d = Networking.devices.values[i]; if (d.type === DeviceType.Wifi) return d }
        return null
    }
    readonly property var wired: {
        for (let i = 0; i < Networking.devices.values.length; i++) { const d = Networking.devices.values[i]; if (d.type === DeviceType.Wired) return d }
        return null
    }
    readonly property bool online: (wired?.connected ?? false) || (wifi?.connected ?? false)
    implicitWidth: ic.implicitWidth
    implicitHeight: 20
    anchors.verticalCenter: parent?.verticalCenter

    Text {
        id: ic
        anchors.centerIn: parent
        text: (root.wired?.connected ?? false) ? "\u{f0200}" : (root.wifi?.connected ?? false) ? "\uf1eb" : "\uf127"
        color: root.online ? Theme.text : Theme.danger
        font { family: Theme.iconFont; pixelSize: 15 }
    }
    Tip { id: tip }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: tip.request(containsMouse ? root : null,
            root.online ? ((root.wired?.connected ?? false) ? "Проводная сеть" : "Wi-Fi") : "Нет сети")
        onClicked: {
            const p = root.mapToItem(null, root.width / 2, 0)
            Modal.toggleAt("network", p.x + 10, QsWindow.window?.screen ?? null)
        }
    }
}
