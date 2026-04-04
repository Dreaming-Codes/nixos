import QtQuick
import Quickshell.Io

import "../services"

Item {
    id: root
    implicitWidth: 28
    implicitHeight: 24

    property bool inhibiting: false

    // Long-running process that holds the inhibit lock
    Process {
        id: inhibitProc
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=quickshell", "--why=Caffeine mode", "sleep", "infinity"]
        running: root.inhibiting
    }

    Text {
        anchors.centerIn: parent
        text: root.inhibiting ? "\uf0f4" : "\uf0f4"
        font.family: Colors.iconFont
        font.pixelSize: 14
        color: root.inhibiting ? Colors.warning : Colors.surface2
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.inhibiting = !root.inhibiting
    }
}
