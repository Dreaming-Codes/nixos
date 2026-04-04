import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import "../services"

PanelWindow {
    id: root
    signal dismissed()

    anchors { bottom: true; left: true }
    margins { bottom: 8; left: 64 }
    implicitWidth: 220
    implicitHeight: content.implicitHeight + 20
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    property bool showRazer: false

    // Razer power state
    property string razerMode: "balanced"
    property string razerPowerSource: "ac"
    property bool razerAvailable: false

    // System power profile state
    property string systemProfile: "balanced"

    Component.onCompleted: {
        sysProfileProc.running = true;
        if (showRazer) { razerProc.running = true; powerSourceProc.running = true; }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            sysProfileProc.running = true;
            if (root.showRazer) { razerProc.running = true; powerSourceProc.running = true; }
        }
    }

    // Get current power source
    Process {
        id: powerSourceProc
        command: ["sh", "-c", "cat /sys/class/power_supply/AC0/online 2>/dev/null || echo 1"]
        stdout: SplitParser {
            onRead: line => { root.razerPowerSource = line.trim() === "0" ? "bat" : "ac"; }
        }
    }

    // Get razer power mode
    Process {
        id: razerProc
        command: ["razer-power"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    root.razerMode = data.alt || "balanced";
                    root.razerAvailable = data.alt !== "error";
                } catch (e) { root.razerAvailable = false; }
            }
        }
    }

    // Get system power profile
    Process {
        id: sysProfileProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: line => { root.systemProfile = line.trim(); }
        }
    }

    readonly property var razerModes: [
        { id: 0, name: "Balanced", key: "balanced", icon: "\uf24e", color: Colors.green },
        { id: 1, name: "Gaming",   key: "gaming",   icon: "\uf11b", color: Colors.red },
        { id: 2, name: "Creator",  key: "creator",  icon: "\uf1fc", color: Colors.mauve },
        { id: 3, name: "Silent",   key: "silent",   icon: "\uf4b3", color: Colors.blue }
    ]

    readonly property var systemProfiles: [
        { name: "Performance", key: "performance",  icon: "\uf0e4", color: Colors.red },
        { name: "Balanced",    key: "balanced",     icon: "\uf24e", color: Colors.green },
        { name: "Power Saver", key: "power-saver",  icon: "\uf06c", color: Colors.blue }
    ]

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Colors.withAlpha(Colors.base, 0.95)
        border.width: 1
        border.color: Colors.withAlpha(Colors.surface2, 0.6)

        ColumnLayout {
            id: content
            anchors { fill: parent; margins: 12 }
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text { text: "\uf0e4"; font.family: Colors.iconFont; font.pixelSize: 16; color: Colors.primary }
                Text { text: "Power Profiles"; font.family: Colors.fontFamily; font.pixelSize: 13; font.bold: true; color: Colors.text }
                Item { Layout.fillWidth: true }
                Text { text: "\uf00d"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            // System Power Profile
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "System Profile"
                    font.family: Colors.fontFamily; font.pixelSize: 11; font.bold: true; color: Colors.subtext1
                }

                Repeater {
                    model: root.systemProfiles
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: root.systemProfile === modelData.key ? Colors.withAlpha(modelData.color, 0.2) : Colors.withAlpha(Colors.surface0, 0.3)
                        border.width: root.systemProfile === modelData.key ? 1 : 0
                        border.color: Colors.withAlpha(modelData.color, 0.5)

                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 8
                            Text {
                                text: modelData.icon
                                font.family: Colors.iconFont; font.pixelSize: 14
                                color: root.systemProfile === modelData.key ? modelData.color : Colors.overlay1
                            }
                            Text {
                                text: modelData.name
                                font.family: Colors.fontFamily; font.pixelSize: 11
                                color: root.systemProfile === modelData.key ? Colors.text : Colors.subtext0
                                font.bold: root.systemProfile === modelData.key
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: root.systemProfile === modelData.key
                                text: "\uf00c"
                                font.family: Colors.iconFont; font.pixelSize: 10
                                color: modelData.color
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setSysProfileProc.command = ["powerprofilesctl", "set", modelData.key];
                                setSysProfileProc.running = true;
                            }
                        }
                    }
                }
            }

            Process {
                id: setSysProfileProc
                onExited: sysProfileProc.running = true
            }

            // Razer section (laptop only, when razer-cli is available)
            ColumnLayout {
                visible: root.showRazer && root.razerAvailable
                Layout.fillWidth: true
                spacing: 4

                Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Razer Mode"
                        font.family: Colors.fontFamily; font.pixelSize: 11; font.bold: true; color: Colors.subtext1
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.razerPowerSource === "ac" ? "AC" : "BAT"
                        font.family: Colors.fontFamily; font.pixelSize: 9
                        color: Colors.overlay0
                    }
                }

                Repeater {
                    model: root.razerModes
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: 8
                        color: root.razerMode === modelData.key ? Colors.withAlpha(modelData.color, 0.2) : Colors.withAlpha(Colors.surface0, 0.3)
                        border.width: root.razerMode === modelData.key ? 1 : 0
                        border.color: Colors.withAlpha(modelData.color, 0.5)

                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            spacing: 8
                            Text {
                                text: modelData.icon
                                font.family: Colors.iconFont; font.pixelSize: 14
                                color: root.razerMode === modelData.key ? modelData.color : Colors.overlay1
                            }
                            Text {
                                text: modelData.name
                                font.family: Colors.fontFamily; font.pixelSize: 11
                                color: root.razerMode === modelData.key ? Colors.text : Colors.subtext0
                                font.bold: root.razerMode === modelData.key
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: root.razerMode === modelData.key
                                text: "\uf00c"
                                font.family: Colors.iconFont; font.pixelSize: 10
                                color: modelData.color
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setRazerProc.command = ["razer-cli", "write", "power", root.razerPowerSource, String(modelData.id)];
                                setRazerProc.running = true;
                            }
                        }
                    }
                }
            }

            Process {
                id: setRazerProc
                onExited: razerProc.running = true
            }
        }
    }
}
