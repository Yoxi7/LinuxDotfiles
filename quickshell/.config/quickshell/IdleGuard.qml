import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Простой: притушить → выключить экраны → заблокировать → сон. Пороги и поведение — Session.idle*
// (настройка: Super+, → «Простой»). Свой swayidle запускается только ради сна/lock-session (before-sleep, lock).
Scope {
    id: root
    readonly property bool enabled: Session.idleOn
    property bool dpmsOff: false
    property bool preview: false              // «Притушить сейчас» из настроек
    readonly property bool dimmed: (enabled && dim.isIdle && Session.idleDim > 0) || preview

    property real veilLevel: dimmed ? Session.idleDimLevel : 0
    Behavior on veilLevel { NumberAnimation { duration: root.dimmed ? 1800 : 250; easing.type: Easing.OutCubic } }

    // действие, которое сейчас можно выполнять: не срабатывает при полноэкранном окне, если так настроено
    property var pendingAction: null
    function guarded(fn) {
        if (!Session.idleSkipFs) { fn(); return }
        pendingAction = fn
        fsCheck.running = true
    }
    Process {
        id: fsCheck
        command: ["bash", "-c", "mmsg get all-clients | python3 -c \"import sys,json;print(any(c.get('is_fullscreen') and c.get('is_visible') for c in json.load(sys.stdin)['clients']))\""]
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim() !== "True" && root.pendingAction) root.pendingAction(); root.pendingAction = null }
        }
    }

    // экраны выключены (по таймеру или кнопкой) — любой ввод включает их обратно
    function screensOff() { dpmsOff = true; Quickshell.execDetached(["mmsg", "dispatch", "sleep_monitor,all"]) }
    function screensOn() { dpmsOff = false; Quickshell.execDetached(["mmsg", "dispatch", "wakeup_monitor,all"]) }
    IdleMonitor {
        id: wake
        enabled: root.dpmsOff
        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: if (!isIdle && root.dpmsOff) root.screensOn()
    }

    IdleMonitor { id: dim; enabled: root.enabled && Session.idleDim > 0; timeout: Session.idleDim; respectInhibitors: Session.idleRespect }
    IdleMonitor {
        enabled: root.enabled && Session.idleDpms > 0
        timeout: Session.idleDpms
        respectInhibitors: Session.idleRespect
        onIsIdleChanged: {
            if (isIdle) root.guarded(() => root.screensOff())
            else if (root.dpmsOff) root.screensOn()
        }
    }
    IdleMonitor {
        enabled: root.enabled && Session.idleLock > 0
        timeout: Session.idleLock
        respectInhibitors: Session.idleRespect
        onIsIdleChanged: if (isIdle) root.guarded(() => Quickshell.execDetached(["loginctl", "lock-session"]))
    }
    IdleMonitor {
        enabled: root.enabled && Session.idleSuspend > 0
        timeout: Session.idleSuspend
        respectInhibitors: Session.idleRespect
        onIsIdleChanged: if (isIdle) root.guarded(() => Quickshell.execDetached(["systemctl", "suspend", "-i"]))
    }

    // swayidle только для событий сна: «блокировать перед сном» и сам lock-session
    Process {
        id: sway
        running: true
        command: Session.idleLockSleep
            ? ["swayidle", "-w", "before-sleep", "loginctl lock-session", "lock", Quickshell.env("HOME") + "/.local/bin/lock"]
            : ["swayidle", "-w", "lock", Quickshell.env("HOME") + "/.local/bin/lock"]
    }

    // затемнение: сквозное для мыши; первое движение возвращает яркость
    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: ll
            required property var modelData
            active: root.dimmed || root.veilLevel > 0.01
            PanelWindow {
                screen: ll.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                // цвет самого окна (без вложенного прямоугольника): на повёрнутом мониторе так нет артефактов перерисовки
                color: Qt.rgba(0, 0, 0, root.veilLevel)
                mask: Region {}
                WlrLayershell.namespace: "qs-idle-dim"
                WlrLayershell.layer: WlrLayer.Overlay
            }
        }
    }

    // проверка из настроек: притушить на 3 с
    function previewDim() { preview = true; previewTimer.restart() }
    Timer { id: previewTimer; interval: 3000; onTriggered: root.preview = false }
}
