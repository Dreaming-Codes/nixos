import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import "../services"

Item {
    id: root
    implicitWidth: 28
    implicitHeight: col.implicitHeight

    property bool active: false
    property bool showRazer: false
    signal clicked()

    property string systemProfile: "balanced"
    property string razerMode: ""

    Component.onCompleted: { sysProfProc.running = true; if (showRazer) razerProc.running = true; }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: { sysProfProc.running = true; if (root.showRazer) razerProc.running = true; }
    }

    Process {
        id: sysProfProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser { onRead: line => { root.systemProfile = line.trim(); } }
    }

    Process {
        id: razerProc
        command: ["razer-power"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    root.razerMode = data.alt !== "error" ? data.alt : "";
                } catch (e) { root.razerMode = ""; }
            }
        }
    }

    readonly property color sysColor: {
        switch (systemProfile) {
            case "performance": return Colors.red;
            case "power-saver": return Colors.blue;
            default: return Colors.green;
        }
    }

    readonly property string sysIcon: {
        switch (systemProfile) {
            case "performance": return "\uf0e4";
            case "power-saver": return "\uf06c";
            default: return "\uf24e";
        }
    }

    readonly property string sysLabel: {
        switch (systemProfile) {
            case "performance": return "PERF";
            case "power-saver": return "SAVE";
            default: return "BAL";
        }
    }

    readonly property color razerColor: {
        switch (razerMode) {
            case "gaming": return Colors.red;
            case "creator": return Colors.mauve;
            case "silent": return Colors.blue;
            default: return Colors.green;
        }
    }

    readonly property string razerLabel: {
        switch (razerMode) {
            case "gaming": return "GAM";
            case "creator": return "CRE";
            case "silent": return "SIL";
            default: return "BAL";
        }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 1

        // System profile icon
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.sysIcon
            font.family: Colors.iconFont
            font.pixelSize: 13
            color: root.active ? Colors.primary : root.sysColor
        }

        // System profile label
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.sysLabel
            font.family: Colors.fontFamily
            font.pixelSize: 7
            font.bold: true
            color: root.sysColor
        }

        // Razer mode (laptop only)
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: root.showRazer && root.razerMode !== ""
            text: root.razerLabel
            font.family: Colors.fontFamily
            font.pixelSize: 7
            font.bold: true
            color: root.razerColor
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
