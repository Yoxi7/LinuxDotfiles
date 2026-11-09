import QtQuick
import Quickshell
import qs

// Окно помощника (кнопка в баре, Super+A): чаты слева, переписка справа. Та же переписка — вкладкой «Помощник» в пункте управления.
// Окно можно перетаскивать за верхнюю полосу (двойной клик — на место, на другой монитор — тоже) и менять размер за края и углы.
ModalWindow {
    id: root
    name: "assistant"
    visible: !Ai.picking
    captureEscape: view.previewPath !== ""
    onKeyPressed: e => {
        if (e.key === Qt.Key_Escape && view.previewPath !== "") {
            view.previewPath = ""
            e.accepted = true
        }
    }
    readonly property var savedSize: { const p = Session.aiSize.split(","); return [Number(p[0]) || 1180, Number(p[1]) || 900] }
    cardWidth: savedSize[0]
    cardHeight: savedSize[1]
    readonly property real minW: 620
    readonly property real minH: 520

    // ── перетаскивание за верхнюю полосу
    MouseArea {
        id: dragArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 58
        hoverEnabled: true
        property real sx: 0
        property real sy: 0
        property real ox: 0
        property real oy: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: e => { const p = mapToItem(null, e.x, e.y); sx = p.x; sy = p.y; ox = root.offX; oy = root.offY }
        onPositionChanged: e => {
            if (!pressed) return
            const p = mapToItem(null, e.x, e.y)
            root.offX = ox + p.x - sx
            root.offY = oy + p.y - sy
        }
        onDoubleClicked: { root.offX = 0; root.offY = 0 }
        onReleased: e => {
            // курсор за пределами этого монитора — окно переезжает на тот, что под ним
            const scr = root.screen ?? Quickshell.screens[0]
            if (!scr) return
            const p = mapToItem(null, e.x, e.y)
            const gx = scr.x + p.x, gy = scr.y + p.y
            const t = Quickshell.screens.find(c => gx >= c.x && gx < c.x + c.width && gy >= c.y && gy < c.y + c.height)
            if (!t || t.name === scr.name) return
            Modal.anchorX = -1
            Modal.anchorScreen = t
            root.offX = (gx - t.x) - t.width / 2
            root.offY = (gy - t.y) - t.height / 2 + root.card.height / 2 - 28
        }
        Rectangle {
            anchors { top: parent.top; topMargin: 6; horizontalCenter: parent.horizontalCenter }
            width: 42; height: 4; radius: 2
            color: dragArea.pressed || dragArea.containsMouse ? Theme.muted : Qt.rgba(1, 1, 1, 0.16)
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }
    }

    AssistantView {
        id: view
        anchors { fill: parent; margins: 16 }
        active: !Modal.closing && !Ai.picking
    }

    // ── изменение размера: края и углы (окно растёт в сторону перетаскиваемого края, противоположный остаётся на месте)
    component Grip: MouseArea {
        id: grip
        property bool gl: false
        property bool gr: false
        property bool gt: false
        property bool gb: false
        property real sx: 0; property real sy: 0
        property real w0: 0; property real h0: 0; property real ox0: 0; property real oy0: 0
        z: 50
        hoverEnabled: true
        cursorShape: (gl && gt) || (gr && gb) ? Qt.SizeFDiagCursor : (gr && gt) || (gl && gb) ? Qt.SizeBDiagCursor
                   : gl || gr ? Qt.SizeHorCursor : Qt.SizeVerCursor
        onPressed: e => {
            const p = mapToItem(null, e.x, e.y)
            sx = p.x; sy = p.y
            w0 = root.card.width; h0 = root.card.height; ox0 = root.offX; oy0 = root.offY
            root.animateSize = false
        }
        onPositionChanged: e => {
            if (!pressed) return
            const p = mapToItem(null, e.x, e.y)
            const maxW = root.card.parent.width - 80, maxH = root.card.parent.height - 80
            if (gl || gr) {
                const w = Math.max(root.minW, Math.min(maxW, w0 + (gr ? 1 : -1) * (p.x - sx)))
                root.cardWidth = w
                root.offX = ox0 + (w - w0) * (gr ? 0.5 : -0.5)
            }
            if (gt || gb) {
                const h = Math.max(root.minH, Math.min(maxH, h0 + (gb ? 1 : -1) * (p.y - sy)))
                root.cardHeight = h
                root.offY = oy0 + (h - h0) * (gb ? 0.5 : -0.5)
            }
        }
        onReleased: { root.animateSize = true; Session.aiSize = Math.round(root.card.width) + "," + Math.round(root.card.height) }
    }
    Grip { gr: true; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 20; bottomMargin: 20 } width: 8 }
    Grip { gl: true; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 20; bottomMargin: 20 } width: 8 }
    Grip { gb: true; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 } height: 8 }
    Grip { gt: true; anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 } height: 6 }
    Grip { gr: true; gb: true; anchors { right: parent.right; bottom: parent.bottom } width: 22; height: 22 }
    Grip { gl: true; gb: true; anchors { left: parent.left; bottom: parent.bottom } width: 22; height: 22 }
    Grip { gr: true; gt: true; anchors { right: parent.right; top: parent.top } width: 22; height: 14 }
    Grip { gl: true; gt: true; anchors { left: parent.left; top: parent.top } width: 22; height: 14 }
    // уголок-подсказка
    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 6; bottomMargin: 4 }
        text: "⋰"
        color: Theme.faint
        font { family: Theme.font; pixelSize: 14 }
    }
}
