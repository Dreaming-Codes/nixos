//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

import "bar"
import "notifications"
import "panels"
import "lock"
import "services"

ShellRoot {
    id: shell
    settings.watchFiles: true

    readonly property string platform: Quickshell.env("QS_PLATFORM") ?? ""
    readonly property bool isLaptop: platform === "blade"

    property bool notifCenterOpen: false
    property string activePanel: ""
    property ShellScreen activeScreen: Quickshell.screens[0] ?? null

    readonly property bool anyPanelOpen: activePanel !== "" || notifCenterOpen

    function closeAll() {
        activePanel = "";
        notifCenterOpen = false;
    }

    function togglePanel(name, fromScreen) {
        if (activePanel === name) {
            activePanel = "";
        } else {
            activePanel = name;
            notifCenterOpen = false;
            if (fromScreen) activeScreen = fromScreen;
        }
    }

    function toggleNotifs(fromScreen) {
        notifCenterOpen = !notifCenterOpen;
        if (notifCenterOpen) {
            activePanel = "";
            if (fromScreen) activeScreen = fromScreen;
        }
    }

    NotifManager { id: notifManager }

    // Backdrop per screen to catch outside clicks
    Variants {
        model: shell.anyPanelOpen ? Quickshell.screens : []
        delegate: PanelBackdrop {
            required property ShellScreen modelData
            screen: modelData
            onClicked: shell.closeAll()
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property ShellScreen modelData
            screen: modelData
            showRazerPower: shell.isLaptop
            notifManager: notifManager
            notifCenterOpen: shell.notifCenterOpen
            activePanel: shell.activePanel
            onToggleNotifCenter: shell.toggleNotifs(modelData)
            onTogglePanel: name => shell.togglePanel(name, modelData)
        }
    }

    LazyLoader {
        active: (notifManager.popupQueue?.length ?? 0) > 0

        NotifPopups {
            screen: shell.activeScreen
            notifManager: notifManager
        }
    }

    LazyLoader {
        active: shell.notifCenterOpen

        NotifCenterPanel {
            screen: shell.activeScreen
            notifManager: notifManager
            onDismissed: shell.notifCenterOpen = false
        }
    }

    LazyLoader {
        active: shell.activePanel === "audio"

        AudioPanel {
            screen: shell.activeScreen
            onDismissed: shell.activePanel = ""
        }
    }

    LazyLoader {
        active: shell.activePanel === "bluetooth"

        BluetoothPanel {
            screen: shell.activeScreen
            onDismissed: shell.activePanel = ""
        }
    }

    LazyLoader {
        active: shell.activePanel === "wifi"

        WiFiPanel {
            screen: shell.activeScreen
            onDismissed: shell.activePanel = ""
        }
    }

    LazyLoader {
        active: shell.activePanel === "power"

        PowerPanel {
            screen: shell.activeScreen
            onDismissed: shell.activePanel = ""
        }
    }

    Lock { id: sessionLock }

    Process {
        running: true
        command: ["sh", "-c", "gdbus monitor --system --dest org.freedesktop.login1 2>/dev/null | grep --line-buffered 'Lock'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("Lock")) sessionLock.locked = true;
            }
        }
        onRunningChanged: if (!running) running = true
    }
}
