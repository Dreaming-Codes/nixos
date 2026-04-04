import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import "../services"
import "../notifications"

PanelWindow {
    id: root

    property var notifManager: null
    property bool notifCenterOpen: false
    property string activePanel: ""
    property bool isLaptop: false
    signal toggleNotifCenter()
    signal togglePanel(string panel)

    anchors {
        top: true
        bottom: true
        left: true
    }

    implicitWidth: 48
    exclusiveZone: implicitWidth + margins.left
    margins { top: 8; bottom: 8; left: 8 }
    color: "transparent"

    readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(screen)

    Rectangle {
        id: barBg
        anchors.fill: parent
        radius: 14
        color: Colors.withAlpha(Colors.background, Colors.barOpacity)
        border.width: 1
        border.color: Colors.withAlpha(Colors.surface1, 0.3)
    }

    ColumnLayout {
        id: barContent
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 6

        Workspaces {
            Layout.fillWidth: true
            hyprMonitor: root.hyprMonitor
        }

        Item { Layout.fillHeight: true }

        Tray {
            Layout.fillWidth: true
            barWindow: root
        }

        Battery {
            Layout.fillWidth: true
        }

        SystemInfo {
            Layout.fillWidth: true
        }

        Clock {
            Layout.fillWidth: true
        }

        Privacy {
            Layout.fillWidth: true
        }

        Caffeine {
            Layout.fillWidth: true
        }

        // Quick action icons
        ProfileIcon {
            Layout.fillWidth: true
            active: root.activePanel === "profile"
            showRazer: root.isLaptop
            onClicked: root.togglePanel("profile")
        }

        BarIcon {
            Layout.fillWidth: true
            icon: "\uf028"
            active: root.activePanel === "audio"
            activeColor: Colors.primary
            onClicked: root.togglePanel("audio")
        }

        BarIcon {
            Layout.fillWidth: true
            icon: "\uf294"
            active: root.activePanel === "bluetooth"
            activeColor: Colors.blue
            onClicked: root.togglePanel("bluetooth")
        }

        BarIcon {
            Layout.fillWidth: true
            icon: "\uf1eb"
            active: root.activePanel === "wifi"
            activeColor: Colors.teal
            onClicked: root.togglePanel("wifi")
        }

        BarIcon {
            Layout.fillWidth: true
            icon: "\uf011"
            active: root.activePanel === "power"
            activeColor: Colors.danger
            onClicked: root.togglePanel("power")
        }

        NotifBell {
            Layout.fillWidth: true
            notifManager: root.notifManager
            notifCenterOpen: root.notifCenterOpen
            onToggleNotifCenter: root.toggleNotifCenter()
            onToggleDnd: {
                if (root.notifManager) root.notifManager.dnd = !root.notifManager.dnd;
            }
        }
    }
}
