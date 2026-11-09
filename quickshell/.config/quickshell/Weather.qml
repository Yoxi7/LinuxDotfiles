pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Погода из двух источников, раз в 20 минут:
//   wttr.in    — сейчас, ветер, влажность, max/min на сегодня, почасовой (шаг 3 ч), первые 3 дня сетки
//                (по Новосибирску сходится с Яндексом лучше)
//   Open-Meteo — остальные дни сетки (до 16 вперёд, 7 назад) и давление у земли
// Если один источник не ответил, всё берётся из другого.
// Open-Meteo у провайдера заблокирован, поэтому curl сначала идёт через mihomo (127.0.0.1:7890).
Singleton {
    id: root

    // ── настройки
    property string city: "Новосибирск"
    property real lat: 55.0302
    property real lon: 82.9204
    readonly property string proxy: "http://127.0.0.1:7890"

    // ── данные для UI
    readonly property bool loaded: om !== null || wt !== null
    readonly property bool failed: omFailed && wtFailed
    property real temp: 0
    property real feelsLike: 0
    property real todayMax: 0
    property real todayMin: 0
    property string description: "Загрузка…"
    property string icon: glyph(0xf0590)
    property color iconColor: "#c7c7cc"
    property int wind: 0
    property int humidity: 0
    property int pressure: 0                    // мм рт. ст.
    property var hourly: []                     // [{ time, temp, icon, color }] — 6 точек вперёд
    // сетка по дням (как у Яндекса): с понедельника этой недели до конца прогноза,
    // добита null до воскресенья; [{ day, month, weekday, max, min, icon, color, past, today }]
    property var calendar: []
    property string sources: ""                 // откуда данные — для подписи в окне
    property date updated

    // разобранные ответы источников
    property var om: null
    property var wt: null
    property bool omFailed: false
    property bool wtFailed: false

    function glyph(cp) { return String.fromCodePoint(cp) }
    function fmt(t) { const r = Math.round(t); return (r > 0 ? "+" : r < 0 ? "−" : "") + Math.abs(r) + "°" }
    function pad(n) { return String(n).padStart(2, "0") }
    function isoDate(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

    // WMO-код → описание и значки (день / ночь)
    readonly property var wmo: ({
        0:  ["Ясно", 0xf0599, 0xf0594],
        1:  ["Преимущественно ясно", 0xf0595, 0xf0f31],
        2:  ["Переменная облачность", 0xf0595, 0xf0f31],
        3:  ["Пасмурно", 0xf0590, 0xf0590],
        45: ["Туман", 0xf0591, 0xf0591],
        48: ["Изморозь", 0xf0591, 0xf0591],
        51: ["Лёгкая морось", 0xf0597, 0xf0597],
        53: ["Морось", 0xf0597, 0xf0597],
        55: ["Сильная морось", 0xf0597, 0xf0597],
        56: ["Ледяная морось", 0xf067f, 0xf067f],
        57: ["Ледяная морось", 0xf067f, 0xf067f],
        61: ["Небольшой дождь", 0xf0597, 0xf0597],
        63: ["Дождь", 0xf0596, 0xf0596],
        65: ["Ливень", 0xf067e, 0xf067e],
        66: ["Ледяной дождь", 0xf067f, 0xf067f],
        67: ["Сильный ледяной дождь", 0xf067f, 0xf067f],
        71: ["Небольшой снег", 0xf0598, 0xf0598],
        73: ["Снег", 0xf0598, 0xf0598],
        75: ["Снегопад", 0xf0f36, 0xf0f36],
        77: ["Снежные зёрна", 0xf0598, 0xf0598],
        80: ["Ливневый дождь", 0xf0596, 0xf0596],
        81: ["Сильный ливень", 0xf067e, 0xf067e],
        82: ["Очень сильный ливень", 0xf067e, 0xf067e],
        85: ["Снежный заряд", 0xf0f36, 0xf0f36],
        86: ["Сильная метель", 0xf0f36, 0xf0f36],
        95: ["Гроза", 0xf0593, 0xf0593],
        96: ["Гроза с градом", 0xf067e, 0xf067e],
        99: ["Гроза с сильным градом", 0xf067e, 0xf067e]
    })
    function wmoText(code) { return (wmo[code] ?? ["Неизвестно"])[0] }
    function wmoIcon(code, day) { const w = wmo[code]; return glyph(w ? (day ? w[1] : w[2]) : 0xf0590) }
    // цвет значка: солнце — жёлтое, осадки — голубые, гроза — фиолетовая, облака — белёсые
    function wmoColor(code) {
        if (code <= 1) return "#ffd60a"
        if (code === 2) return "#ffcc66"
        if (code === 3 || code === 45 || code === 48) return "#c7c7cc"
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "#e5f2ff"
        if (code >= 95) return "#bf5af2"
        return "#64d2ff"
    }
    function wmoTint(code, day) { return !day && code <= 2 ? "#a6c8ff" : wmoColor(code) }   // ночью — «лунный»

    // коды wttr.in (WorldWeatherOnline) → WMO, чтобы значки и цвета были общими
    function wwo(code) {
        const c = Number(code)
        if (c === 113) return 0
        if (c === 116) return 2
        if (c === 119 || c === 122) return 3
        if ([143, 248, 260].includes(c)) return 45
        if ([176, 263, 266, 293, 296, 353].includes(c)) return 61
        if ([299, 302, 356].includes(c)) return 63
        if ([305, 308, 359].includes(c)) return 65
        if ([179, 323, 326, 368].includes(c)) return 71
        if ([329, 332].includes(c)) return 73
        if ([227, 230, 335, 338, 371].includes(c)) return 75
        if ([182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377].includes(c)) return 66
        if ([200, 386, 389, 392, 395].includes(c)) return 95
        return 3
    }
    // «07:12 AM» → минуты от полуночи
    function minutes(t) {
        const m = /(\d+):(\d+)\s*(AM|PM)/.exec(t ?? "")
        if (!m) return -1
        return (Number(m[1]) % 12 + (m[3] === "PM" ? 12 : 0)) * 60 + Number(m[2])
    }

    function update() {
        if (!omProc.running) omProc.running = true
        if (!wtProc.running) wtProc.running = true
    }

    readonly property string omUrl: `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}`
        + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m"
        + "&hourly=temperature_2m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&wind_speed_unit=ms&timezone=auto&past_days=7&forecast_days=16"
    readonly property string wtUrl: `https://wttr.in/${lat},${lon}?format=j1&lang=ru`

    // аргументы передаются позиционно — в строку команды ничего не подставляется
    readonly property var curl: ["sh", "-c", 'curl -sf --max-time 12 -x "$1" "$2" || curl -sf --max-time 12 "$2"', "weather", proxy]

    Process {
        id: omProc
        command: root.curl.concat([root.omUrl])
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.om = root.parseOpenMeteo(JSON.parse(text)); root.omFailed = false }
                catch (e) { root.omFailed = true; if (text) console.warn("weather: Open-Meteo:", e) }
                root.rebuild()
            }
        }
    }
    Process {
        id: wtProc
        command: root.curl.concat([root.wtUrl])
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.wt = root.parseWttr(JSON.parse(text)); root.wtFailed = false }
                catch (e) { root.wtFailed = true; if (text) console.warn("weather: wttr.in:", e) }
                root.rebuild()
            }
        }
    }

    // 20 минут; если какой-то источник не ответил — повтор через 2 минуты
    Timer { interval: 20 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.update() }
    Timer { interval: 2 * 60 * 1000; running: root.omFailed || root.wtFailed; repeat: true; onTriggered: root.update() }

    // ── разбор: каждый источник → общий вид
    function parseOpenMeteo(d) {
        const c = d.current, dl = d.daily, h = d.hourly
        const day = c.is_day === 1
        const today = c.time.slice(0, 10)
        const ti = dl.time.indexOf(today)
        const now = h.time.findIndex(t => t.slice(0, 13) === c.time.slice(0, 13))
        const hours = []
        for (let i = now + 1; i >= 1 && i < h.time.length && hours.length < 6; i++)
            hours.push({ time: h.time[i].slice(11, 16), temp: fmt(h.temperature_2m[i]),
                         icon: wmoIcon(h.weather_code[i], h.is_day[i] === 1), color: wmoTint(h.weather_code[i], h.is_day[i] === 1) })
        const days = {}
        for (let i = 0; i < dl.time.length; i++)
            days[dl.time[i]] = { max: dl.temperature_2m_max[i], min: dl.temperature_2m_min[i], code: dl.weather_code[i] }
        return {
            today: today, temp: c.temperature_2m, feels: c.apparent_temperature, code: c.weather_code, day: day,
            text: wmoText(c.weather_code), wind: Math.round(c.wind_speed_10m), humidity: Math.round(c.relative_humidity_2m),
            pressure: Math.round(c.surface_pressure * 0.750062),
            max: dl.temperature_2m_max[ti], min: dl.temperature_2m_min[ti], hours: hours, days: days
        }
    }

    function parseWttr(d) {
        const c = d.current_condition[0]
        const now = new Date()
        const nowMin = now.getHours() * 60 + now.getMinutes()
        const todayW = d.weather[0]
        const sun = todayW.astronomy?.[0] ?? {}
        const rise = minutes(sun.sunrise), set = minutes(sun.sunset)
        const isDay = m => rise < 0 || set < 0 || (m >= rise && m < set)
        const code = wwo(c.weatherCode)

        // почасовой у wttr — шаг 3 часа, по 8 точек на день; берём 6 ближайших после текущего часа
        const hours = []
        for (let di = 0; di < d.weather.length && hours.length < 6; di++) {
            for (const h of d.weather[di].hourly) {
                const m = Number(h.time) / 100 * 60
                if (di === 0 && m <= nowMin) continue
                if (hours.length >= 6) break
                const hc = wwo(h.weatherCode)
                hours.push({ time: pad(m / 60) + ":00", temp: fmt(Number(h.tempC)), icon: wmoIcon(hc, isDay(m)), color: wmoTint(hc, isDay(m)) })
            }
        }
        // дни: значок — по полудню
        const days = {}
        for (const w of d.weather) {
            const noon = w.hourly.find(h => h.time === "1200") ?? w.hourly[Math.floor(w.hourly.length / 2)]
            days[w.date] = { max: Number(w.maxtempC), min: Number(w.mintempC), code: wwo(noon.weatherCode) }
        }
        return {
            today: todayW.date, temp: Number(c.temp_C), feels: Number(c.FeelsLikeC), code: code, day: isDay(nowMin),
            text: c.lang_ru?.[0]?.value || wmoText(code), wind: Math.round(Number(c.windspeedKmph) / 3.6),
            humidity: Number(c.humidity), pressure: Math.round(Number(c.pressure) * 0.750062),
            max: Number(todayW.maxtempC), min: Number(todayW.mintempC), hours: hours, days: days
        }
    }

    // ── слияние: wttr.in главнее, Open-Meteo — дальние дни и давление
    function rebuild() {
        const main = wt ?? om
        if (!main) return
        temp = main.temp
        feelsLike = main.feels
        description = main.text
        icon = wmoIcon(main.code, main.day)
        iconColor = wmoTint(main.code, main.day)
        wind = main.wind
        humidity = main.humidity
        pressure = om?.pressure ?? main.pressure
        todayMax = main.max
        todayMin = main.min
        hourly = main.hours
        sources = wt && om ? "wttr.in · Open-Meteo" : wt ? "wttr.in" : "Open-Meteo"
        updated = new Date()

        // сетка: дни из обоих источников, wttr.in перекрывает
        const days = Object.assign({}, om?.days ?? {}, wt?.days ?? {})
        const today = main.today
        const first = new Date(today + "T00:00")
        const monday = new Date(first); monday.setDate(first.getDate() - (first.getDay() + 6) % 7)
        const dates = Object.keys(days).filter(k => new Date(k + "T00:00") >= monday).sort()
        const cal = []
        for (const k of dates) {
            const dt = new Date(k + "T00:00")
            const x = days[k]
            cal.push({
                day: dt.getDate(), month: dt.toLocaleString(Qt.locale("ru_RU"), "MMMM"), weekday: (dt.getDay() + 6) % 7,
                max: fmt(x.max), min: fmt(x.min), icon: wmoIcon(x.code, true), color: wmoColor(x.code),
                past: k < today, today: k === today
            })
        }
        // если в начале недели нет данных (нет Open-Meteo) — пустые клетки до первого дня
        const lead = dates.length ? (new Date(dates[0] + "T00:00").getDay() + 6) % 7 : 0
        for (let i = 0; i < lead; i++) cal.unshift(null)
        while (cal.length % 7) cal.push(null)
        calendar = cal
    }
}
