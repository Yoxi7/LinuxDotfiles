import QtQuick
import Quickshell
import qs

// Идёт запись экрана (qs-record): мигающая точка и время; клик — остановить
Item {
    id: root
    anchors.verticalCenter: parent?.verticalCenter
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    property real now: Date.now()

    Timer { interval: 1000; running: Shot.recording; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }

    Row {
        id: row
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10; height: 10; radius: 5
            color: Theme.danger
            SequentialAnimation on opacity {
                running: Shot.recording
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const s = Math.max(0, Math.floor((root.now - Shot.recordStart) / 1000))
                return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
            }
            color: Theme.text
            font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold; features: ({ "tnum": 1 }) }
        }
    }
    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-record", "--stop"])
    }
}
