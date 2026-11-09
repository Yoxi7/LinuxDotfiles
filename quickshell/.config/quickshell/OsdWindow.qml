import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// OSD громкости / микрофона / плеера внизу по центру монитора с фокусом. Живёт 1.5 с.
PanelWindow {
    id: win
    screen: Demo.active ? Demo.targetScreen() : Theme.primaryScreen()
    anchors.bottom: true
    margins.bottom: 90
    implicitWidth: 340
    implicitHeight: 64
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}          // клики проходят насквозь

    readonly property string label: Osd.kind === "player" ? Player.playerName || "Плеер"
                                  : Osd.kind === "mic" ? "Микрофон" : "Звук"

    Glass {
        id: pill
        anchors.fill: parent
        radius: height / 2
        property bool entered: false
        Component.onCompleted: entered = true
        opacity: entered && Osd.shown ? 1 : 0
        scale: entered && Osd.shown ? 1 : 0.96
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { duration: Osd.shown ? Theme.dFast : Theme.dExit } }
        Behavior on scale { NumberAnimation { duration: Osd.shown ? Theme.dBase : Theme.dExit; easing.type: Osd.shown ? Easing.OutCubic : Easing.InCubic } }

        // у плеера вместо значка — обложка трека
        Cover {
            visible: Osd.kind === "player"
            size: 38
            radius: 10
            anchors.centerIn: icon
        }
        Text {
            id: icon
            anchors { left: parent.left; leftMargin: Osd.kind === "player" ? 20 : 22; verticalCenter: parent.verticalCenter }
            width: Osd.kind === "player" ? 38 : 24
            opacity: Osd.kind === "player" ? 0 : 1
            horizontalAlignment: Text.AlignHCenter
            text: Osd.kind === "player" ? "󰝚"
                : Osd.kind === "mic" ? (Osd.muted ? "" : "")
                : Osd.muted ? "" : Osd.value > 0.5 ? "" : Osd.value > 0 ? "" : ""
            color: Osd.muted ? Theme.danger : Theme.text
            font { family: Theme.iconFont; pixelSize: 20 }
        }

        Column {
            anchors { left: icon.right; leftMargin: 14; right: percent.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 7
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: win.label
                color: Theme.muted
                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
            }
            Rectangle {
                width: parent.width
                height: 8
                radius: 4
                color: Theme.strong
                Rectangle {
                    width: Math.max(parent.height, parent.width * Math.min(1, Osd.value))
                    height: parent.height
                    radius: 4
                    color: Osd.muted ? Theme.faint : Theme.selected
                    Behavior on width { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
                }
            }
        }

        Text {
            id: percent
            anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
            width: 40
            horizontalAlignment: Text.AlignRight
            text: Osd.muted ? "выкл" : Math.round(Osd.value * 100) + "%"
            color: Theme.text
            font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            font.features: ({ "tnum": 1 })
        }
    }
}
