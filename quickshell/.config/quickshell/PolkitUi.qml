import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs

// Агент polkit: запрос пароля в нашем стекле вместо polkit-kde.
// Агент живёт всегда (регистрируется в polkitd), окно создаётся только на время запроса.
Scope {
    id: root
    readonly property alias agent: agent
    readonly property bool registered: agent.isRegistered

    PolkitAgent { id: agent }

    // страховка: если наш агент не зарегистрировался и никто другой не отвечает за polkit — поднять штатный
    Timer {
        interval: 6000
        running: true
        onTriggered: if (!agent.isRegistered) Quickshell.execDetached(["bash", "-c", "pgrep -f '^/usr/lib/polkit-kde-authentication' >/dev/null || /usr/lib/polkit-kde-authentication-agent-1"])
    }

    // если регистрация не прошла (другой агент уже есть) — ничего не ломаем, просто не показываем
    LazyLoader {
        active: agent.isActive && agent.flow !== null
        PolkitDialog { flow: agent.flow }
    }
}
