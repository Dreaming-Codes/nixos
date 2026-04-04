import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

import "../services"

ColumnLayout {
    id: root
    spacing: 4

    property var barWindow: null

    visible: trayRepeater.count > 0

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Colors.withAlpha(Colors.surface2, 0.4)
        visible: trayRepeater.count > 0
    }

    Repeater {
        id: trayRepeater
        model: SystemTray.items

        delegate: Item {
            id: trayDelegate
            required property SystemTrayItem modelData

            Layout.fillWidth: true
            Layout.preferredHeight: 24

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: trayDelegate.modelData.icon
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(16, 16)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.RightButton || trayDelegate.modelData.onlyMenu) {
                        if (trayDelegate.modelData.hasMenu && root.barWindow) {
                            const globalPos = trayDelegate.mapToItem(null, event.x, event.y);
                            trayDelegate.modelData.display(root.barWindow, globalPos.x, globalPos.y);
                        }
                    } else {
                        trayDelegate.modelData.activate();
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Colors.withAlpha(Colors.surface2, 0.4)
        visible: trayRepeater.count > 0
    }
}
