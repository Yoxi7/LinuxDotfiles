import QtQuick
import qs

// График за последние 2 минуты.
//   загрузка    — залитая область (акцент), шкала 0–100 %
//   температура — линия с подсветкой, шкала подстраивается под разброс (не меньше 15°),
//                 подписанные линии сетки, точка с текущим значением, максимум за период
// Перерисовывается только когда приходят новые точки.
Canvas {
    id: root
    property var history: []          // [{ ...: число }]
    property string loadKey
    property string tempKey
    property int capacity: 60
    property int labelPx: 10
    readonly property int labelWidth: Math.round(labelPx * 2.6) // слева — подписи градусов (26 при 10 px)

    onHistoryChanged: requestPaint()
    onWidthChanged: requestPaint()
    onLabelPxChanged: requestPaint()

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const h = history
        if (h.length < 2) return
        const left = labelWidth, w = width - left, ht = height
        const step = w / (capacity - 1)
        const x0 = left + w - (h.length - 1) * step
        const yOf = v => ht - 3 - Math.max(0, Math.min(1, v)) * (ht - 8)

        // ── шкала температуры по данным: шаг 5° или 10°, разброс не меньше 15°
        const temps = h.map(p => p[tempKey])
        const tMaxData = Math.max(...temps), tMinData = Math.min(...temps)
        const span = Math.max(15, tMaxData - tMinData)
        const gridStep = span > 30 ? 10 : 5
        const lo = Math.floor((tMinData - span * 0.15) / gridStep) * gridStep
        const hi = Math.ceil((tMaxData + span * 0.15) / gridStep) * gridStep
        const tY = t => yOf((t - lo) / (hi - lo))

        // ── сетка с подписями
        ctx.font = labelPx + "px '" + Theme.font + "'"
        ctx.textAlign = "right"
        ctx.textBaseline = "middle"
        for (let t = lo; t <= hi; t += gridStep) {
            const y = Math.round(tY(t)) + 0.5
            if (y < 4 || y > ht - 2) continue
            ctx.strokeStyle = rgba(Theme.text, 0.07)
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(left + w, y); ctx.stroke()
            ctx.fillStyle = rgba(Theme.text, 0.35)
            ctx.fillText(t + "°", left - 5, y)
        }

        // ── загрузка
        ctx.beginPath()
        ctx.moveTo(x0, ht)
        h.forEach((p, i) => ctx.lineTo(x0 + i * step, yOf(p[loadKey] / 100)))
        ctx.lineTo(left + w, ht)
        ctx.closePath()
        const g = ctx.createLinearGradient(0, 0, 0, ht)
        g.addColorStop(0, rgba(Theme.accent, 0.45))
        g.addColorStop(1, rgba(Theme.accent, 0.03))
        ctx.fillStyle = g
        ctx.fill()

        // ── температура: подсветка под линией + линия
        const path = () => {
            ctx.beginPath()
            h.forEach((p, i) => { const x = x0 + i * step, y = tY(p[tempKey]); i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y) })
        }
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        path(); ctx.strokeStyle = rgba(Theme.primary, 0.25); ctx.lineWidth = 6; ctx.stroke()
        path(); ctx.strokeStyle = Theme.primary; ctx.lineWidth = 2; ctx.stroke()

        // ── точка на конце с текущим значением
        const last = temps[temps.length - 1]
        const ex = left + w - 1, ey = tY(last)
        ctx.fillStyle = Theme.primary
        ctx.beginPath(); ctx.arc(ex - 2, ey, 3.5, 0, 2 * Math.PI); ctx.fill()

        // ── максимум за период — в правом верхнем углу
        ctx.textAlign = "right"
        ctx.textBaseline = "top"
        ctx.fillStyle = rgba(Theme.text, 0.55)
        ctx.fillText("макс " + Math.round(tMaxData) + "°", left + w - 2, 2)
    }
}
