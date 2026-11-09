pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import qs

// Карточка уведомления — общая для всплывашек и центра уведомлений.
// ЛКМ — действие по умолчанию, ПКМ / × — убрать.
// Всплывашка — самостоятельное стекло, в центре уведомлений — плашка внутри карточки.
Glass {
    id: root
    required property var notif
    property bool popup: false          // всплывашка: уходит из всплывающих, но остаётся в истории
    signal done
    signal leave                        // всплывашка уходит: Toasts анимирует и убирает из списка

    readonly property bool critical: notif?.urgency === NotificationUrgency.Critical
    readonly property string imageSource: {
        const img = notif?.image ?? ""
        if (img) return img
        const icon = notif?.appIcon ?? ""
        if (!icon) return ""
        return icon.startsWith("/") || icon.includes("://") ? icon : Quickshell.iconPath(icon, true)
    }

    implicitHeight: content.implicitHeight + 24
    radius: 20
    sheen: popup
    color: popup ? (hover.hovered ? Theme.glassStrong : Theme.glass) : hover.hovered ? Theme.strong : Theme.weak
    rimColor: critical ? Theme.danger : popup ? Theme.rim : Theme.rimSoft

    function close() {
        if (popup) { leave(); done() }
        else notif?.dismiss()
    }
    function activate() {
        const def = (notif?.actions ?? []).find(a => a.identifier === "default")
        if (def) def.invoke()
        if (popup) { leave(); done() }
        else notif?.dismiss()
    }

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.close() : root.activate()
    }

    Row {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12

        Image {
            id: image
            visible: root.imageSource !== "" && status !== Image.Error
            width: visible ? 40 : 0
            height: 40
            source: root.imageSource
            sourceSize { width: 80; height: 80 }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }

        Column {
            width: parent.width - image.width - (image.visible ? parent.spacing : 0) - 22
            spacing: 3

            Text {
                width: parent.width
                text: (root.notif?.appName || "Уведомление") + (Notifs.timeOf(root.notif) ? "  ·  " + Notifs.timeOf(root.notif) : "")
                elide: Text.ElideRight
                color: Theme.faint
                font { family: Theme.font; pixelSize: 11 }
            }
            Text {
                width: parent.width
                text: root.notif?.summary ?? ""
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                color: root.critical ? Theme.danger : Theme.text
                font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: root.notif?.body ?? ""
                layer.enabled: Session.privacy
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; saturation: -0.5 }
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: root.popup ? 4 : 8
                elide: Text.ElideRight
                color: Theme.muted
                linkColor: Theme.primary
                font { family: Theme.font; pixelSize: 13 }
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Flow {
                width: parent.width
                spacing: 6
                topPadding: visible ? 4 : 0
                visible: actions.count > 0
                Repeater {
                    id: actions
                    model: (root.notif?.actions ?? []).filter(a => a.identifier !== "default" && a.text)
                    Rectangle {
                        id: action
                        required property var modelData
                        width: actionText.implicitWidth + 20
                        height: 26
                        radius: 9
                        color: actionMouse.containsMouse ? Theme.border : Theme.strong
                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: action.modelData.text
                            color: Theme.text
                            font { family: Theme.font; pixelSize: 12 }
                        }
                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { action.modelData.invoke(); root.close() }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors { top: parent.top; right: parent.right; margins: 10 }
        text: ""
        color: closeMouse.containsMouse ? Theme.text : Theme.faint
        font { family: Theme.iconFont; pixelSize: 12 }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
        }
    }
}
