import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import "../services"

Item {
    id: root
    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    property string currentMode: "balanced"
    property string displayText: "..."

    readonly property var modeIcons: ({
        "gaming": "\u{F0CB5}",
        "creator": "\u{F0B55}",
        "silent": "\u{F075F}",
        "balanced": "\u{F06F2}",
        "error": "!"
    })

    Process {
        id: listenProc
        running: true
        command: ["razer-power", "listen"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    root.displayText = data.text || "?";
                    root.currentMode = data.alt || "balanced";
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) running = true
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 2

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.modeIcons[root.currentMode] ?? "\u{F0FC0}"
            font.family: Colors.iconFont
            font.pixelSize: 14
            color: {
                switch (root.currentMode) {
                    case "gaming": return Colors.red;
                    case "creator": return Colors.mauve;
                    case "silent": return Colors.blue;
                    case "balanced": return Colors.green;
                    default: return Colors.danger;
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.displayText
            font.family: Colors.fontFamily
            font.pixelSize: 8
            color: Colors.subtext0
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: toggleProc.running = true
    }

    Process {
        id: toggleProc
        command: ["razer-power", "toggle"]
    }
}
