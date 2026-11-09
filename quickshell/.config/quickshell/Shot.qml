pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Скриншотилка (порт regionSelector из iNiR): замороженный кадр на всех мониторах,
// выделение прямоугольником / обводкой, клик — по окну или найденной области картинки.
//   action: copy (снимок → файл + буфер) | edit (редактор) | ocr (текст → буфер)
//           | record (запись области, повторно — стоп)
//   mode:   rect | lasso
// qs -c lite ipc call region screenshot|menu|edit|ocr|record|recordSound|dismiss
Singleton {
    id: root

    property bool active: false
    property string action: "copy"
    property string mode: "rect"
    property bool sound: false

    // редактор: путь к обрезанному кадру и монитор, где выделяли
    property string editorPath: ""
    property string editorScreen: ""

    // запись: qs-record сообщает о старте / остановке через ipc
    property bool recording: false
    property real recordStart: 0

    readonly property string tmp: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-shot"
    readonly property string saveDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
    readonly property string nameFormat: "Screenshot from %Y-%m-%d %H-%M-%S"

    function open(a, m) {
        if (a === "record" && recording) {          // повторный вызов записи — остановить
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/qs-record", "--stop"])
            return
        }
        action = a
        mode = m ?? "rect"
        sound = false
        active = true
    }
    // меню — с последним выбранным действием и формой
    function menu() { open(Session.snipAction || "copy", Session.snipMode || "rect") }
    function remember() {
        if (action !== "record") Session.snipAction = action
        Session.snipMode = mode
    }
    function dismiss() { active = false }
    // редактор открывается после того, как окна выделения закрылись: иначе mango не отдаёт ему клавиатуру
    function openEditor(path, screen) {
        editorScreen = screen
        pendingEditor = path
        active = false
        editorDelay.restart()
    }
    property string pendingEditor: ""
    Timer { id: editorDelay; interval: 150; onTriggered: root.editorPath = root.pendingEditor }

    function setRecording(on) {
        recording = on
        if (on) recordStart = Date.now()
    }

    // qs перезапустили во время записи — подхватить
    Process {
        running: true
        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => { if (code === 0) root.setRecording(true) }
    }
}
