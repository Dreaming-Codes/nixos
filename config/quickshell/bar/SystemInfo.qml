import QtQuick
import QtQuick.Layouts

import "../services"

ColumnLayout {
    id: root
    spacing: 4

    SysIndicator {
        Layout.fillWidth: true
        icon: "\uf2db"
        label: "CPU"
        value: SysInfo.cpuPercent
        suffix: "%"
        barColor: SysInfo.colorForValue(SysInfo.cpuPercent, SysInfo.cpuWarn, SysInfo.cpuAlert)
    }

    SysIndicator {
        Layout.fillWidth: true
        icon: "\uf0c9"
        label: "MEM"
        value: SysInfo.memPercent
        suffix: "%"
        barColor: SysInfo.colorForValue(SysInfo.memPercent, SysInfo.memWarn, SysInfo.memAlert)
    }

    SysIndicator {
        Layout.fillWidth: true
        icon: "\uf2c9"
        label: "TMP"
        value: SysInfo.temperature
        suffix: "\u00b0"
        barColor: SysInfo.colorForValue(SysInfo.temperature, SysInfo.tempWarn, SysInfo.tempAlert)
    }
}
