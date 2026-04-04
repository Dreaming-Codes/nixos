import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import "../services"

ColumnLayout {
    id: root
    spacing: 3

    required property HyprlandMonitor hyprMonitor

    readonly property int activeWsId: hyprMonitor.activeWorkspace?.id ?? -1

    readonly property var workspaceList: {
        const list = [];
        for (const ws of Hyprland.workspaces.values) {
            if (ws.name && ws.name.startsWith("special:")) continue;
            // Only show workspaces assigned to this monitor
            if (ws.monitor && ws.monitor !== root.hyprMonitor) continue;
            list.push(ws);
        }
        list.sort((a, b) => a.id - b.id);
        return list;
    }

    Repeater {
        model: root.workspaceList

        delegate: Rectangle {
            id: wsBtn
            required property var modelData

            readonly property int wsId: modelData.id
            readonly property string wsName: modelData.name ?? String(wsId)
            readonly property bool isActive: root.activeWsId === wsId

            Layout.fillWidth: true
            Layout.preferredHeight: isActive ? 28 : 18

            radius: 7
            color: {
                if (isActive) {
                    const idx = Math.abs(wsId - 1) % Colors.workspaceColors.length;
                    return Colors.workspaceColors[idx];
                }
                return Colors.withAlpha(Colors.surface1, 0.5);
            }

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Text {
                anchors.centerIn: parent
                text: {
                    const name = wsBtn.wsName;
                    // Numeric workspaces: just show number
                    if (name === String(wsBtn.wsId)) return name;
                    // Named workspaces: abbreviate
                    // "ALT1" -> "A1", "F1" -> "F1"
                    if (name.startsWith("ALT")) return "A" + name.substring(3);
                    if (name.length > 3) return name.substring(0, 3);
                    return name;
                }
                font.family: Colors.fontFamily
                font.pixelSize: wsBtn.isActive ? 11 : 9
                font.bold: wsBtn.isActive
                color: wsBtn.isActive ? Colors.crust : Colors.subtext0
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Hyprland.dispatch(`workspace ${wsBtn.wsId}`)
            }
        }
    }
}
