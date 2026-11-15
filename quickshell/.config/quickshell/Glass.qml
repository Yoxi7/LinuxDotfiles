import QtQuick
import qs

// Статическая подложка под карточки, модальные окна и виджеты (без шейдеров и бликов)
Rectangle {
    id: root
    property bool sheen: false
    property color rimColor: Theme.rim
    property color glintColor: Theme.rim
    property real rimWidth: 1
    property real lightAngle: 0
    property bool followCursor: false
    property bool interactive: false
    property real fresnel: 0

    color: Theme.glass
    radius: Theme.radius
    border {
        width: Math.max(1, Math.round(root.rimWidth))
        color: root.rimColor
    }
}
