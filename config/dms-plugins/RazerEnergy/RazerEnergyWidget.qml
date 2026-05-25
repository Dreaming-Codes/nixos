import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
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
    property string cpuDisplay: "--"
    property string gpuDisplay: "--"
    property string acCpuDisplay: "--"
    property string acGpuDisplay: "--"
    property string batCpuDisplay: "--"
    property string batGpuDisplay: "--"
    property int cpuBoost: -1
    property int gpuBoost: -1
    property int acCpuBoost: -1
    property int acGpuBoost: -1
    property int batCpuBoost: -1
    property int batGpuBoost: -1
    property int gpuBoostMax: 2
    property string actionLabel: ""
    property string errorText: ""
    property string statusOutput: ""
    property int customCpuBoost: clampBoost(parseInt(pluginData.customCpuBoost ?? 2), 0, 3)
    property int customGpuBoost: clampBoost(parseInt(pluginData.customGpuBoost ?? 2), 0, gpuBoostMax)

    function batteryTimeText() {
        if (!BatteryService.batteryAvailable)
            return "Power profile management available"
        var time = BatteryService.formatTimeRemaining()
        if (time !== "")
            return BatteryService.isCharging ? "Time until full: " + time : "Time remaining: " + time
        return BatteryService.batteryStatus
    }

    function powerProfileText() {
        if (typeof PowerProfiles === "undefined")
            return "Unknown"
        return Theme.getPowerProfileLabel(PowerProfiles.profile)
    }

    function shortPowerProfileText() {
        var profile = root.powerProfileText()
        if (profile === "Power Saver")
            return "Save"
        if (profile === "Balanced")
            return "Bal"
        if (profile === "Performance")
            return "Perf"
        return profile.substring(0, 4)
    }

    function clampBoost(value, minValue, maxValue) {
        if (isNaN(value))
            return maxValue
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function intOrUnknown(value) {
        return value === null || value === undefined || isNaN(value) ? -1 : value
    }

    function boostOptions(kind) {
        return kind === "gpu" ? [0, 1, 2] : [0, 1, 2, 3]
    }

    function customArgs() {
        var raw = (pluginData.customPowerArgs || "").trim()
        if (raw.length > 0)
            return raw.split(/\s+/)
        return ["4", String(customCpuBoost), String(customGpuBoost)]
    }

    function isActiveProfile(profile) {
        if (typeof PowerProfiles === "undefined")
            return false
        return PowerProfiles.profile === profile
    }

    function setCustomBoost(kind, value) {
        value = clampBoost(value, 0, kind === "gpu" ? gpuBoostMax : 3)
        if (kind === "cpu")
            customCpuBoost = value
        else
            customGpuBoost = value
        if (pluginService)
            pluginService.savePluginData("razerEnergy", kind === "cpu" ? "customCpuBoost" : "customGpuBoost", value)
    }

    function refresh() {
        if (!statusProc.running) {
            statusOutput = ""
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

    function setProfile(profile) {
        if (typeof PowerProfiles === "undefined") {
            ToastService.showError("Power", "power-profiles-daemon not available")
            return
        }
        PowerProfiles.profile = profile
        if (PowerProfiles.profile !== profile)
            ToastService.showError("Power", "Failed to set power profile")
    }

    Process {
        id: statusProc
        command: ["razer-energy", "json"]

        stdout: SplitParser {
            onRead: line => root.statusOutput = line.trim()
        }

        stderr: SplitParser {
            onRead: line => root.errorText = line.trim()
        }

        onExited: exitCode => {
            if (exitCode === 0 && root.statusOutput.length > 0) {
                try {
                    var data = JSON.parse(root.statusOutput)
                    root.ok = data.ok === true
                    root.statusText = data.text || "!"
                    root.statusAlt = data.alt || "unknown"
                    root.powerSource = data.source || "ac"
                    root.acDisplay = data.ac ? data.ac.display : "--"
                    root.batDisplay = data.bat ? data.bat.display : "--"
                    root.cpuBoost = root.intOrUnknown(data.cpu)
                    root.gpuBoost = root.intOrUnknown(data.gpu)
                    root.cpuDisplay = data.cpuDisplay || "--"
                    root.gpuDisplay = data.gpuDisplay || "--"
                    root.acCpuBoost = data.ac ? root.intOrUnknown(data.ac.cpu) : -1
                    root.acGpuBoost = data.ac ? root.intOrUnknown(data.ac.gpu) : -1
                    root.batCpuBoost = data.bat ? root.intOrUnknown(data.bat.cpu) : -1
                    root.batGpuBoost = data.bat ? root.intOrUnknown(data.bat.gpu) : -1
                    root.acCpuDisplay = data.ac ? data.ac.cpuDisplay : "--"
                    root.acGpuDisplay = data.ac ? data.ac.gpuDisplay : "--"
                    root.batCpuDisplay = data.bat ? data.bat.cpuDisplay : "--"
                    root.batGpuDisplay = data.bat ? data.bat.gpuDisplay : "--"
                    root.errorText = data.error || ""
                } catch (e) {
                    root.ok = false
                    root.statusText = "!"
                    root.statusAlt = "parse-error"
                    root.errorText = "Failed to parse razer-energy output: " + e
                    console.warn("RazerEnergy parse error:", e, "output:", root.statusOutput)
                }
            } else {
                root.ok = false
                root.statusText = "!"
                root.statusAlt = "error"
                if (root.errorText === "")
                    root.errorText = "razer-energy exited with code " + exitCode
            }
            root.statusOutput = ""
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
                name: Theme.getBatteryIcon(BatteryService.batteryLevel, BatteryService.isCharging, BatteryService.batteryAvailable)
                color: root.ok ? Theme.primary : Theme.error
                size: Theme.iconSize - 4
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: BatteryService.batteryAvailable ? (BatteryService.batteryLevel + "%") : root.statusText
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.powerProfileText()
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.statusText
                color: root.ok ? Theme.primary : Theme.error
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
                text: BatteryService.batteryAvailable ? String(BatteryService.batteryLevel) : root.statusText.substring(0, 3)
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.shortPowerProfileText()
                color: root.ok ? Theme.surfaceText : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.statusText.substring(0, 3)
                color: root.ok ? Theme.primary : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 680

    popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "Razer Energy"
            detailsText: BatteryService.batteryAvailable ? (BatteryService.batteryLevel + "% " + BatteryService.batteryStatus) : (root.powerSource === "ac" ? "On AC power" : "On battery")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: BatteryService.batteryAvailable

                        StyledRect {
                            width: (parent.width - Theme.spacingS) / 2
                            height: 64
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "Health"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                    font.weight: Font.Medium
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: BatteryService.batteryHealth
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: BatteryService.batteryHealth !== "N/A" && parseInt(BatteryService.batteryHealth) < 80 ? Theme.error : Theme.surfaceText
                                    font.weight: Font.Bold
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        StyledRect {
                            width: (parent.width - Theme.spacingS) / 2
                            height: 64
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "Capacity"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                    font.weight: Font.Medium
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: BatteryService.batteryCapacity > 0 ? BatteryService.batteryCapacity.toFixed(1) + " Wh" : "Unknown"
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: Theme.surfaceText
                                    font.weight: Font.Bold
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: BatteryService.batteryAvailable
                        text: root.batteryTimeText()
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Item {
                        width: parent.width
                        height: profileButtonGroup.height * profileButtonGroup.scale

                        DankButtonGroup {
                            id: profileButtonGroup

                            property var profileModel: (typeof PowerProfiles !== "undefined") ? [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : []) : [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                            property int currentProfileIndex: {
                                if (typeof PowerProfiles === "undefined")
                                    return 1
                                return profileModel.findIndex(profile => root.isActiveProfile(profile))
                            }

                            scale: Math.min(1, parent.width / implicitWidth)
                            transformOrigin: Item.Center
                            anchors.horizontalCenter: parent.horizontalCenter
                            model: profileModel.map(profile => Theme.getPowerProfileLabel(profile))
                            currentIndex: currentProfileIndex
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return
                                root.setProfile(profileModel[index])
                            }
                        }
                    }
                }

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
                            text: "Power profile: " + root.powerProfileText()
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            text: "CPU: " + root.cpuDisplay + " (" + root.cpuBoost + ")   GPU: " + root.gpuDisplay + " (" + root.gpuBoost + ")"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            width: parent.width
                            text: "AC: " + root.acDisplay + "  CPU " + root.acCpuDisplay + " (" + root.acCpuBoost + ")  GPU " + root.acGpuDisplay + " (" + root.acGpuBoost + ")"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            width: parent.width
                            text: "Battery: " + root.batDisplay + "  CPU " + root.batCpuDisplay + " (" + root.batCpuBoost + ")  GPU " + root.batGpuDisplay + " (" + root.batGpuBoost + ")"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
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
                                    model: root.boostOptions(boostRow.modelData.kind)

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
