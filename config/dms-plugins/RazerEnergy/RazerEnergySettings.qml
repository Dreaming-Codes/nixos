import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "razerEnergy"

    StyledText {
        width: parent.width
        text: "Razer Energy"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Controls razer-cli power modes from the bar. Leave custom args empty to use the CPU/GPU boost selectors in the popout."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "customPowerArgs"
        label: "Override Custom Args"
        description: "Optional raw args after the power source, for example: 4 3 2."
        placeholder: "4 3 2"
        defaultValue: ""
    }
}
