import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Подпись демо-режима: слева внизу основного монитора, поверх всего, клики проходят насквозь.
PanelWindow {
    id: win
    screen: Demo.targetScreen()
    anchors { left: true; bottom: true }
    margins { left: 48; bottom: 44 }
    implicitWidth: 760
    implicitHeight: 120
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "qs-demo"
    WlrLayershell.layer: WlrLayer.Overlay

    Item {
        id: box
        anchors { left: parent.left; bottom: parent.bottom }
        width: col.implicitWidth + 40
        height: col.implicitHeight + 32
        Behavior on width { NumberAnimation { duration: Theme.dSlow; easing.type: Easing.OutCubic } }
        opacity: Demo.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

        // смена подписи: старая уходит, новая поднимается на 10 px
        property real lift: 0
        Connections {
            target: Demo
            function onSerialChanged() { swap.restart() }
        }
        SequentialAnimation {
            id: swap
            NumberAnimation { target: col; property: "opacity"; to: 0; duration: Theme.dFast }
            ScriptAction { script: { stepText.text = Demo.step; titleText.text = Demo.title; subText.text = Demo.sub } }
            ParallelAnimation {
                NumberAnimation { target: col; property: "opacity"; to: 1; duration: Theme.dSlow; easing.type: Easing.OutCubic }
                NumberAnimation { target: box; property: "lift"; from: 10; to: 0; duration: 420; easing.type: Easing.OutCubic }
            }
        }

        Glass {
            anchors.fill: parent
            radius: 20
            color: Theme.glassStrong
            interactive: false
            followCursor: false
        }
        Column {
            id: col
            x: 20
            y: 16 + box.lift
            spacing: 4
            Text {
                id: stepText
                text: Demo.step
                color: Theme.primary
                font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold; letterSpacing: 2; features: ({ "tnum": 1 }) }
            }
            Text {
                id: titleText
                text: Demo.title
                color: Theme.text
                font { family: Theme.font; pixelSize: 26; weight: Font.DemiBold }
            }
            Text {
                id: subText
                width: Math.min(implicitWidth, 680)
                elide: Text.ElideRight
                text: Demo.sub
                color: Theme.muted
                font { family: Theme.font; pixelSize: 15 }
            }
        }
    }
}
