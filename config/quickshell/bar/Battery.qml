import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import "../services"

Item {
    id: root
    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    property int percent: 0
    property string status: ""
    property bool charging: status === "Charging" || status === "Full"
    property bool hasBattery: false

    visible: hasBattery

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            capProc.running = true;
            statusProc.running = true;
        }
    }

    Process {
        id: capProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo -1"]
        stdout: SplitParser {
            onRead: line => {
                const val = Number(line.trim());
                if (val >= 0) {
                    root.percent = val;
                    root.hasBattery = true;
                }
            }
        }
    }

    Process {
        id: statusProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo ''"]
        stdout: SplitParser {
            onRead: line => { root.status = line.trim(); }
        }
    }

    readonly property color indicatorColor: {
        if (charging) return Colors.green;
        if (percent <= 10) return Colors.danger;
        if (percent <= 25) return Colors.warning;
        return Colors.subtext1;
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 1

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (root.charging) return "\uf0e7";
                if (root.percent > 90) return "\uf240";
                if (root.percent > 60) return "\uf241";
                if (root.percent > 40) return "\uf242";
                if (root.percent > 10) return "\uf243";
                return "\uf244";
            }
            font.family: Colors.iconFont
            font.pixelSize: 13
            color: root.indicatorColor
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "BAT"
            font.family: Colors.fontFamily
            font.pixelSize: 7
            font.bold: true
            color: Colors.overlay1
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 24
            height: 3
            radius: 1.5
            color: Colors.withAlpha(Colors.surface0, 0.6)

            Rectangle {
                width: parent.width * Math.min(root.percent / 100, 1)
                height: parent.height
                radius: 1.5
                color: root.indicatorColor

                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.percent + "%"
            font.family: Colors.fontFamily
            font.pixelSize: 8
            color: Colors.subtext0
        }
    }
}
