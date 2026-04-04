import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import "../services"
import "../bar"

PanelWindow {
    id: root
    signal dismissed()

    anchors { bottom: true; left: true }
    margins { bottom: 8; left: 64 }
    implicitWidth: 160
    implicitHeight: content.implicitHeight + 20
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Colors.withAlpha(Colors.base, 0.95)
        border.width: 1
        border.color: Colors.withAlpha(Colors.surface2, 0.6)

        ColumnLayout {
            id: content
            anchors { fill: parent; margins: 10 }
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Text { text: "\uf011"; font.family: Colors.iconFont; font.pixelSize: 14; color: Colors.danger }
                Text { text: "Power"; font.family: Colors.fontFamily; font.pixelSize: 13; font.bold: true; color: Colors.text }
                Item { Layout.fillWidth: true }
                Text { text: "\uf00d"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

            SettingsButton { icon: "\uf023"; label: "Lock"; onActivated: { lockProc.running = true; root.dismissed(); } }
            SettingsButton { icon: "\uf186"; label: "Suspend"; onActivated: { suspendProc.running = true; root.dismissed(); } }
            SettingsButton { icon: "\uf2f1"; label: "Reboot"; onActivated: { rebootProc.running = true; root.dismissed(); } }
            SettingsButton { icon: "\uf011"; label: "Shutdown"; onActivated: { shutdownProc.running = true; root.dismissed(); } }
            SettingsButton { icon: "\uf2f5"; label: "Logout"; onActivated: { logoutProc.running = true; root.dismissed(); } }
        }
    }

    Process { id: lockProc; command: ["loginctl", "lock-session"] }
    Process { id: suspendProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["shutdown", "now"] }
    Process { id: logoutProc; command: ["sh", "-c", "loginctl kill-user $(whoami)"] }
}
