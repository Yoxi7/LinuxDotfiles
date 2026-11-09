import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Окно запроса пароля polkit в стекле. flow — AuthFlow из PolkitAgent (в превью — макет с теми же полями).
PanelWindow {
    id: win
    required property var flow                 // AuthFlow (в превью — макет)
    property bool preview: false
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: preview ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.flow?.cancelAuthenticationRequest()

        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

        Glass {
            id: card
            anchors.centerIn: parent
            width: 440
            height: col.implicitHeight + 48
            radius: 28
            color: Theme.glassStrong
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 14

                Row {
                    spacing: 12
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        Text { anchors.centerIn: parent; text: ""; color: Theme.primary; font { family: Theme.iconFont; pixelSize: 17 } }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Требуется подтверждение"; color: Theme.text; font { family: Theme.font; pixelSize: 16; weight: Font.DemiBold } }
                        Text { text: "Для этого действия нужны права администратора"; color: Theme.muted; font { family: Theme.font; pixelSize: 12 } }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.flow?.message ?? ""
                    color: Theme.text
                    font { family: Theme.font; pixelSize: 13 }
                }

                // учётные записи, если можно выбрать
                Row {
                    visible: (win.flow?.identities?.length ?? 0) > 1
                    spacing: 6
                    Repeater {
                        model: win.flow?.identities ?? []
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool on: win.flow?.selectedIdentity === modelData
                            height: 30; width: idt.implicitWidth + 20; radius: 15
                            color: on ? Theme.selected : Theme.weak
                            Text { id: idt; anchors.centerIn: parent; text: modelData.displayName ?? String(modelData); color: on ? Theme.base : Theme.text; font { family: Theme.font; pixelSize: 12 } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.flow.selectedIdentity = modelData }
                        }
                    }
                }

                Text {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: win.flow?.supplementaryMessage ?? ""
                    color: win.flow?.supplementaryIsError ? Theme.danger : Theme.muted
                    font { family: Theme.font; pixelSize: 12 }
                }

                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 14
                    color: Theme.weak
                    border { width: 2; color: win.flow?.failed ? Theme.danger : Theme.primary }
                    TextInput {
                        id: pw
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: win.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 15 }
                        focus: true
                        enabled: win.flow?.isResponseRequired ?? false
                        Component.onCompleted: forceActiveFocus()
                        onEnabledChanged: if (enabled) { text = ""; forceActiveFocus() }
                        onAccepted: { if (win.flow) win.flow.submit(text); text = "" }
                        Keys.onEscapePressed: win.flow?.cancelAuthenticationRequest()
                        Text {
                            visible: pw.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.flow?.inputPrompt || "Пароль"
                            color: Theme.faint
                            font { family: Theme.font; pixelSize: 14 }
                        }
                    }
                }
                Text {
                    visible: win.flow?.failed ?? false
                    text: "Неверный пароль. Повторите ввод"
                    color: Theme.danger
                    font { family: Theme.font; pixelSize: 12 }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Rectangle {
                        height: 38; width: 110; radius: 19
                        color: cm.containsMouse ? Theme.strong : Theme.weak
                        Text { anchors.centerIn: parent; text: "Отмена"; color: Theme.text; font { family: Theme.font; pixelSize: 13 } }
                        MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.flow?.cancelAuthenticationRequest() }
                    }
                    Rectangle {
                        height: 38; width: 130; radius: 19
                        color: Theme.primary
                        Text { anchors.centerIn: parent; text: "Подтвердить"; color: Theme.base; font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (win.flow) win.flow.submit(pw.text); pw.text = "" } }
                    }
                }
            }
        }
    }
}
