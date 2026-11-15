import QtQuick
import qs

// Стеклянная капсула под группу виджетов
Glass {
    default property alias content: row.data
    implicitWidth: row.implicitWidth + 28
    implicitHeight: Theme.barHeight
    radius: 6
    interactive: false
    followCursor: false

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
    }
}
