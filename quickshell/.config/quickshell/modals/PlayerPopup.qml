pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs

// Плеер (cider-ctl: Яндекс Музыка / Cider): размытая обложка фоном, крупная обложка,
// прогресс с перемоткой (клик / перетаскивание), управление, громкость плеера.
// Пробел — пауза, ←/→ — трек назад/вперёд, ↑/↓ — громкость.
ModalWindow {
    id: root
    name: "player"
    dropdown: true
    cardWidth: 400
    cardHeight: col.implicitHeight + 40

    Component.onCompleted: Player.refreshVolume(false)

    function fmt(sec) {
        const s = Math.max(0, Math.floor(sec))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    onKeyPressed: e => {
        if (e.key === Qt.Key_Space) { Player.toggle(); e.accepted = true }
        else if (e.key === Qt.Key_Right) { Player.next(); e.accepted = true }
        else if (e.key === Qt.Key_Left) { Player.previous(); e.accepted = true }
        else if (e.key === Qt.Key_Up) { Player.setVolume(Player.volume + 0.05); e.accepted = true }
        else if (e.key === Qt.Key_Down) { Player.setVolume(Player.volume - 0.05); e.accepted = true }
        else if (e.key === Qt.Key_L || e.key === Qt.Key_F) { Player.toggleLike(); e.accepted = true }
    }

    // ── фон: обложка, размытая и притемнённая (по форме карточки)
    ClippingRectangle {
        anchors { fill: parent; margins: 1 }
        radius: 27
        color: "transparent"
        Image {
            id: bg
            anchors.fill: parent
            source: Player.art
            sourceSize { width: 150; height: 150 }
            fillMode: Image.PreserveAspectCrop
            cache: false
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: bg
            visible: bg.status === Image.Ready
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: 0.3
            brightness: -0.25
            opacity: 0.75
        }
        // затемнение снизу — под кнопками и текстом
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.05) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.45) }
            }
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
        spacing: 16

        // обложка + текст
        Row {
            width: col.width
            spacing: 16
            Cover {
                size: 120
                radius: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: col.width - 120 - 16
                spacing: 4
                Text {
                    width: parent.width
                    text: Player.playerName
                    color: Theme.primary
                    font { family: Theme.font; pixelSize: 10; weight: Font.Bold; capitalization: Font.AllUppercase; letterSpacing: 1 }
                }
                Text {
                    width: parent.width
                    text: Player.title || "Ничего не играет"
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 19; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    text: Player.artist
                    elide: Text.ElideRight
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font { family: Theme.font; pixelSize: 14 }
                }
                Text {
                    width: parent.width
                    visible: Player.album !== "" && Player.album !== Player.title
                    text: Player.album
                    elide: Text.ElideRight
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }

        // прогресс: клик / перетаскивание — перемотка
        Column {
            width: col.width
            spacing: 6
            visible: Player.duration > 0
            Item {
                id: bar
                width: parent.width
                height: 14
                property real dragPos: -1          // пока тянем — показываем это, а не плеер
                readonly property real frac: dragPos >= 0 ? dragPos : Math.min(1, Player.livePosition / Math.max(1, Player.duration))
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: seekMouse.containsMouse || seekMouse.pressed ? 8 : 5
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.18)
                    Behavior on height { NumberAnimation { duration: Theme.dFast } }
                    Rectangle {
                        width: Math.max(parent.height, parent.width * bar.frac)
                        height: parent.height
                        radius: height / 2
                        color: Theme.selected
                    }
                }
                MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: e => bar.dragPos = Math.max(0, Math.min(1, e.x / width))
                    onPositionChanged: e => { if (pressed) bar.dragPos = Math.max(0, Math.min(1, e.x / width)) }
                    onReleased: { Player.seek(bar.dragPos * Player.duration); bar.dragPos = -1 }
                }
            }
            Item {
                width: parent.width
                height: 14
                Text {
                    text: root.fmt(bar.frac * Player.duration)
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                }
                Text {
                    anchors.right: parent.right
                    text: "-" + root.fmt(Player.duration * (1 - bar.frac))
                    color: Theme.muted
                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                }
            }
        }

        // управление
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20
            component Btn: Rectangle {
                id: btn
                property string icon
                property int size: 48
                property bool primary: false
                property color iconColor: primary ? Theme.base : Theme.text
                signal clicked
                width: size; height: size; radius: size / 2
                color: primary ? Theme.selected : btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                scale: btnMouse.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: Theme.dFast } }
                Behavior on color { ColorAnimation { duration: Theme.dFast } }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: btn.icon === "" ? 2 : 0   // ▶ визуально по центру
                    text: btn.icon
                    color: btn.iconColor
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    font { family: Theme.iconFont; pixelSize: btn.size * 0.38 }
                }
                MouseArea { id: btnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
            }
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: ""; onClicked: Player.previous() }
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: Player.playing ? "" : ""; size: 64; primary: true; onClicked: Player.toggle() }
            Btn { anchors.verticalCenter: parent.verticalCenter; icon: ""; onClicked: Player.next() }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                icon: Player.liked ? "" : ""
                iconColor: Player.liked ? Theme.danger : Theme.text
                onClicked: Player.toggleLike()
            }
        }

        // громкость плеера
        Item {
            width: col.width
            height: 20
            Text {
                id: volLow
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: ""
                color: Theme.muted
                font { family: Theme.iconFont; pixelSize: 13 }
            }
            Item {
                id: vol
                anchors { left: volLow.right; leftMargin: 12; right: volHigh.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                height: 14
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: volMouse.containsMouse || volMouse.pressed ? 8 : 5
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.18)
                    Behavior on height { NumberAnimation { duration: Theme.dFast } }
                    Rectangle {
                        width: Math.max(parent.height, parent.width * Math.min(1, Player.volume))
                        height: parent.height
                        radius: height / 2
                        color: Theme.text
                    }
                }
                MouseArea {
                    id: volMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: e => Player.setVolume(e.x / width)
                    onPositionChanged: e => { if (pressed) Player.setVolume(e.x / width) }
                    onWheel: w => Player.setVolume(Player.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))
                }
            }
            Text {
                id: volHigh
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: ""
                color: Theme.muted
                font { family: Theme.iconFont; pixelSize: 13 }
            }
        }
    }
}
