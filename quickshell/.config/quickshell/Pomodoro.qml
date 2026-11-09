pragma Singleton
import QtQuick
import Quickshell

// Помодоро-таймер под задачу. Конец хранится в Session — переживает перезапуск qs.
// В конце — уведомление; в баре, пока идёт, — оставшееся время.
Singleton {
    id: root

    readonly property int minutes: 25
    readonly property bool running: Session.pomodoroEnds > now
    readonly property string task: Session.pomodoroTask
    property real now: Date.now()
    readonly property int remaining: Math.max(0, Math.ceil((Session.pomodoroEnds - now) / 1000))
    readonly property real progress: running ? remaining / (minutes * 60) : 0
    readonly property string label: Math.floor(remaining / 60) + ":" + String(remaining % 60).padStart(2, "0")

    function start(text) {
        Session.pomodoroTask = text ?? ""
        Session.pomodoroEnds = Date.now() + minutes * 60 * 1000
        now = Date.now()
    }
    function stop() { Session.pomodoroEnds = 0 }

    Timer {
        interval: 1000
        repeat: true
        running: Session.pomodoroEnds > 0
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            if (Session.pomodoroEnds > 0 && root.now >= Session.pomodoroEnds) {
                Session.pomodoroEnds = 0
                Quickshell.execDetached(["notify-send", "-a", "Помодоро", "-i", "alarm-symbolic",
                                         root.minutes + " минут прошло", root.task || "Пора сделать перерыв"])
            }
        }
    }
}
