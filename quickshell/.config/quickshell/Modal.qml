pragma Singleton
import QtQuick
import Quickshell

// Какой оверлей открыт: "" | launcher | wallpapers | power | cheatsheet | control | notifications | weather.
// Закрытый оверлей не существует вовсе: LazyLoader в shell.qml уничтожает окно.
// toggleAt — открыть под кнопкой бара: x центра кнопки на экране и сам экран.
Singleton {
    id: root
    property string active: ""
    property bool closing: false        // идёт анимация ухода: окно ещё есть, но уже гаснет
    property real anchorX: -1           // -1 — обычное место (по центру / справа)
    property var anchorScreen: null

    function toggle(name: string): void {
        if (active === name && !closing) { close(); return }
        anchorX = -1
        anchorScreen = null
        open(name)
    }
    function toggleAt(name: string, x: real, screen: var): void {
        if (active === name && !closing) { close(); return }
        anchorX = x
        anchorScreen = screen
        open(name)
    }
    function open(name: string): void {
        exit.stop()
        closing = false
        active = name
    }
    function openOn(name: string, screenName: string): void {
        anchorX = -1
        anchorScreen = Quickshell.screens.find(s => s.name === screenName) ?? null
        open(name)
    }
    // окно плавно уходит, и только потом разгружается
    function close(): void {
        if (active === "" || closing) return
        closing = true
        exit.restart()
    }
    Timer {
        id: exit
        interval: Theme.dExit + 20
        onTriggered: { root.active = ""; root.closing = false }
    }
}
