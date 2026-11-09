pragma Singleton
import QtQuick
import Quickshell

// Виджеты рабочего стола: каталог, настройки каждого (Session.deskCfg), режим правки и позиции.
Singleton {
    id: root
    property bool editing: false

    readonly property var pos: { try { return JSON.parse(Session.deskPos) } catch (e) { return {} } }
    readonly property var items: { try { return JSON.parse(Session.deskItems) } catch (e) { return [] } }
    readonly property var cfgAll: { try { return JSON.parse(Session.deskCfg) } catch (e) { return {} } }

    // общие настройки плитки + свои у каждого виджета. type: choice — список [подпись, значение]
    readonly property var common: [
        { key: "scale", label: "Размер", def: 1, values: [["S", 0.75], ["M", 1], ["L", 1.35], ["XL", 1.8]] },
        { key: "style", label: "Фон", def: "glass", values: [["Стекло", "glass"], ["Без фона", "plain"]] },
        { key: "alpha", label: "Плотность", def: 0.6, values: [["30%", 0.3], ["60%", 0.6], ["100%", 1]], when: "glass" }
    ]
    readonly property var catalog: [
        { id: "clock", label: "Часы", icon: "", defPos: { x: 80, y: 120 }, opts: [
            { key: "seconds", label: "Секунды", def: false, values: [["Нет", false], ["Да", true]] },
            { key: "h12", label: "Формат", def: false, values: [["24 ч", false], ["12 ч", true]] },
            { key: "date", label: "Дата", def: true, values: [["Да", true], ["Нет", false]] } ] },
        { id: "weather", label: "Погода", icon: "\u{f0590}", defPos: { x: 80, y: 330 }, opts: [
            { key: "desc", label: "Описание", def: true, values: [["Да", true], ["Нет", false]] } ] },
        { id: "stats", label: "Загрузка системы", icon: "", defPos: { x: 80, y: 480 }, opts: [
            { key: "cpu", label: "CPU", def: true, values: [["Да", true], ["Нет", false]] },
            { key: "gpu", label: "GPU", def: true, values: [["Да", true], ["Нет", false]] },
            { key: "ram", label: "RAM", def: true, values: [["Да", true], ["Нет", false]] } ] },
        { id: "player", label: "Плеер", icon: "", defPos: { x: 420, y: 120 }, opts: [
            { key: "cover", label: "Обложка", def: true, values: [["Да", true], ["Нет", false]] } ] },
        { id: "calendar", label: "Календарь", icon: "", defPos: { x: 420, y: 330 }, opts: [
            { key: "monday", label: "Неделя начинается с", def: true, values: [["Понедельника", true], ["Воскресенья", false]] } ] }
    ]

    function info(id) { return catalog.find(c => c.id === id) }
    function has(id) { return items.indexOf(id) >= 0 }
    function toggle(id) {
        const a = items.slice(), i = a.indexOf(id)
        if (i >= 0) a.splice(i, 1); else a.push(id)
        Session.deskItems = JSON.stringify(a)
    }
    function defaultOf(id, key) {
        for (const o of common) if (o.key === key) return o.def
        for (const o of info(id)?.opts ?? []) if (o.key === key) return o.def
        return undefined
    }
    function cfg(id, key) {
        const v = cfgAll[id]?.[key]
        return v === undefined ? (key === "monitor" ? "DP-3" : defaultOf(id, key)) : v
    }
    function set(id, key, value) {
        const c = Object.assign({}, cfgAll)
        c[id] = Object.assign({}, c[id] ?? {}, { [key]: value })
        Session.deskCfg = JSON.stringify(c)
    }
    function position(id) { return pos[id] ?? info(id)?.defPos ?? { x: 100, y: 100 } }
    function place(id, x, y) {
        const p = Object.assign({}, pos)
        p[id] = { x: Math.round(x), y: Math.round(y) }
        Session.deskPos = JSON.stringify(p)
    }
    function resetPos() { Session.deskPos = "{}" }
}
