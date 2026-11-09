import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// OSD раскладки: крупно сверху по центру монитора с фокусом, ~0.9 с, клики насквозь
PanelWindow {
    screen: Demo.active ? Demo.targetScreen() : Theme.primaryScreen()
    anchors.top: true
    margins.top: 120
    implicitWidth: 220
    implicitHeight: 150
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-osd-layout"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    Glass {
        id: pill
        anchors.fill: parent
        radius: 36
        color: Theme.glassStrong
        property bool entered: false
        Component.onCompleted: entered = true
        scale: entered && Mango.osdShown ? 1 : 0.94
        opacity: entered && Mango.osdShown ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Mango.osdShown ? Theme.dBase : Theme.dExit; easing.type: Mango.osdShown ? Easing.OutCubic : Easing.InCubic } }
        Behavior on opacity { NumberAnimation { duration: Mango.osdShown ? Theme.dFast : Theme.dExit } }

        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Mango.layoutShort
                color: Theme.text
                font { family: Theme.font; pixelSize: 64; weight: Font.Bold; letterSpacing: 2 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Mango.layoutName
                color: Theme.primary
                font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            }
        }
    }
}
