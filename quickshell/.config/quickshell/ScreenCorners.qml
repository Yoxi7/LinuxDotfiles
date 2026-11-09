import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs

// Скруглённые углы экрана: на каждом мониторе слой Overlay (выше окон, в том числе полноэкранных игр) с четырьмя
// чёрными уголками. Клики и фокус не перехватывает. На OLED чёрный — это выключенные пиксели.
Variants {
    model: Quickshell.screens

    PanelWindow {
        required property var modelData
        screen: modelData
        visible: Session.corners
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "qs-corners"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        readonly property real r: Session.cornerRadius

        // уголок: треугольник с вырезанной дугой; rot — поворот вокруг центра квадрата r×r
        component Corner: Shape {
            id: c
            property bool isR: false
            property bool isB: false
            width: parent.width; height: parent.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "black"
                strokeColor: "transparent"
                strokeWidth: 0
                startX: c.isR ? c.width : 0
                startY: c.isB ? c.height : 0
                PathLine { x: c.isR ? c.width - r : r; y: c.isB ? c.height : 0 }
                PathArc {
                    x: c.isR ? c.width : 0
                    y: c.isB ? c.height - r : r
                    radiusX: r; radiusY: r
                    direction: (c.isR === c.isB) ? PathArc.Counterclockwise : PathArc.Clockwise
                }
                PathLine { x: c.isR ? c.width : 0; y: c.isB ? c.height : 0 }
            }
        }
        Corner { isR: false; isB: false }
        Corner { isR: true; isB: false }
        Corner { isR: false; isB: true }
        Corner { isR: true; isB: true }
    }
}
