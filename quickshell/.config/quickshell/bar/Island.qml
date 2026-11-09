import QtQuick
import qs

// Стеклянная капсула под группу виджетов
Glass {
    default property alias content: row.data
    implicitWidth: row.implicitWidth + 28
    implicitHeight: Theme.barHeight
    radius: height / 2

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
    }
}
