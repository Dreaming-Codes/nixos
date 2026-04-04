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
    focusable: true

    property var networks: []
    property string activeSSID: ""
    property bool wifiEnabled: true
    property bool scanning: false
    property string passwordTarget: ""
    property bool showPassword: false

    Component.onCompleted: { statusProc.running = true; activeProc.running = true; listProc.running = true; }

    function refresh() {
        activeProc.running = true;
        listProc.running = true;
    }

    function scan() {
        root.scanning = true;
        scanProc.running = true;
    }

    // Get active wifi connection
    Process {
        id: activeProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active"]
        environment: ({ LANG: "C.UTF-8" })
        stdout: StdioCollector {
            onStreamFinished: {
                root.activeSSID = "";
                const lines = this.text.trim().split("\n");
                for (const line of lines) {
                    const parts = line.split(":");
                    if (parts.length >= 3 && parts[1] === "802-11-wireless") {
                        root.activeSSID = parts[0];
                        break;
                    }
                }
            }
        }
    }

    // List available networks (no rescan, fast)
    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "SIGNAL,SSID,SECURITY", "dev", "wifi", "list"]
        environment: ({ LANG: "C.UTF-8" })
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(l => l.length > 0);
                const nets = [];
                const seen = new Set();
                for (const line of lines) {
                    // Format: SIGNAL:SSID:SECURITY (SSID shouldn't contain :, but security might)
                    const firstColon = line.indexOf(":");
                    if (firstColon < 0) continue;
                    const signal = parseInt(line.substring(0, firstColon));
                    const rest = line.substring(firstColon + 1);
                    const lastColon = rest.lastIndexOf(":");
                    if (lastColon < 0) continue;
                    const ssid = rest.substring(0, lastColon);
                    const security = rest.substring(lastColon + 1);
                    if (!ssid || seen.has(ssid)) continue;
                    seen.add(ssid);
                    const isActive = ssid === root.activeSSID;
                    nets.push({ ssid, signal, active: isActive, security, secure: security !== "" && security !== "--" });
                }
                nets.sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
                root.networks = nets;
                root.scanning = false;
            }
        }
    }

    // Rescan (slow, triggers re-list after)
    Process {
        id: scanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        environment: ({ LANG: "C.UTF-8" })
        onExited: {
            // Wait a moment for scan results, then re-list
            scanDelay.start();
        }
    }
    Timer { id: scanDelay; interval: 2000; onTriggered: { listProc.running = true; activeProc.running = true; } }

    // Wifi radio status
    Process {
        id: statusProc
        command: ["nmcli", "radio", "wifi"]
        stdout: SplitParser { onRead: line => { root.wifiEnabled = line.trim() === "enabled"; } }
    }

    // Auto-refresh
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: refresh()
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
                Text { text: "\uf1eb"; font.family: Colors.iconFont; font.pixelSize: 16; color: Colors.teal }
                Text { text: "WiFi"; font.family: Colors.fontFamily; font.pixelSize: 14; font.bold: true; color: Colors.text }
                Item { Layout.fillWidth: true }
                // Scan
                Text {
                    text: "\uf021"
                    font.family: Colors.iconFont; font.pixelSize: 12
                    color: root.scanning ? Colors.primary : Colors.subtext1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.scan() }
                }
                Text { text: "\uf00d"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            // WiFi toggle
            RowLayout {
                Layout.fillWidth: true
                Text { text: "WiFi"; font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.subtext1 }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 36; height: 20; radius: 10
                    color: root.wifiEnabled ? Colors.primary : Colors.surface1
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2
                        x: root.wifiEnabled ? 18 : 2; color: Colors.text
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wifiToggleProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"];
                            wifiToggleProc.running = true;
                        }
                    }
                }
            }
            Process { id: wifiToggleProc; onExited: { statusProc.running = true; Qt.callLater(refresh); } }

            // Connected network
            Rectangle {
                visible: root.activeSSID !== ""
                Layout.fillWidth: true
                implicitHeight: connRow.implicitHeight + 10
                radius: 8
                color: Colors.withAlpha(Colors.green, 0.15)

                RowLayout {
                    id: connRow
                    anchors { fill: parent; margins: 6 }
                    spacing: 6
                    Text { text: "\uf1eb"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.green }
                    Text { text: root.activeSSID; font.family: Colors.fontFamily; font.pixelSize: 11; font.bold: true; color: Colors.green; Layout.fillWidth: true }
                    Rectangle {
                        width: 60; height: 22; radius: 6
                        color: Colors.withAlpha(Colors.danger, 0.3)
                        Text { anchors.centerIn: parent; text: "Disconnect"; font.family: Colors.fontFamily; font.pixelSize: 8; color: Colors.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { disconnProc.command = ["nmcli", "con", "down", root.activeSSID]; disconnProc.running = true; }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

            // Password entry
            ColumnLayout {
                visible: root.showPassword
                Layout.fillWidth: true
                spacing: 4
                Text { text: "Password for " + root.passwordTarget; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.subtext1 }
                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 6
                    color: Colors.withAlpha(Colors.surface0, 0.6)
                    border.width: 1; border.color: Colors.withAlpha(Colors.surface2, 0.4)
                    TextInput {
                        id: pwInput
                        anchors { fill: parent; margins: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.text
                        clip: true; focus: root.showPassword
                        onAccepted: {
                            if (text.length > 0) {
                                connectWithPwProc.command = ["nmcli", "dev", "wifi", "connect", root.passwordTarget, "password", text];
                                connectWithPwProc.running = true;
                                root.showPassword = false;
                                pwInput.text = "";
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        width: 60; height: 24; radius: 6; color: Colors.withAlpha(Colors.surface1, 0.5)
                        Text { anchors.centerIn: parent; text: "Cancel"; font.family: Colors.fontFamily; font.pixelSize: 9; color: Colors.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.showPassword = false; pwInput.text = ""; } }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 60; height: 24; radius: 6; color: Colors.withAlpha(Colors.primary, 0.3)
                        Text { anchors.centerIn: parent; text: "Connect"; font.family: Colors.fontFamily; font.pixelSize: 9; color: Colors.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pwInput.accepted() }
                    }
                }
            }
            Process { id: connectWithPwProc; onExited: Qt.callLater(refresh) }

            // Network list
            Text {
                visible: root.scanning && root.networks.length === 0
                text: "Scanning..."
                font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.overlay1
                Layout.alignment: Qt.AlignHCenter
            }

            Flickable {
                visible: !root.showPassword && root.networks.length > 0
                Layout.fillWidth: true
                Layout.maximumHeight: 350
                Layout.minimumHeight: 40
                contentHeight: netCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: netCol
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.networks
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: netRow.implicitHeight + 10
                            radius: 8
                            visible: !modelData.active
                            color: Colors.withAlpha(Colors.surface0, 0.4)

                            RowLayout {
                                id: netRow
                                anchors { fill: parent; margins: 6 }
                                spacing: 6

                                Text {
                                    text: "\uf1eb"
                                    font.family: Colors.iconFont; font.pixelSize: 12
                                    opacity: Math.max(0.3, modelData.signal / 100)
                                    color: Colors.subtext1
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text { text: modelData.ssid; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 4
                                        Text { text: modelData.signal + "%"; font.family: Colors.fontFamily; font.pixelSize: 8; color: Colors.overlay0 }
                                        Text { visible: modelData.secure; text: "\uf023"; font.family: Colors.iconFont; font.pixelSize: 8; color: Colors.overlay0 }
                                        Text { visible: modelData.security !== ""; text: modelData.security; font.family: Colors.fontFamily; font.pixelSize: 7; color: Colors.overlay0 }
                                    }
                                }

                                Rectangle {
                                    width: 55; height: 22; radius: 6
                                    color: Colors.withAlpha(Colors.green, 0.3)
                                    Text { anchors.centerIn: parent; text: "Connect"; font.family: Colors.fontFamily; font.pixelSize: 8; color: Colors.text }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.secure) {
                                                tryConnProc.ssid = modelData.ssid;
                                                tryConnProc.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid];
                                                tryConnProc.running = true;
                                            } else {
                                                connProc.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid];
                                                connProc.running = true;
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "\uf1f8"; font.family: Colors.iconFont; font.pixelSize: 10; color: Colors.overlay1
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { forgetProc.command = ["nmcli", "con", "delete", modelData.ssid]; forgetProc.running = true; }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Process { id: disconnProc; onExited: Qt.callLater(refresh) }
            Process { id: connProc; onExited: Qt.callLater(refresh) }
            Process { id: forgetProc; onExited: Qt.callLater(refresh) }

            Process {
                id: tryConnProc
                property string ssid: ""
                onExited: exitCode => {
                    if (exitCode === 0) {
                        Qt.callLater(refresh);
                    } else {
                        root.passwordTarget = ssid;
                        root.showPassword = true;
                    }
                }
            }
        }
    }
}
