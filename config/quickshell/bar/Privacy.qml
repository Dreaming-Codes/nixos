import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import "../services"

ColumnLayout {
    id: root
    spacing: 4

    property bool micActive: false
    property bool cameraActive: false

    visible: micActive || cameraActive

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            micProc.running = true;
            camProc.running = true;
        }
    }

    Process {
        id: micProc
        command: ["sh", "-c", "pactl list source-outputs 2>/dev/null | grep -c 'Source Output' || echo 0"]
        stdout: SplitParser {
            onRead: line => {
                root.micActive = Number(line.trim()) > 0;
            }
        }
    }

    Process {
        id: camProc
        command: ["sh", "-c", "ls /dev/video* 2>/dev/null | while read dev; do fuser $dev 2>/dev/null && echo 1; done | head -1"]
        stdout: SplitParser {
            onRead: line => {
                root.cameraActive = line.trim() !== "";
            }
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        visible: root.micActive
        text: "\uf130"
        font.family: Colors.iconFont
        font.pixelSize: 14
        color: Colors.danger
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        visible: root.cameraActive
        text: "\uf030"
        font.family: Colors.iconFont
        font.pixelSize: 14
        color: Colors.danger
    }
}
