import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Локальный сокет $XDG_RUNTIME_DIR/qs-lite.sock: строка = команда. Скрипты и игры шлют события оболочке:
//   toast <заголовок> | <текст>      — уведомление
//   modal <имя>                     — открыть / закрыть окно (launcher, wallpapers, …)
//   privacy on|off|toggle           — приватный режим
//   dnd on|off|toggle               — «не беспокоить»
//   desk on|off|toggle|edit         — виджеты рабочего стола
//   idle on|off                     — простой (притушение / экраны / блокировка)
//   ping                            — ответ «pong»
// Отправка: qs-send toast "Игра запущена | Dota 2"
Scope {
    id: root
    readonly property string path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lite.sock"

    function flag(arg, cur) { return arg === "on" ? true : arg === "off" ? false : !cur }

    // sock — соединение клиента: команда может ответить позже (approve)
    function run(line, sock) {
        const sp = line.indexOf(" ")
        const cmd = (sp < 0 ? line : line.slice(0, sp)).trim()
        const arg = sp < 0 ? "" : line.slice(sp + 1).trim()
        switch (cmd) {
        case "ping": return "pong"
        case "toast": {
            const p = arg.split("|")
            Quickshell.execDetached(["notify-send", "-a", "qs", p[0].trim(), (p[1] ?? "").trim()])
            return "ok"
        }
        case "modal": Modal.toggle(arg); return "ok"
        case "approve": Ai.requestApproval(arg, sock); return null          // ответит окно помощника (allow | deny)
        case "question": Ai.requestQuestion(arg, sock); return null         // ответит окно помощника JSON-ответом на вопросы
        case "plan": Ai.receivePlan(arg); return "ok"                       // карточка предложенного плана (ProposedPlanCard)
        case "subagent_event": Ai.onSubagentEvent(arg); return "ok"         // живой статус/результат субагента (delegate_task / ask_agent)
        case "privacy": Session.privacy = flag(arg, Session.privacy); return "ok"
        case "dnd": Session.dnd = flag(arg, Session.dnd); return "ok"
        case "desk":
            if (arg === "edit") { Session.deskOn = true; Desk.editing = !Desk.editing }
            else Session.deskOn = flag(arg, Session.deskOn)
            return "ok"
        case "idle": Session.idleOn = flag(arg, Session.idleOn); return "ok"
        case "caffeine": Session.idleInhibit = flag(arg, Session.idleInhibit); return "ok"
        case "nightlight": Session.nightLight = flag(arg, Session.nightLight); return "ok"
        case "cursor": {
            const p = arg.split(/\s+/)
            if (p.length >= 2) Cursor.setPos(parseFloat(p[0]), parseFloat(p[1]))
            return "ok"
        }
        }
        return "err: неизвестная команда " + cmd
    }

    SocketServer {
        active: true
        path: root.path
        handler: Socket {
            id: sock
            parser: SplitParser {
                onRead: line => {
                    if (line.trim() === "") return
                    const r = root.run(line, sock)
                    if (r !== null) { sock.write(r + "\n"); sock.flush() }
                }
            }
        }
    }
}
