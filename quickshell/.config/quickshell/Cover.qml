import QtQuick
import Quickshell.Widgets
import qs

// Обложка трека из cider-ctl (маленькая превьюшка), со скруглением; нет обложки — нота
ClippingRectangle {
    id: root
    property int size: 22
    property bool showPause: false
    width: size
    height: size
    radius: 6
    color: Theme.strong

    Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: "󰝚"
        color: Theme.muted
        font { family: Theme.iconFont; pixelSize: root.size * 0.5 }
    }
    Image {
        id: img
        anchors.fill: parent
        source: Player.art
        sourceSize { width: root.size * 2; height: root.size * 2 }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
    Rectangle {
        anchors.fill: parent
        visible: root.showPause && !Player.playing
        color: "#99000000"
        Text {
            anchors.centerIn: parent
            text: ""
            color: Theme.text
            font { family: Theme.iconFont; pixelSize: root.size * 0.45 }
        }
    }
}
