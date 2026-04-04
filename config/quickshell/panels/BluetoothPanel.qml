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
    implicitWidth: 300
    implicitHeight: content.implicitHeight + 20
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    property var devices: []
    property bool powered: false
    property bool scanning: false

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: refreshProc.running = true
    }

    Process {
        id: refreshProc
        command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(l => l.length > 0);
                const devs = [];
                for (const line of lines) {
                    const match = line.match(/^Device\s+(\S+)\s+(.+)$/);
                    if (match) devs.push({ mac: match[1], name: match[2], connected: false, paired: false });
                }
                // Now get info for each
                root.devices = devs;
                infoProc.running = true;
            }
        }
    }

    Process {
        id: infoProc
        command: ["bluetoothctl", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Parse all device info blocks
                const blocks = this.text.split("Device ");
                const updated = [...root.devices];
                for (const block of blocks) {
                    const macMatch = block.match(/^(\S+)/);
                    if (!macMatch) continue;
                    const mac = macMatch[1];
                    const dev = updated.find(d => d.mac === mac);
                    if (!dev) continue;
                    dev.connected = block.includes("Connected: yes");
                    dev.paired = block.includes("Paired: yes");
                }
                root.devices = updated;
            }
        }
    }

    Process {
        id: powerProc
        command: ["bluetoothctl", "show"]
        stdout: StdioCollector {
            onStreamFinished: { root.powered = this.text.includes("Powered: yes"); }
        }
        Component.onCompleted: running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Colors.withAlpha(Colors.base, 0.95)
        border.width: 1
        border.color: Colors.withAlpha(Colors.surface2, 0.6)

        ColumnLayout {
            id: content
            anchors { fill: parent; margins: 12 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text { text: "\uf294"; font.family: Colors.iconFont; font.pixelSize: 16; color: Colors.blue }
                Text { text: "Bluetooth"; font.family: Colors.fontFamily; font.pixelSize: 14; font.bold: true; color: Colors.text }
                Item { Layout.fillWidth: true }
                Text { text: "\uf00d"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            // Power toggle
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Power"; font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.subtext1 }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 36; height: 20; radius: 10
                    color: root.powered ? Colors.primary : Colors.surface1
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.powered ? 18 : 2
                        color: Colors.text
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const turningOff = root.powered;
                            toggleProc.turningOff = turningOff;
                            toggleProc.command = ["bluetoothctl", "power", turningOff ? "off" : "on"];
                            toggleProc.running = true;
                        }
                    }
                }
            }

            Process {
                id: toggleProc
                property bool turningOff: false
                onExited: {
                    powerProc.running = true;
                    if (turningOff) {
                        root.devices = [];
                        root.scanning = false;
                    } else {
                        Qt.callLater(() => { refreshProc.running = true; });
                    }
                }
            }

            // Scan button
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Scan"; font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.subtext1 }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 60; height: 24; radius: 6
                    color: root.scanning ? Colors.withAlpha(Colors.danger, 0.3) : Colors.withAlpha(Colors.primary, 0.3)
                    Text {
                        anchors.centerIn: parent
                        text: root.scanning ? "Stop" : "Scan"
                        font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.text
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.scanning = !root.scanning;
                            scanProc.command = ["bluetoothctl", root.scanning ? "scan" : "scan", root.scanning ? "on" : "off"];
                            scanProc.running = true;
                            if (root.scanning) scanTimer.start();
                            else scanTimer.stop();
                        }
                    }
                }
            }

            Process { id: scanProc }
            Timer { id: scanTimer; interval: 15000; onTriggered: { root.scanning = false; scanStopProc.running = true; refreshProc.running = true; } }
            Process { id: scanStopProc; command: ["bluetoothctl", "scan", "off"] }

            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

            // Device list
            Flickable {
                Layout.fillWidth: true
                Layout.maximumHeight: 300
                Layout.minimumHeight: 40
                contentHeight: devCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: devCol
                    width: parent.width
                    spacing: 4

                    Text {
                        visible: root.devices.length === 0
                        text: "No devices found"
                        font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.overlay1
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: root.devices
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: devRow.implicitHeight + 12
                            radius: 8
                            color: Colors.withAlpha(Colors.surface0, 0.4)

                            RowLayout {
                                id: devRow
                                anchors { fill: parent; margins: 6 }
                                spacing: 6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { text: modelData.name; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: modelData.mac; font.family: Colors.fontFamily; font.pixelSize: 8; color: Colors.overlay0 }
                                }

                                // Status
                                Text {
                                    text: modelData.connected ? "ON" : (modelData.paired ? "OFF" : "")
                                    font.family: Colors.fontFamily; font.pixelSize: 8; font.bold: true
                                    color: modelData.connected ? Colors.green : Colors.overlay1
                                }

                                // Connect/Disconnect
                                Rectangle {
                                    width: 50; height: 22; radius: 6
                                    color: modelData.connected ? Colors.withAlpha(Colors.danger, 0.3) : Colors.withAlpha(Colors.green, 0.3)
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.connected ? "Disc." : "Conn."
                                        font.family: Colors.fontFamily; font.pixelSize: 8; color: Colors.text
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const action = modelData.connected ? "disconnect" : "connect";
                                            btActionProc.command = ["bluetoothctl", action, modelData.mac];
                                            btActionProc.running = true;
                                        }
                                    }
                                }

                                // Forget
                                Text {
                                    visible: modelData.paired
                                    text: "\uf1f8"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            btActionProc.command = ["bluetoothctl", "remove", modelData.mac];
                                            btActionProc.running = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Process {
                id: btActionProc
                onExited: { Qt.callLater(() => { refreshProc.running = true; }); }
            }
        }
    }
}
