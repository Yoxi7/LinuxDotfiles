pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick.Effects
import qs

// Системный трей: ЛКМ — активировать, ПКМ — меню, СКМ — вторичное действие.
// Значки серые (полутона рисунка сохраняются) — цвет возвращается при наведении; подсказка — имя программы.
Row {
    id: root
    required property var window
    readonly property int count: repeater.count
    spacing: 10
    anchors.verticalCenter: parent?.verticalCenter

    function trigger(query, button) {
        const q = String(query ?? "").trim().toLowerCase()
        const items = SystemTray.items.values
        if (!items || items.length === 0) return "err: системный трей пуст"
        let idx = -1
        if (/^\d+$/.test(q)) {
            const n = parseInt(q)
            if (n >= 0 && n < items.length) idx = n
        }
        if (idx < 0) {
            for (let i = 0; i < items.length; i++) {
                const it = items[i]
                const hay = ((it.id ?? "") + " " + (it.title ?? "") + " " + (it.tooltipTitle ?? "")).toLowerCase()
                if (q === "" || hay.indexOf(q) >= 0) { idx = i; break }
            }
        }
        if (idx < 0) return "err: значок трея не найден: " + query
        const item = items[idx]
        const del = repeater.itemAt(idx)
        const b = (button || "left").toLowerCase()
        if (b === "middle" || b === "secondary") item.secondaryActivate()
        else if (b === "up") item.scroll(120, false)
        else if (b === "down") item.scroll(-120, false)
        else if (b === "right" || b === "menu" || item.onlyMenu) {
            if (item.hasMenu && del) del.menuOpen = !del.menuOpen
            else item.activate()
        } else {
            item.activate()
        }
        return "ok: " + (item.tooltipTitle || item.title || item.id) + " (" + b + ")"
    }

    Tip { id: tip }

    Repeater {
        id: repeater
        model: SystemTray.items

        IconImage {
            id: icon
            required property SystemTrayItem modelData
            implicitSize: 18
            source: modelData.icon
            anchors.verticalCenter: parent.verticalCenter
            layer.enabled: true
            layer.effect: MultiEffect {
                saturation: iconMouse.containsMouse ? 0 : -1
                brightness: iconMouse.containsMouse ? 0 : 0.08
                Behavior on saturation { NumberAnimation { duration: Theme.dBase } }
                Behavior on brightness { NumberAnimation { duration: Theme.dBase } }
            }
            opacity: iconMouse.containsMouse ? 1 : 0.86

            // меню — наше, в стекле (DBusMenu)
            property bool menuOpen: false
            LazyLoader {
                active: icon.menuOpen
                TrayMenu {
                    screen: root.window.screen
                    menu: icon.modelData.menu
                    anchorX: icon.mapToItem(null, icon.width / 2, 0).x + 10
                    onDismissed: icon.menuOpen = false
                }
            }
            MouseArea {
                id: iconMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onContainsMouseChanged: tip.request(containsMouse ? icon : null,
                    icon.modelData.tooltipTitle || icon.modelData.title || icon.modelData.id)
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: e => {
                    const item = icon.modelData
                    if (e.button === Qt.MiddleButton) item.secondaryActivate()
                    else if (e.button === Qt.RightButton || item.onlyMenu) { if (item.hasMenu) icon.menuOpen = !icon.menuOpen }
                    else item.activate()
                }
                onWheel: w => icon.modelData.scroll(w.angleDelta.y, false)
            }
        }
    }
}
