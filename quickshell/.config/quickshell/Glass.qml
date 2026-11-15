import QtQuick
import Quickshell
import qs

// Стеклянная подложка: полупрозрачная заливка, мягкий блик сверху и «живая» кромка (shaders/rim.frag):
//   • блики на противоположных углах — как свет на изогнутом стекле; свет «смотрит» на курсор
//     (где бы он ни был на экранах) — блик плавно поворачивается за мышью, как в iOS за гироскопом;
//   • под курсором кромка загорается, внутри — слабое свечение, оно плывёт за мышью;
//   • при наведении по стеклу один раз пробегает блик, при нажатии стекло вспыхивает.
// Всё только по событиям: в покое ничего не анимируется и не перерисовывается.
// Тени не рисуем: их пиксели попали бы в маску размытия.
Rectangle {
    id: root
    property bool sheen: true
    property color rimColor: Theme.rim
    property color glintColor: Qt.rgba(Qt.lighter(Theme.primary, 1.25).r, Qt.lighter(Theme.primary, 1.25).g,
                                       Qt.lighter(Theme.primary, 1.25).b, 0.95)
    property real rimWidth: 1.2
    property real lightAngle: Math.atan2(dirY, dirX)   // откуда свет; без курсора — сверху-слева
    property bool followCursor: true
    // направление на курсор — единичный вектор (анимируется он, а не угол: без скачка через ±π)
    property real dirX: -0.63
    property real dirY: -0.78
    Behavior on dirX { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
    Behavior on dirY { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }

    // центр стекла в координатах раскладки: экран окна + место окна на экране + место в окне
    function aim() {
        const w = QsWindow.window
        const s = w?.screen
        if (!s || !visible || width <= 0) return
        let ox = s.x, oy = s.y
        const a = w.anchors, m = w.margins
        if (a?.left) ox += m?.left ?? 0
        else if (a?.right) ox += s.width - w.width - (m?.right ?? 0)
        else ox += (s.width - w.width) / 2
        if (a?.top) oy += m?.top ?? 0
        else if (a?.bottom) oy += s.height - w.height - (m?.bottom ?? 0)
        else oy += (s.height - w.height) / 2
        const c = mapToItem(null, width / 2, height / 2)
        // в «нормированных» координатах стекла — как считает шейдер
        const dx = (Cursor.x - ox - c.x) / Math.max(1, width / 2)
        const dy = (Cursor.y - oy - c.y) / Math.max(1, height / 2)
        const len = Math.hypot(dx, dy)
        if (len < 1e-3) return
        dirX = dx / len
        dirY = dy / len
    }
    Connections {
        target: Cursor
        enabled: root.followCursor && root.visible
        function onMoved() { root.aim() }
    }
    Component.onCompleted: if (followCursor && Cursor.x >= 0) aim()
    property bool interactive: true           // реагировать на курсор
    property real fresnel: 1                  // толща и мениск: 0 — плоская плёнка, 1 — линза

    color: Theme.glass
    radius: Theme.radius

    Rectangle {
        visible: root.sheen
        anchors { fill: parent; margins: 1 }
        radius: Math.max(0, root.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.sheen }
            GradientStop { position: 0.5; color: "transparent" }
        }
    }

    // курсор: где и насколько «горит»
    HoverHandler {
        id: hover
        enabled: root.interactive
        onHoveredChanged: if (hovered && root.interactive) shineAnim.restart()
    }
    PointHandler { id: press; enabled: root.interactive; acceptedButtons: Qt.AllButtons }

    property real hoverLevel: (root.interactive && hover.hovered) ? 1 : 0
    Behavior on hoverLevel { NumberAnimation { duration: Theme.dBase; easing.type: Easing.OutCubic } }
    property real pressLevel: (root.interactive && press.active) ? 1 : 0
    Behavior on pressLevel { NumberAnimation { duration: press.active ? 60 : 380; easing.type: Easing.OutCubic } }
    // пятно света догоняет курсор с инерцией — стекло «тянется»
    property real lightX: width / 2
    property real lightY: 0
    Binding on lightX { when: root.interactive && hover.hovered; value: hover.point.position.x }
    Binding on lightY { when: root.interactive && hover.hovered; value: hover.point.position.y }
    Behavior on lightX { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutQuad } }
    Behavior on lightY { NumberAnimation { duration: Theme.dFast; easing.type: Easing.OutQuad } }
    property real shine: -1
    NumberAnimation on shine { id: shineAnim; running: false; from: 0; to: 1; duration: 850; easing.type: Easing.InOutQuad
        onFinished: root.shine = -1 }

    ShaderEffect {
        anchors.fill: parent
        z: 100
        property size size: Qt.size(width, height)
        property real radius: root.radius
        property real rimWidth: root.rimWidth
        property color rimColor: root.rimColor
        property color glintColor: root.glintColor
        property real angle: root.followCursor ? root.lightAngle : Math.atan2(-0.78, -0.63)
        property real hover: root.interactive ? root.hoverLevel : 0.0
        property point mouse: Qt.point(root.lightX, root.lightY)
        property real shine: root.interactive ? root.shine : -1.0
        property real press: root.interactive ? root.pressLevel : 0.0
        property real fresnel: root.fresnel
        fragmentShader: Qt.resolvedUrl("shaders/rim.frag.qsb")
    }
}
