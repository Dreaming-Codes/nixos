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
        text: "Controls razer-cli power modes from the bar. Custom args are passed after the power source, for example: 4 3 2."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "customPowerArgs"
        label: "Custom Power Args"
        description: "Arguments used by the Custom AC and Custom Battery buttons."
        placeholder: "4 3 2"
        defaultValue: "4 3 2"
    }
}
