pragma Singleton
import QtQuick
import Quickshell

// Обратный отсчёт перед действием из повер-меню (выход, сон, перезагрузка, BIOS, выключение).
// 10 секунд: все мониторы уходят в размытие, на основном — кольцо с секундами.
// Esc / «Отменить» — отмена, Enter / «Сейчас» — сразу.
//   qs -c lite ipc call power cancel | now
Singleton {
    id: root

    readonly property int duration: 10000
    property var action: null           // { key, icon, label, verb, cmd, tint }
    property bool active: false          // окна существуют
    property bool closing: false         // окна уходят (анимация), потом active = false
    property real progress: 1            // 1 → 0 за duration
    readonly property int seconds: Math.max(0, Math.ceil(progress * duration / 1000 - 0.001))
    property var pending: null           // команда, которую выполнить после ухода окон

    function start(a) {
        if (active) return
        action = a
        closing = false
        pending = null
        progress = 1
        active = true
        fast.stop()
        run.restart()
    }
    function cancel() {
        if (!active || closing) return
        run.stop()
        fast.stop()
        closing = true
        hide.restart()
    }
    // повторное нажатие буквы действия: если осталось больше 5 секунд — сразу сократить до 5
    function expedite() {
        if (!active || closing) return
        if (progress * duration <= 5000) return
        run.stop()
        fast.from = 5000 / duration
        fast.restart()
    }
    function now() {
        if (!active || closing) return
        run.stop()
        fast.stop()
        pending = action?.cmd ?? null
        closing = true
        hide.restart()
    }

    NumberAnimation {
        id: run
        target: root
        property: "progress"
        from: 1; to: 0
        duration: root.duration
        onFinished: if (root.progress <= 0) root.now()
    }
    NumberAnimation {
        id: fast
        target: root
        property: "progress"
        to: 0
        duration: 5000
        onFinished: if (root.progress <= 0) root.now()
    }
    // окна плавно гаснут, затем исчезают; действие — когда экран уже чистый
    Timer {
        id: hide
        interval: 320
        onTriggered: {
            root.active = false
            root.closing = false
            if (root.pending) Quickshell.execDetached(root.pending)
            root.pending = null
        }
    }
}
