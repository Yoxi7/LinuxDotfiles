pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Меню значка трея (DBusMenu) в нашем стекле. Полноэкранный прозрачный слой ловит клик мимо.
//   TrayMenu { menu: item.menu; screen: …; anchorX: …; onClosed: … }
PanelWindow {
    id: win
    required property var menu                 // QsMenuHandle
    property real anchorX: 0                   // центр иконки в координатах экрана
    signal dismissed

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property var stack: []                     // уровни подменю: [{ handle, title }]
    readonly property var cur: stack.length ? stack[stack.length - 1] : { handle: win.menu, title: "" }

    QsMenuOpener { id: opener; menu: win.cur.handle }

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.dismissed()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: win.dismissed() }

        Glass {
            id: card
            x: Math.max(10, Math.min(parent.width - width - 10, win.anchorX - width / 2))
            y: Theme.barHeight + 14
            width: 250
            height: list.implicitHeight + 16
            radius: 18
            color: Theme.glassStrong
            MouseArea { anchors.fill: parent }

            property bool entered: false
            Component.onCompleted: entered = true
            opacity: entered ? 1 : 0
            scale: entered ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
            Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

            Column {
                id: list
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                spacing: 1

                // назад из подменю
                Rectangle {
                    visible: win.stack.length > 0
                    width: parent.width; height: 34; radius: 9
                    color: bm.containsMouse ? Theme.strong : "transparent"
                    Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } text: "   " + win.cur.title; color: Theme.muted; font { family: Theme.font; pixelSize: 13 } }
                    MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.stack = win.stack.slice(0, -1) }
                }

                Repeater {
                    model: opener.children
                    delegate: Item {
                        id: row
                        required property var modelData            // QsMenuEntry
                        width: list.width
                        height: modelData.isSeparator ? 9 : 34

                        Rectangle {
                            visible: row.modelData.isSeparator
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.1)
                        }
                        Rectangle {
                            visible: !row.modelData.isSeparator
                            anchors.fill: parent
                            radius: 9
                            color: rm.containsMouse && row.modelData.enabled ? Theme.strong : "transparent"
                            IconImage {
                                id: ri
                                visible: source !== ""
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                implicitSize: 16
                                source: row.modelData.icon
                            }
                            Text {
                                anchors { left: parent.left; leftMargin: ri.visible ? 34 : 12; right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: (row.modelData.buttonType !== 0 && row.modelData.checkState === 2 ? "✓  " : "") + row.modelData.text.replace(/&(.)/g, "$1")
                                color: row.modelData.enabled ? Theme.text : Theme.faint
                                font { family: Theme.font; pixelSize: 13 }
                            }
                            Text {
                                visible: row.modelData.hasChildren
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: ""
                                color: Theme.muted
                                font { family: Theme.iconFont; pixelSize: 11 }
                            }
                            MouseArea {
                                id: rm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (!row.modelData.enabled) return
                                    if (row.modelData.hasChildren) win.stack = win.stack.concat([{ handle: row.modelData, title: row.modelData.text }])
                                    else { row.modelData.triggered(); win.dismissed() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
