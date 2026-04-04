import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
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

    PwObjectTracker {
        objects: {
            const list = [];
            if (Pipewire.defaultAudioSink) list.push(Pipewire.defaultAudioSink);
            if (Pipewire.defaultAudioSource) list.push(Pipewire.defaultAudioSource);
            for (const n of Pipewire.nodes.values) {
                if (n.audio) list.push(n);
            }
            return list;
        }
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
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text { text: "\uf028"; font.family: Colors.iconFont; font.pixelSize: 16; color: Colors.primary }
                Text { text: "Audio"; font.family: Colors.fontFamily; font.pixelSize: 14; font.bold: true; color: Colors.text }
                Item { Layout.fillWidth: true }
                Text { text: "\uf00d"; font.family: Colors.iconFont; font.pixelSize: 12; color: Colors.overlay1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            // Output volume
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Output"; font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.subtext1 }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Pipewire.defaultAudioSink?.audio?.muted ? "\uf6a9" : "\uf028"
                        font.family: Colors.iconFont; font.pixelSize: 14
                        color: Pipewire.defaultAudioSink?.audio?.muted ? Colors.danger : Colors.subtext1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { const a = Pipewire.defaultAudioSink?.audio; if (a) a.muted = !a.muted; }
                        }
                    }
                    Text {
                        text: Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100) + "%"
                        font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.subtext0
                    }
                }
                VolumeSlider {
                    Layout.fillWidth: true
                    from: 0; to: 1.0; stepSize: 0.01
                    value: Pipewire.defaultAudioSink?.audio?.volume ?? 0
                    onMoved: { const a = Pipewire.defaultAudioSink?.audio; if (a) { a.muted = false; a.volume = value; } }
                }
            }

            // Output device selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Output Device"; font.family: Colors.fontFamily; font.pixelSize: 10; font.bold: true; color: Colors.overlay1 }
                Repeater {
                    model: {
                        const list = [];
                        for (const n of Pipewire.nodes.values) {
                            if (!n.isStream && n.isSink && n.audio) list.push(n);
                        }
                        return list;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 26; radius: 6
                        color: Pipewire.defaultAudioSink?.id === modelData.id ? Colors.withAlpha(Colors.primary, 0.2) : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            Text { text: modelData.description || modelData.name; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

            // Input volume
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Input"; font.family: Colors.fontFamily; font.pixelSize: 11; color: Colors.subtext1 }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Pipewire.defaultAudioSource?.audio?.muted ? "\uf131" : "\uf130"
                        font.family: Colors.iconFont; font.pixelSize: 14
                        color: Pipewire.defaultAudioSource?.audio?.muted ? Colors.danger : Colors.subtext1
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { const a = Pipewire.defaultAudioSource?.audio; if (a) a.muted = !a.muted; }
                        }
                    }
                    Text {
                        text: Math.round((Pipewire.defaultAudioSource?.audio?.volume ?? 0) * 100) + "%"
                        font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.subtext0
                    }
                }
                VolumeSlider {
                    Layout.fillWidth: true
                    from: 0; to: 1.0; stepSize: 0.01
                    value: Pipewire.defaultAudioSource?.audio?.volume ?? 0
                    onMoved: { const a = Pipewire.defaultAudioSource?.audio; if (a) { a.muted = false; a.volume = value; } }
                }
            }

            // Input device selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Input Device"; font.family: Colors.fontFamily; font.pixelSize: 10; font.bold: true; color: Colors.overlay1 }
                Repeater {
                    model: {
                        const list = [];
                        for (const n of Pipewire.nodes.values) {
                            if (!n.isStream && !n.isSink && n.audio) list.push(n);
                        }
                        return list;
                    }
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 26; radius: 6
                        color: Pipewire.defaultAudioSource?.id === modelData.id ? Colors.withAlpha(Colors.primary, 0.2) : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            Text { text: modelData.description || modelData.name; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: Pipewire.preferredDefaultAudioSource = modelData
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Colors.withAlpha(Colors.surface2, 0.3) }

            // Per-app mixer
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text { text: "App Mixer"; font.family: Colors.fontFamily; font.pixelSize: 10; font.bold: true; color: Colors.overlay1 }
                Repeater {
                    model: {
                        const list = [];
                        for (const n of Pipewire.nodes.values) {
                            if (n.isStream && n.audio) list.push(n);
                        }
                        return list;
                    }
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.properties?.["application.name"] ?? modelData.description ?? modelData.name ?? "Unknown"
                                font.family: Colors.fontFamily; font.pixelSize: 9; color: Colors.text; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            Text {
                                text: Math.round((modelData.audio?.volume ?? 0) * 100) + "%"
                                font.family: Colors.fontFamily; font.pixelSize: 9; color: Colors.subtext0
                            }
                        }
                        VolumeSlider {
                            Layout.fillWidth: true
                            from: 0; to: 1.0; stepSize: 0.01
                            value: modelData.audio?.volume ?? 0
                            onMoved: { if (modelData.audio) modelData.audio.volume = value; }
                        }
                    }
                }
                Text {
                    visible: {
                        for (const n of Pipewire.nodes.values) { if (n.isStream && n.audio) return false; }
                        return true;
                    }
                    text: "No apps playing"; font.family: Colors.fontFamily; font.pixelSize: 10; color: Colors.overlay1
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
