pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

// Сервер уведомлений (org.freedesktop.Notifications).
// popups — то, что сейчас всплыло; история — server.trackedNotifications.
Singleton {
    id: root
    readonly property bool dnd: Session.dnd   // хранится в Session (переживает перезапуск)
    // открыто окно игры — всплывашек нет совсем (даже критических), уведомления тихо идут в историю.
    // Список игр тот же, что в правиле игр mango (tearing / VRR).
    readonly property var gameRe: /^(steam_app_\d+|gamescope|cs2|dota2|osu!|Minecraft.*)$/
    readonly property bool gaming: ToplevelManager.toplevels.values.some(t => gameRe.test(t.appId ?? ""))
    onGamingChanged: if (gaming) popups = []
    property var popups: []
    property var times: ({})          // id → время прихода (для «HH:mm» в истории)
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length

    function dropPopup(n) {
        popups = popups.filter(x => x && x !== n)
    }
    function clearAll() {
        popups = []
        for (const n of server.trackedNotifications.values.slice()) n.dismiss()
    }
    function timeOf(n) {
        const t = times[n?.id]
        return t ? Qt.formatTime(t, "HH:mm") : ""
    }

    // страховка: исчезнувшие/закрытые уведомления не должны оставаться в «всплывших» (иначе окно тостов висит пустым)
    Timer {
        interval: 3000
        running: root.popups.length > 0 || Object.keys(root.times).length > 50
        repeat: true
        onTriggered: {
            const live = server.trackedNotifications.values
            const keep = root.popups.filter(n => n && live.indexOf(n) >= 0)
            if (keep.length !== root.popups.length) root.popups = keep
            // времена прихода: оставляем только живые уведомления (иначе словарь растёт вечно)
            const ids = new Set(live.map(n => String(n.id)))
            const stale = Object.keys(root.times).filter(k => !ids.has(k))
            if (stale.length) { const t = Object.assign({}, root.times); for (const k of stale) delete t[k]; root.times = t }
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = true
            root.times = Object.assign({}, root.times, { [n.id]: new Date() })
            if ((!root.gaming || Demo.active || n.appName === "lite demo") && (!root.dnd || n.urgency === NotificationUrgency.Critical || Demo.active || n.appName === "lite demo"))
                root.popups = [n].concat(root.popups).slice(0, 5)
        }
    }
}
