pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Переключатели сессии из панели быстрых настроек. Переживают перезапуск qs:
// хранятся в ~/.local/state/qs-lite-session.json и записываются при каждом изменении.
Singleton {
    property alias idleInhibit: state.idleInhibit   // не гасить экран / не блокировать
    property alias dnd: state.dnd                   // не беспокоить
    property alias wallDir: state.wallDir           // последняя папка в пикере обоев
    property alias wallPins: state.wallPins         // закреплённые папки (JSON-массив)
    property alias wallRecent: state.wallRecent     // недавние папки (JSON-массив)
    property alias wallZoom: state.wallZoom         // размер превью: 0 / 1 / 2
    property alias wgPreviews: state.wgPreviews     // окно групп обоев: показывать превью
    property alias winSizes: state.winSizes         // размеры окон, которые можно растягивать (JSON: имя → [ширина, высота])
    property alias audioCycle: state.audioCycle     // устройства вывода для быстрого переключения (JSON: имена узлов PipeWire)
    property alias corners: state.corners           // скруглённые углы экрана (чёрные уголки поверх всего, в т.ч. игр)
    property alias cornerRadius: state.cornerRadius
    property alias blurOff: state.blurOff           // без размытия под окнами оболочки (стекло становится плотнее)
    property alias wallAnim: state.wallAnim         // анимация смены обоев: dynamic | random | grow | wave | wipe | fade | none
    property alias wallSortRev: state.wallSortRev   // сортировка наоборот (дата и размер — сначала новые/большие)
    property alias wallSort: state.wallSort         // name | date
    property alias wallRatings: state.wallRatings   // онлайн-обои: допустимые рейтинги, буквы s q e
    property alias wallOnSort: state.wallOnSort     // random | new | top
    property alias clipHide: state.clipHide         // буфер обмена: скрывать содержимое размытием
    property alias wallRatio: state.wallRatio       // пропорции в онлайн-поиске: "" или 16:9, 9:16 …
    property alias wallResize: state.wallResize     // как обои ложатся на экран: crop | fit | stretch | no
    property alias wallGravity: state.wallGravity   // какую часть оставить при crop
    property alias wallFill: state.wallFill         // цвет полей при fit / no (RRGGBB)
    property alias aiModel: state.aiModel             // помощник Claude: haiku | sonnet | opus
    property alias aiPrefs: state.aiPrefs             // JSON: модель и effort по помощникам {claude:{model,effort}, agy:…, codex:…}
    property alias aiSize: state.aiSize               // размер окна помощника "ширина,высота"
    property alias aiSidebar: state.aiSidebar         // боковая панель чатов
    property alias aiProvider: state.aiProvider       // claude | agy | codex (запасное)
    property alias aiModelAgy: state.aiModelAgy       // модель Antigravity
    property alias aiModelCodex: state.aiModelCodex   // модель Codex ("" — по умолчанию)
    property alias privacy: state.privacy             // приватный режим: размытие заголовков, треков, уведомлений, буфера, обоев
    property alias idleDim: state.idleDim             // секунд простоя до притушения (0 — выкл)
    property alias idleDpms: state.idleDpms           // …до выключения экранов
    property alias idleLock: state.idleLock           // …до блокировки
    property alias idleSuspend: state.idleSuspend     // …до сна (0 — выкл)
    property alias idleOn: state.idleOn               // мастер-переключатель простоя
    property alias idleLockSleep: state.idleLockSleep // блокировать перед сном
    property alias idleRespect: state.idleRespect     // учитывать inhibit'ы (видео, игры)
    property alias idleSkipFs: state.idleSkipFs       // не срабатывать при полноэкранном окне
    property alias idleDimLevel: state.idleDimLevel   // насколько тёмным делать при притушении
    property alias deskOn: state.deskOn               // виджеты рабочего стола
    property alias deskPos: state.deskPos             // JSON {id: {x, y}}
    property alias deskCfg: state.deskCfg             // JSON {id: {scale, style, alpha, monitor, …}}
    property alias deskItems: state.deskItems         // JSON ["clock", "weather", "stats"]
    property alias miniOn: state.miniOn              // дашборд на мини-дисплее (HDMI-A-1)
    property alias wallHidden: state.wallHidden       // размытые по одной обои (JSON-массив ключей)
    property alias wallSortRoot: state.wallSortRoot   // папка, в подпапки которой сортируются обои ("" — ~/Pictures/wp)
    property alias wallBlur: state.wallBlur           // пикер обоев: размывать превью (приватность), под курсором — чётко
    property alias wallAutoUp: state.wallAutoUp       // апскейлить обои при установке, если они меньше монитора
    property alias wallOutputs: state.wallOutputs   // на какие мониторы (через запятую; пусто — на все)
    property alias wallAspect: state.wallAspect     // в онлайн-сетке — исходные пропорции
    property alias wallSim: state.wallSim           // в просмотре — «как на экране», а не целиком
    property alias snipAction: state.snipAction     // скриншотилка: последнее действие и форма выделения
    property alias snipMode: state.snipMode
    property alias recentEmoji: state.recentEmoji   // недавние эмодзи через пробел
    property alias ccTab: state.ccTab               // пункт управления: последняя вкладка
    property alias nightLight: state.nightLight     // ночной свет (wlsunset) и его температура
    property alias nightTemp: state.nightTemp
    property alias pomodoroEnds: state.pomodoroEnds // помодоро: когда закончится (мс) и над чем
    property alias pomodoroTask: state.pomodoroTask

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qs-lite-session.json"
        blockLoading: true                          // состояние нужно до первой отрисовки
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: state
            property bool idleInhibit: false
            property bool dnd: false
            property string wallDir: ""
            property string wallPins: "[]"
            property string wallRecent: "[]"
            property int wallZoom: 1
            property string wallSort: "name"
            property bool wallSortRev: false
            property bool blurOff: false
            property bool corners: true
            property int cornerRadius: 24
            property string audioCycle: "[]"
            property string winSizes: "{}"
            property bool wgPreviews: true
            property string wallAnim: "dynamic"
            property string wallRatings: "s"
            property string wallOnSort: "random"
            property bool clipHide: false
            property string wallRatio: ""
            property string wallResize: "crop"
            property string wallGravity: "center"
            property string wallFill: "000000"
            property string wallOutputs: ""
            property bool wallAutoUp: true
            property bool wallBlur: false
            property string wallSortRoot: ""
            property string wallHidden: "[]"
            property bool privacy: false
            property string aiModel: "haiku"
            property string aiProvider: "claude"
            property string aiPrefs: "{}"
            property bool aiSidebar: true
            property string aiSize: "1180,900"
            property string aiModelAgy: "gemini-3.8-flash-medium"
            property string aiModelCodex: ""
            property int idleDim: 240
            property int idleDpms: 300
            property int idleLock: 600
            property int idleSuspend: 0
            property bool idleOn: true
            property bool idleLockSleep: true
            property bool idleRespect: true
            property bool idleSkipFs: true
            property real idleDimLevel: 0.72
            property bool deskOn: false
            property string deskPos: "{}"
            property string deskCfg: "{}"
            property string deskItems: '["clock","weather","stats"]'
            property bool miniOn: true
            property bool wallAspect: true
            property bool wallSim: true
            property string snipAction: "copy"
            property string snipMode: "rect"
            property string recentEmoji: ""
            property int ccTab: 0
            property bool nightLight: false
            property int nightTemp: 4000
            property real pomodoroEnds: 0
            property string pomodoroTask: ""
        }
    }
}
