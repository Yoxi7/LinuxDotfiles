pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

// Кто сейчас использует микрофон, экран и камеру. Клик по программе — сведения о её процессе
// нельзя открыть отсюда, поэтому в строке: значок, название, PID; «Завершить» — kill с подтверждением.
ModalWindow {
    id: root
    name: "privacy"
    dropdown: true
    cardWidth: 380
    cardHeight: col.implicitHeight + 32

    property int armedPid: -1

    readonly property var sections: [
        { key: "mic", title: "Микрофон", icon: "", tint: "#ff9f0a", users: Privacy.mic },
        { key: "screen", title: "Экран", icon: "", tint: "#bf5af2", users: Privacy.screen },
        { key: "camera", title: "Камера", icon: "", tint: "#30d158", users: Privacy.camera }
    ]

    function icon(u) {
        const key = u.binary || u.name
        return Quickshell.iconPath(DesktopEntries.heuristicLookup(key)?.icon ?? key.toLowerCase(), "application-x-executable")
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12

        Item {
            width: col.width
            height: 24
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Конфиденциальность"
                color: Theme.text
                font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold }
            }
        }

        // пусто
        Text {
            visible: Privacy.count === 0
            width: col.width
            wrapMode: Text.Wrap
            text: "Сейчас микрофон, экран и камеру никто не использует."
            color: Theme.muted
            font { family: Theme.font; pixelSize: 13 }
        }

        Repeater {
            model: root.sections
            Glass {
                id: sec
                required property var modelData
                visible: modelData.users.length > 0
                width: col.width
                height: visible ? secCol.implicitHeight + 16 : 0
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.22)
                sheen: false
                interactive: false
                fresnel: 0.5
                rimColor: Qt.rgba(1, 1, 1, 0.07)
                glintColor: Qt.rgba(1, 1, 1, 0.55)
                rimWidth: 1

                Column {
                    id: secCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 2

                    Row {
                        spacing: 8
                        leftPadding: 4
                        height: 24
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: sec.modelData.tint
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sec.modelData.title
                            color: Theme.muted
                            font { family: Theme.font; pixelSize: 12; weight: Font.DemiBold }
                        }
                    }

                    Repeater {
                        model: sec.modelData.users
                        Rectangle {
                            id: row
                            required property var modelData
                            width: secCol.width
                            height: 40
                            radius: 8
                            color: rowMouse.containsMouse ? Theme.strong : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.dFast } }
                            MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }
                            Image {
                                id: ico
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                width: 24; height: 24
                                sourceSize { width: 48; height: 48 }
                                source: root.icon(row.modelData)
                            }
                            Column {
                                anchors { left: ico.right; leftMargin: 12; right: kill.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.modelData.name
                                    color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (row.modelData.pid ? "PID " + row.modelData.pid : "") + (row.modelData.detail ? " · " + row.modelData.detail : "")
                                    color: Theme.faint
                                    font { family: Theme.font; pixelSize: 11; features: ({ "tnum": 1 }) }
                                }
                            }
                            // завершить процесс: два клика
                            Rectangle {
                                id: kill
                                visible: row.modelData.pid > 0
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                readonly property bool armed: root.armedPid === row.modelData.pid
                                width: armed ? armedText.implicitWidth + 20 : 28
                                height: 28
                                radius: 8
                                opacity: rowMouse.containsMouse || killMouse.containsMouse || armed ? 1 : 0
                                color: armed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22) : killMouse.containsMouse ? Theme.strong : "transparent"
                                Behavior on width { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
                                Text {
                                    id: armedText
                                    anchors.centerIn: parent
                                    text: kill.armed ? "завершить" : ""
                                    color: kill.armed ? Theme.danger : Theme.muted
                                    font { family: kill.armed ? Theme.font : Theme.iconFont; pixelSize: kill.armed ? 11 : 12; weight: kill.armed ? Font.DemiBold : Font.Normal }
                                }
                                MouseArea {
                                    id: killMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (kill.armed) { Quickshell.execDetached(["kill", String(row.modelData.pid)]); root.armedPid = -1 }
                                        else { root.armedPid = row.modelData.pid; disarm.restart() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Timer { id: disarm; interval: 2500; onTriggered: root.armedPid = -1 }
    }
}
