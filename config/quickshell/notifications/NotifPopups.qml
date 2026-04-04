import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

import "../services"

PanelWindow {
    id: root

    property var notifManager: null

    anchors {
        top: true
        right: true
    }

    margins { top: 12; right: 12 }

    implicitWidth: 360
    implicitHeight: popupCol.implicitHeight

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    ColumnLayout {
        id: popupCol
        anchors {
            left: parent.left
            right: parent.right
        }
        spacing: 8

        Repeater {
            model: root.notifManager?.popupQueue ?? []

            delegate: Rectangle {
                id: popup
                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: popupContent.implicitHeight + 24
                radius: 12
                color: Colors.withAlpha(Colors.base, 0.95)
                border.width: 1
                border.color: Colors.withAlpha(Colors.surface2, 0.6)

                ColumnLayout {
                    id: popupContent
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: popup.modelData.appName || "Notification"
                            font.family: Colors.fontFamily
                            font.pixelSize: Colors.fontSizeSmall
                            font.bold: true
                            color: Colors.primary
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: ""
                            font.family: Colors.iconFont
                            font.pixelSize: 12
                            color: Colors.overlay1

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.notifManager)
                                        root.notifManager.dismiss(popup.modelData);
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: popup.modelData.summary || ""
                        font.family: Colors.fontFamily
                        font.pixelSize: Colors.fontSizeNormal
                        font.bold: true
                        color: Colors.text
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                    }

                    Text {
                        Layout.fillWidth: true
                        text: popup.modelData.body || ""
                        font.family: Colors.fontFamily
                        font.pixelSize: Colors.fontSizeSmall
                        color: Colors.subtext1
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        visible: text !== ""
                        textFormat: Text.PlainText
                    }

                    // Action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: popup.modelData.actions.length > 0

                        Repeater {
                            model: popup.modelData.actions
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: actionText.implicitWidth + 16
                                implicitHeight: 24
                                radius: 6
                                color: Colors.withAlpha(Colors.surface1, 0.5)

                                Text {
                                    id: actionText
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    font.family: Colors.fontFamily
                                    font.pixelSize: Colors.fontSizeSmall
                                    color: Colors.text
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        modelData.invoke();
                                        if (root.notifManager)
                                            root.notifManager.dismiss(popup.modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
