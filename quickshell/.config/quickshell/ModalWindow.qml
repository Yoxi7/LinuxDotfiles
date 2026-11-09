import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Общая основа оверлеев: прозрачный слой на весь экран, стеклянная карточка по центру,
// клавиатура захвачена, Esc / клик мимо — закрыть.
PanelWindow {
    id: win
    property string name
    default property alias content: card.data
    property alias card: card
    property real cardWidth: 640
    property real cardHeight: 480
    property bool dropdown: false        // выпадает под баром справа, а не по центру
    property bool captureEscape: false   // Esc отдаётся окну (закрыть вложенный просмотр), а не закрывает всё
    // окно можно перетащить: смещение от штатной позиции (сбрасывается при новом открытии)
    property real offX: 0
    property real offY: 0
    property bool resizable: false       // края и углы карточки тянутся; размер запоминается для каждого окна
    property real minW: 640
    property real minH: 480
    property bool animateSize: true      // false на время ручного изменения размера
    signal keyPressed(var event)

    // открыто кнопкой бара — на мониторе этой кнопки; в режиме демо — на выбранном мониторе; иначе mango сам выберет монитор с фокусом
    screen: Modal.anchorScreen ?? (Demo.active && Demo.screenName !== "" ? Demo.targetScreen() : null)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-" + name
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // FocusScope — корень: нажатия, не съеденные полем ввода/списком, всплывают сюда
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape && !win.captureEscape) { Modal.close(); e.accepted = true; return }
            win.keyPressed(e)
        }

        // подложка полностью прозрачная: так mango размывает только под карточкой,
        // а клик мимо карточки всё равно закрывает окно
        MouseArea { anchors.fill: parent; onClicked: Modal.close() }

        Glass {
            id: card
            width: Math.min(win.cardWidth, parent.width - 80)
            height: Math.min(win.cardHeight, parent.height - 80)
            // под кнопкой бара, если открыто кликом по ней; иначе справа / по центру
            readonly property real baseX: Modal.anchorX >= 0 ? Math.max(10, Math.min(parent.width - width - 10, Modal.anchorX - width / 2))
                : win.dropdown ? parent.width - width - 10 : (parent.width - width) / 2
            readonly property real baseY: win.dropdown ? Theme.barHeight + 14 : (parent.height - height) / 2
            x: Math.max(-width + 120, Math.min(parent.width - 120, baseX + win.offX))      // за край целиком не уедет
            y: Math.max(0, Math.min(parent.height - 60, baseY + win.offY))
            transformOrigin: Modal.anchorX >= 0 ? Item.Top : win.dropdown ? Item.TopRight : Item.Center
            radius: 28
            color: Theme.glassStrong
            property bool entered: false
            readonly property bool shown: entered && !Modal.closing
            scale: shown ? 1 : 0.97
            opacity: shown ? 1 : 0
            Component.onCompleted: entered = true
            Behavior on scale { NumberAnimation { duration: card.shown ? Theme.dBase : Theme.dExit; easing.type: card.shown ? Easing.OutCubic : Easing.InCubic } }
            Behavior on opacity { NumberAnimation { duration: card.shown ? Theme.dFast : Theme.dExit } }
            Behavior on height { enabled: win.animateSize; NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // клики по карточке не закрывают оверлей
        }

        // ── изменение размера: края и углы (противоположный край остаётся на месте)
        Component.onCompleted: {
            if (!win.resizable) return
            try {
                const z = JSON.parse(Session.winSizes)[win.name]
                if (z) { win.cardWidth = Math.max(win.minW, z[0]); win.cardHeight = Math.max(win.minH, z[1]) }
            } catch (e) {}
        }
        component Grip: MouseArea {
            id: grip
            property bool gl: false
            property bool gr: false
            property bool gt: false
            property bool gb: false
            property real sx: 0; property real sy: 0
            property real w0: 0; property real h0: 0; property real ox0: 0; property real oy0: 0
            visible: win.resizable
            z: 50
            hoverEnabled: true
            cursorShape: (gl && gt) || (gr && gb) ? Qt.SizeFDiagCursor : (gr && gt) || (gl && gb) ? Qt.SizeBDiagCursor : gl || gr ? Qt.SizeHorCursor : Qt.SizeVerCursor
            onPressed: e => { const p = mapToItem(null, e.x, e.y); sx = p.x; sy = p.y; w0 = card.width; h0 = card.height; ox0 = win.offX; oy0 = win.offY; win.animateSize = false }
            onPositionChanged: e => {
                if (!pressed) return
                const p = mapToItem(null, e.x, e.y)
                if (gl || gr) {
                    const w = Math.max(win.minW, Math.min(card.parent.width - 40, w0 + (gr ? 1 : -1) * (p.x - sx)))
                    win.cardWidth = w
                    win.offX = ox0 + (w - w0) * (gr ? 0.5 : -0.5)
                }
                if (gt || gb) {
                    const h = Math.max(win.minH, Math.min(card.parent.height - 40, h0 + (gb ? 1 : -1) * (p.y - sy)))
                    win.cardHeight = h
                    win.offY = oy0 + (h - h0) * (gb ? 0.5 : -0.5)
                }
            }
            onReleased: {
                win.animateSize = true
                try { const o = JSON.parse(Session.winSizes); o[win.name] = [Math.round(card.width), Math.round(card.height)]; Session.winSizes = JSON.stringify(o) } catch (e) {}
            }
        }
        Grip { gr: true; x: card.x + card.width - 5; y: card.y + 22; width: 10; height: card.height - 44 }
        Grip { gl: true; x: card.x - 5; y: card.y + 22; width: 10; height: card.height - 44 }
        Grip { gb: true; x: card.x + 22; y: card.y + card.height - 5; width: card.width - 44; height: 10 }
        Grip { gt: true; x: card.x + 22; y: card.y - 5; width: card.width - 44; height: 8 }
        Grip { gr: true; gb: true; x: card.x + card.width - 18; y: card.y + card.height - 18; width: 24; height: 24 }
        Grip { gl: true; gb: true; x: card.x - 6; y: card.y + card.height - 18; width: 24; height: 24 }
        Grip { gr: true; gt: true; x: card.x + card.width - 18; y: card.y - 6; width: 24; height: 18 }
        Grip { gl: true; gt: true; x: card.x - 6; y: card.y - 6; width: 24; height: 18 }

        // блюр под окнами оболочки: кнопка на углу карточки, одна на все окна
        Rectangle {
            id: blurBtn
            x: Math.min(parent.width - width - 4, card.x + card.width - width - 18)
            y: Math.max(4, card.y - height / 2 - 2)
            width: 30; height: 30; radius: 15
            opacity: card.opacity
            color: blurMouse.containsMouse ? Qt.rgba(0.1, 0.1, 0.14, 0.97) : Qt.rgba(0.06, 0.06, 0.09, 0.9)
            border { width: 1; color: Session.blurOff ? Qt.rgba(1, 1, 1, 0.14) : Theme.primary }
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Text {
                anchors.centerIn: parent
                text: Session.blurOff ? "\u{f00af}" : "\u{f00ae}"
                color: Session.blurOff ? Theme.muted : Theme.primary
                font { family: Theme.iconFont; pixelSize: 14 }
            }
            MouseArea { id: blurMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Session.blurOff = !Session.blurOff }
            Rectangle {
                visible: blurMouse.containsMouse
                anchors { right: parent.right; top: parent.bottom; topMargin: 6 }
                width: tipT.implicitWidth + 20; height: tipT.implicitHeight + 12; radius: 9
                color: Qt.rgba(0.04, 0.04, 0.06, 0.97)
                border { width: 1; color: Qt.rgba(1, 1, 1, 0.14) }
                Text { id: tipT; anchors.centerIn: parent; text: Session.blurOff ? "Включить размытие под окнами" : "Выключить размытие под окнами"; color: Theme.text; font { family: Theme.font; pixelSize: 12 } }
            }
        }
    }
}
