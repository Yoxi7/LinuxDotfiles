pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.WindowManager
import qs

// Все 10 тегов mango (ext-workspace): активный — светлая «линза»,
// занятые — яркие цифры с точкой, пустые — бледные.
Row {
    id: root
    required property ShellScreen screen
    spacing: 4
    anchors.verticalCenter: parent?.verticalCenter

    readonly property var projection: WindowManager.screenProjection(screen)
    // mango прячет пустые теги (shouldDisplay = false), но в списке они есть
    readonly property var byName: {
        const m = {}
        for (const w of projection?.windowsets ?? []) m[w.name] = w
        return m
    }

    // колесо: вниз — следующий тег, вверх — предыдущий (без перескока через край);
    // тачпад копит смещение до целого «щелчка»
    property real wheelAcc: 0
    // активный тег приходит от mango с задержкой — при быстрой прокрутке считаем от цели
    readonly property var mon: Mango.monitors[screen?.name] ?? null
    readonly property int activeNum: Mango.isHypr ? (mon?.tag ?? 1) : (parseInt(Object.values(byName).find(w => w.active)?.name) || 1)
    property int target: 0
    onActiveNumChanged: if (activeNum === target) target = 0
    function step(d) {
        const n = Math.max(1, Math.min(10, (target || activeNum) + d))
        target = n
        targetReset.restart()
        const ws = Mango.isHypr ? null : byName[String(n)]
        if (ws) ws.activate()
        else Mango.view(screen.name, n)
    }
    Timer { id: targetReset; interval: 600; onTriggered: root.target = 0 }   // цель не достигнута — забыть
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            root.wheelAcc += e.angleDelta.y
            while (Math.abs(root.wheelAcc) >= 120) {
                root.step(root.wheelAcc > 0 ? -1 : 1)
                root.wheelAcc -= Math.sign(root.wheelAcc) * 120
            }
        }
    }

    Repeater {
        model: 10

        Item {
            id: tag
            required property int index
            readonly property string name: String(index + 1)
            readonly property var ws: root.byName[name] ?? null
            readonly property bool active: Mango.isHypr ? root.activeNum === index + 1 : (ws?.active ?? false)
            readonly property bool occupied: Mango.isHypr ? ((root.mon?.counts?.[index] ?? 0) > 0) : (ws?.shouldDisplay ?? false)
            readonly property bool urgent: ws?.urgent ?? false
            anchors.verticalCenter: parent.verticalCenter
            width: active ? 34 : 22
            height: 24
            Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: tag.urgent ? Theme.danger : tag.active ? Theme.selected : mouse.containsMouse ? Theme.strong : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dFast } }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: tag.occupied && !tag.active ? -2 : 0
                text: tag.name
                color: tag.active || tag.urgent ? Theme.base : tag.occupied ? Theme.text : Theme.faint
                font { family: Theme.font; pixelSize: 12; weight: tag.active || tag.occupied ? Font.Bold : Font.Medium }
            }
            // точка под занятым неактивным тегом
            Rectangle {
                visible: tag.occupied && !tag.active && !tag.urgent
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
                width: 3; height: 3; radius: 1.5
                color: Theme.muted
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (tag.ws && !Mango.isHypr) ? tag.ws.activate() : Mango.view(root.screen.name, tag.index + 1)
            }
        }
    }
}
