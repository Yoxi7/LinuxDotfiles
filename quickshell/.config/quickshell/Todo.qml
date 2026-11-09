pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Список задач. Хранится в ~/.local/share/quickshell/todos.json — обычный JSON-массив
// [{ "id": …, "text": "…", "done": false }], его можно править руками или синхронизировать;
// изменения файла подхватываются сразу.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/share/quickshell/todos.json"
    property var items: []
    readonly property var pending: items.filter(i => !i.done)
    readonly property var finished: items.filter(i => i.done)
    readonly property var current: pending[0] ?? null      // верхняя невыполненная — «в фокусе»

    function save() { file.setText(JSON.stringify(items, null, 2) + "\n") }
    function add(text) {
        const t = text.trim()
        if (!t) return
        // новая — в конец невыполненных, перед выполненными
        items = pending.concat([{ id: Date.now(), text: t, done: false }], finished)
        save()
    }
    function toggle(id) {
        const it = items.map(i => i.id === id ? Object.assign({}, i, { done: !i.done }) : i)
        items = it.filter(i => !i.done).concat(it.filter(i => i.done))
        save()
    }
    function remove(id) { items = items.filter(i => i.id !== id); save() }
    function focus(id) {                                    // поднять наверх
        const i = items.find(x => x.id === id)
        if (!i) return
        items = [i].concat(items.filter(x => x.id !== id))
        save()
    }
    function clearDone() { items = pending; save() }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/quickshell"])

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text() || "[]")
                root.items = (Array.isArray(d) ? d : []).filter(i => i && typeof i.text === "string")
                                                       .map((i, n) => ({ id: i.id ?? n + 1, text: i.text, done: !!i.done }))
            } catch (e) {}
        }
    }
}
