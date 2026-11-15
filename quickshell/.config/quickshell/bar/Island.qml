import QtQuick
import qs

// Минималистичный остров под группу виджетов
Rectangle {
    default property alias content: row.data
    implicitWidth: row.implicitWidth + 28
    implicitHeight: Theme.barHeight
    radius: 6
    color: Theme.glass
    border.width: 1
    border.color: Theme.rim

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
    }
}
