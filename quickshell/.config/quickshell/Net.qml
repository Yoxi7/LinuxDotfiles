pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Активные подключения NetworkManager (для VPN / tun вроде mihomo) раз в 10 с
Singleton {
    id: root
    property var active: []      // [{ name, type, device }]
    readonly property var vpns: active.filter(c => /^(vpn|wireguard|tun)$/.test(c.type))
    readonly property var wired: active.find(c => c.type === "802-3-ethernet")
    readonly property var wifi: active.find(c => c.type === "802-11-wireless")

    Process {
        id: poll
        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: root.active = text.trim().split("\n").filter(l => l).map(l => {
                const p = l.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
                return { name: p[0], type: p[1], device: p[2] }
            }).filter(c => c.type !== "loopback")
        }
    }
    function refresh(): void { poll.running = true }
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }
}
