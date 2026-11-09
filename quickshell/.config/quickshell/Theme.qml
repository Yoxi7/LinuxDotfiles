pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// «Жидкое стекло»: подложки полупрозрачные, размытие под ними делает mango
// (blur_layer=1 — размывается только то, что под непрозрачными пикселями).
// Тексты — белый с разной прозрачностью, как vibrancy в macOS.
Singleton {
    // стекло
    readonly property color glass: Qt.rgba(0.07, 0.07, 0.10, Session.blurOff ? 0.93 : 0.16)       // бар, всплывашки (без блюра — плотнее)
    readonly property color glassStrong: Qt.rgba(0.06, 0.06, 0.09, Session.blurOff ? 0.95 : 0.20) // окна
    // кромка и блики — в цвет акцента (следуют за обоями вместе с primary)
    readonly property color rim: Qt.rgba(primary.r, primary.g, primary.b, 0.30)       // кромка стекла
    readonly property color rimSoft: Qt.rgba(1, 1, 1, 0.07)   // волосяная граница модулей внутри стекла (нейтральная: акцент — только у кромки стекла)
    readonly property color glint: Qt.rgba(primary.r, primary.g, primary.b, 0.70)     // «линза» по верхнему краю
    readonly property color sheen: Qt.rgba(primary.r, primary.g, primary.b, 0.10)     // верхний блик

    // заливки поверх стекла
    readonly property color base: "#000000"                       // текст на светлых/цветных плашках
    readonly property color weak: Qt.rgba(1, 1, 1, 0.05)
    readonly property color strong: Qt.rgba(1, 1, 1, 0.10)
    readonly property color border: Qt.rgba(1, 1, 1, 0.18)
    readonly property color selected: Qt.rgba(1, 1, 1, 0.88)      // «линза» активного элемента
    readonly property color dim: "transparent"

    readonly property color text: "#f5f5f7"
    readonly property color muted: Qt.rgba(1, 1, 1, 0.62)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.36)
    // акцент берётся с обоев: wall-accent пишет ~/.cache/qs-lite/accent.json (его зовёт wallpick),
    // файл отслеживается — смена обоев перекрашивает всё сразу, с плавным переходом
    property color primary: wall.primary                          // светлый: значки, текст
    property color accent: wall.accent                            // насыщенный: включённые переключатели
    Behavior on primary { ColorAnimation { duration: 400 } }
    Behavior on accent { ColorAnimation { duration: 400 } }
    // при старте — пересчитать по тому, что сейчас на обоях (их могли сменить не через wallpick)
    Component.onCompleted: Quickshell.execDetached(["sh", "-c", "command -v wall-accent >/dev/null 2>&1 && wall-accent || true"])

    FileView {
        path: Quickshell.env("HOME") + "/.cache/qs-lite/accent.json"
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        JsonAdapter {
            id: wall
            property string primary: "#f3a6b8"
            property string accent: "#ea7a99"
        }
    }
    readonly property color danger: "#ff6961"
    readonly property color success: "#30d158"
    readonly property color warning: "#ffd60a"

    readonly property string font: "Kibernetyk Mono, Medeo Sans, sans-serif"
    readonly property string iconFont: "Font Awesome 6 Free, Font Awesome 5 Free, FontAwesome, MedeoMono Nerd Font Mono, monospace"
    readonly property int fontSize: 14
    // движение: три длительности и один характер (замедление в конце, без отскоков).
    // Уход всегда быстрее появления — интерфейс не должен заставлять ждать.
    readonly property int dFast: 120     // наведение, цвет, нажатие
    readonly property int dBase: 200     // появление, смена состояния, размеры
    readonly property int dSlow: 320     // крупные перемещения
    readonly property int dExit: 140     // исчезновение
    readonly property int radius: 18
    readonly property int barHeight: 36

    // склонение по числу: plural(1, "окно", "окна", "окон") → «окно»
    function plural(n, one, few, many) {
        const a = Math.abs(n) % 100, b = a % 10
        return a > 10 && a < 20 ? many : b === 1 ? one : b >= 2 && b <= 4 ? few : many
    }

    // основной монитор (бар, уведомления, отсчёт, демо): динамически первый активный экран
    readonly property string primaryMonitor: Quickshell.screens[0]?.name ?? "eDP-1"
    function primaryScreen() { return Quickshell.screens.find(s => s.name === primaryMonitor) ?? Quickshell.screens[0] }
}
