pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs

// Всплывающие уведомления: справа сверху на основном мониторе.
// Окно существует только пока есть что показать (LazyLoader в shell.qml).
PanelWindow {
    id: win
    screen: Demo.active ? Demo.targetScreen() : Theme.primaryScreen()
    anchors { top: true; right: true }
    margins { top: Theme.barHeight + 14; right: 10 }
    implicitWidth: 380
    implicitHeight: Math.max(1, column.implicitHeight)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: column }          // клики принимает только то, что реально нарисовано
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: column
        width: parent.width
        spacing: 8
        // остальные плавно сдвигаются, когда одна уходит
        move: Transition { NumberAnimation { properties: "y"; duration: Theme.dBase; easing.type: Easing.OutCubic } }

        Repeater {
            model: ScriptModel { values: Notifs.popups }

            NotifCard {
                id: card
                required property var modelData
                notif: modelData
                popup: true
                width: column.width
                // невидимая карточка не должна ни занимать место, ни ловить клики под собой
                visible: opacity > 0.01

                // вход: справа, с замедлением; уход: вправо и в прозрачность, потом убирается из списка
                property bool entered: false
                property bool leaving: false
                opacity: entered && !leaving ? 1 : 0
                x: entered && !leaving ? 0 : 40
                Component.onCompleted: entered = true
                function exit() {
                    if (leaving) return
                    leaving = true
                    exitTimer.start()
                }
                Timer { id: exitTimer; interval: Theme.dExit; onTriggered: Notifs.dropPopup(card.notif) }
                onLeave: exit()
                Behavior on opacity { NumberAnimation { duration: card.leaving ? Theme.dExit : Theme.dBase } }
                Behavior on x { NumberAnimation { duration: card.leaving ? Theme.dExit : Theme.dBase; easing.type: card.leaving ? Easing.InCubic : Easing.OutCubic } }

                // 5 с (или сколько попросило приложение); критические — пока не закроешь; наведение — пауза
                Timer {
                    running: !card.critical && !hover.hovered
                    interval: (card.notif?.expireTimeout ?? 0) > 0 ? card.notif.expireTimeout : 5000
                    onTriggered: card.exit()
                }
                HoverHandler { id: hover }
                // приложение само закрыло уведомление
                Connections {
                    target: card.notif
                    function onClosed() { card.exit() }
                }
            }
        }
    }
}
