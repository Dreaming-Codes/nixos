import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool ok: false
    property string statusText: "..."
    property string statusAlt: "loading"
    property string powerSource: "ac"
    property string acDisplay: "--"
    property string batDisplay: "--"
    property string statusBuffer: ""
    property string actionLabel: ""
    property string errorText: ""
    property int customCpuBoost: parseInt(pluginData.customCpuBoost ?? 3)
    property int customGpuBoost: parseInt(pluginData.customGpuBoost ?? 2)

    function customArgs() {
        var raw = (pluginData.customPowerArgs || "").trim()
        if (raw.length > 0)
            return raw.split(/\s+/)
        return ["4", String(customCpuBoost), String(customGpuBoost)]
    }

    function setCustomBoost(kind, value) {
        if (kind === "cpu")
            customCpuBoost = value
        else
            customGpuBoost = value
        if (pluginService)
            pluginService.savePluginData("razerEnergy", kind === "cpu" ? "customCpuBoost" : "customGpuBoost", value)
    }

    function refresh() {
        if (!statusProc.running) {
            statusBuffer = ""
            statusProc.running = true
        }
    }

    function applyMode(source, mode, label) {
        if (actionProc.running)
            return
        actionLabel = label
        actionProc.command = ["razer-energy", "set", source, mode]
        actionProc.running = true
    }

    function applyCustom(source) {
        if (actionProc.running)
            return
        actionLabel = "Custom " + source.toUpperCase()
        actionProc.command = ["razer-energy", "set", source].concat(customArgs())
        actionProc.running = true
    }

    Process {
        id: statusProc
        command: ["razer-energy", "json"]

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.statusBuffer += data
        }

        stderr: SplitParser {
            onRead: line => root.errorText = line
        }

        onExited: exitCode => {
            if (exitCode === 0 && root.statusBuffer.length > 0) {
                try {
                    var data = JSON.parse(root.statusBuffer)
                    root.ok = data.ok === true
                    root.statusText = data.text || "!"
                    root.statusAlt = data.alt || "unknown"
                    root.powerSource = data.source || "ac"
                    root.acDisplay = data.ac ? data.ac.display : "--"
                    root.batDisplay = data.bat ? data.bat.display : "--"
                    root.errorText = data.error || ""
                } catch (e) {
                    root.ok = false
                    root.statusText = "!"
                    root.statusAlt = "parse-error"
                    root.errorText = "Failed to parse razer-energy output"
                }
            } else {
                root.ok = false
                root.statusText = "!"
                root.statusAlt = "error"
                if (root.errorText === "")
                    root.errorText = "razer-energy exited with code " + exitCode
            }
            root.statusBuffer = ""
        }
    }

    Process {
        id: actionProc

        stderr: SplitParser {
            onRead: line => root.errorText = line
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                ToastService.showInfo("Razer Power", root.actionLabel)
            } else {
                ToastService.showError("Razer Power", root.errorText || ("command exited with code " + exitCode))
            }
            root.refresh()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.powerSource === "ac" ? "bolt" : "battery_charging_full"
                color: root.ok ? Theme.primary : Theme.error
                size: Theme.iconSize - 4
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.statusText
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.powerSource === "ac" ? "bolt" : "battery_charging_full"
                color: root.ok ? Theme.primary : Theme.error
                size: Theme.iconSize - 4
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.statusText.substring(0, 3)
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "Razer Energy"
            detailsText: root.powerSource === "ac" ? "On AC power" : "On battery"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    height: stateColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: stateColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: root.ok ? ("Current: " + root.statusText) : "Razer state unavailable"
                            color: root.ok ? Theme.surfaceText : Theme.error
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                        }

                        StyledText {
                            text: "AC: " + root.acDisplay + "   Battery: " + root.batDisplay
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            visible: root.errorText !== ""
                            text: root.errorText
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }

                Grid {
                    columns: 2
                    columnSpacing: Theme.spacingS
                    rowSpacing: Theme.spacingS
                    width: parent.width

                    Repeater {
                        model: [
                            { label: "Balanced", mode: "balanced", icon: "balance" },
                            { label: "Gaming", mode: "gaming", icon: "sports_esports" },
                            { label: "Creator", mode: "creator", icon: "edit" },
                            { label: "Silent", mode: "silent", icon: "volume_off" }
                        ]

                        StyledRect {
                            required property var modelData
                            width: (parent.width - Theme.spacingS) / 2
                            height: 54
                            radius: Theme.cornerRadius
                            color: modeArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: modelData.icon
                                    color: Theme.primary
                                    size: Theme.iconSize - 2
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: modelData.label
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: modeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyMode("current", modelData.mode, modelData.label)
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: customColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: customColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Custom boost"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                        }

                        Repeater {
                            model: [
                                { label: "CPU", kind: "cpu", value: root.customCpuBoost },
                                { label: "GPU", kind: "gpu", value: root.customGpuBoost }
                            ]

                            Row {
                                id: boostRow
                                required property var modelData
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    width: 42
                                    text: modelData.label
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Repeater {
                                    model: [0, 1, 2, 3]

                                    StyledRect {
                                        required property int modelData
                                        property bool selected: modelData === boostRow.modelData.value
                                        width: 44
                                        height: 34
                                        radius: Theme.cornerRadius
                                        color: selected ? Theme.primary : boostArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: String(modelData)
                                            color: parent.selected ? Theme.onPrimary : Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                        }

                                        MouseArea {
                                            id: boostArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setCustomBoost(boostRow.modelData.kind, modelData)
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: "Command: razer-cli write power <source> 4 " + root.customCpuBoost + " " + root.customGpuBoost
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: [
                            { label: "Custom Current", source: "current" },
                            { label: "Custom AC", source: "ac" },
                            { label: "Custom Battery", source: "bat" }
                        ]

                        StyledRect {
                            required property var modelData
                            width: (parent.width - Theme.spacingS * 2) / 3
                            height: 48
                            radius: Theme.cornerRadius
                            color: customArea.containsMouse ? Theme.primary : Theme.surfaceContainerHigh

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: customArea.containsMouse ? Theme.onPrimary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: customArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.applyCustom(modelData.source)
                            }
                        }
                    }
                }
            }
        }
    }
}
