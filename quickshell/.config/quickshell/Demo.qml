pragma Singleton
import QtQuick
import Quickshell

// Режим демонстрации (qs-demo и MCP demo):
//   • стеклянная подпись внизу выбранного монитора (step, title, sub, screenName);
//   • плавный посимвольный ввод в поле поиска открытого модального окна (query / typeQuery);
//   • переключение вкладок и секций внутри ControlCenter, ShellSettings, BarConfig, ClipboardPicker, EmojiPicker.
Singleton {
    id: root
    property bool active: false
    property string screenName: ""
    property string step: ""
    property string title: ""
    property string sub: ""
    property int serial: 0              // меняется на каждую подпись — для анимации смены
    property bool shown: false          // окно подписи живёт, пока не догаснет

    // состояние управления открытыми окнами во время демонстрации
    property string query: ""
    property string typingTarget: ""
    property int typingPos: 0
    property string ccExpand: ""        // "" | bt | net | sink | source | display
    property string settingsTab: "general" // general | idle | desk
    property string deskOpenId: ""      // "" | clock | weather | stats | player | calendar
    property string barScope: "primary" // primary | secondary
    property string clipKind: "all"     // all | text | image
    property int emojiGroup: 0

    function targetScreen() {
        if (screenName !== "") {
            const s = Quickshell.screens.find(x => x.name === screenName)
            if (s) return s
        }
        return Theme.primaryScreen()
    }

    function caption(n, t, s, scr) {
        if (scr !== undefined && scr !== "") screenName = scr
        step = n ?? ""
        title = t ?? ""
        sub = s ?? ""
        serial++
        active = true
        shown = true
        hide.stop()
    }
    function setQuery(q) {
        typeTimer.stop()
        query = q ?? ""
    }
    function typeQuery(q) {
        typeTimer.stop()
        query = ""
        typingTarget = q ?? ""
        typingPos = 0
        if (typingTarget.length > 0) typeTimer.start()
    }
    function clear() {
        typeTimer.stop()
        query = ""
        ccExpand = ""
        settingsTab = "general"
        deskOpenId = ""
        barScope = "primary"
        clipKind = "all"
        active = false
        hide.restart()
    }
    Timer {
        id: typeTimer
        interval: 65
        repeat: true
        onTriggered: {
            if (root.typingPos >= root.typingTarget.length) { stop(); return }
            root.typingPos++
            root.query = root.typingTarget.slice(0, root.typingPos)
        }
    }
    Timer { id: hide; interval: 400; onTriggered: root.shown = false }
}
