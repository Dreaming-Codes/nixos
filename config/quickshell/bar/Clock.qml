import QtQuick
import QtQuick.Layouts
import Quickshell

import "../services"

ColumnLayout {
    id: root
    spacing: 2

    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        height: 1
        color: Colors.withAlpha(Colors.surface2, 0.4)
    }

    // HH
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "HH")
        font.family: Colors.fontFamily
        font.pixelSize: 16
        font.bold: true
        color: Colors.primary
    }

    // MM
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "mm")
        font.family: Colors.fontFamily
        font.pixelSize: 16
        font.bold: true
        color: Colors.text
    }

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        height: 1
        color: Colors.withAlpha(Colors.surface2, 0.3)
    }

    // Day of week
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "ddd")
        font.family: Colors.fontFamily
        font.pixelSize: 9
        color: Colors.subtext1
    }

    // Day number
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "d")
        font.family: Colors.fontFamily
        font.pixelSize: 13
        font.bold: true
        color: Colors.text
    }

    // Month abbr
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDateTime(root.now, "MMM")
        font.family: Colors.fontFamily
        font.pixelSize: 9
        color: Colors.subtext1
    }
}
