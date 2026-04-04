import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

import "../services"

PanelWindow {
    id: root

    property var notifManager: null
    signal dismissed()

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
    }

    margins { top: 8; left: 64 }

    implicitWidth: 320
    implicitHeight: Math.min(contentCol.implicitHeight + 20, 500)

    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Colors.withAlpha(Colors.base, 0.95)
        border.width: 1
        border.color: Colors.withAlpha(Colors.surface2, 0.6)

        ColumnLayout {
            id: contentCol
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Notifications"
                    font.family: Colors.fontFamily
                    font.pixelSize: Colors.fontSizeLarge
                    font.bold: true
                    color: Colors.text
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.notifManager?.dnd ? "" : ""
                    font.family: Colors.iconFont
                    font.pixelSize: 14
                    color: root.notifManager?.dnd ? Colors.danger : Colors.subtext1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.notifManager)
                                root.notifManager.dnd = !root.notifManager.dnd;
                        }
                    }
                }

                Text {
                    text: ""
                    font.family: Colors.iconFont
                    font.pixelSize: 14
                    color: Colors.subtext1
                    visible: (root.notifManager?.notifications.length ?? 0) > 0

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.notifManager) root.notifManager.dismissAll();
                        }
                    }
                }

                Text {
                    text: ""
                    font.family: Colors.iconFont
                    font.pixelSize: 14
                    color: Colors.subtext1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colors.withAlpha(Colors.surface2, 0.4)
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 50
                Layout.maximumHeight: 400
                contentHeight: notifCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: notifCol
                    width: parent.width
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "No notifications"
                        font.family: Colors.fontFamily
                        font.pixelSize: Colors.fontSizeNormal
                        color: Colors.overlay1
                        horizontalAlignment: Text.AlignHCenter
                        visible: (root.notifManager?.notifications.length ?? 0) === 0
                    }

                    Repeater {
                        model: root.notifManager?.notifications ?? []

                        delegate: Rectangle {
                            id: notifItem
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: itemCol.implicitHeight + 16
                            radius: 8
                            color: Colors.withAlpha(Colors.surface0, 0.5)

                            ColumnLayout {
                                id: itemCol
                                anchors {
                                    fill: parent
                                    margins: 8
                                }
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: notifItem.modelData.appName || "App"
                                        font.family: Colors.fontFamily
                                        font.pixelSize: 9
                                        color: Colors.primary
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: ""
                                        font.family: Colors.iconFont
                                        font.pixelSize: 10
                                        color: Colors.overlay1

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.notifManager)
                                                    root.notifManager.dismiss(notifItem.modelData);
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: notifItem.modelData.summary || ""
                                    font.family: Colors.fontFamily
                                    font.pixelSize: Colors.fontSizeSmall
                                    font.bold: true
                                    color: Colors.text
                                    wrapMode: Text.WordWrap
                                    visible: text !== ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: notifItem.modelData.body || ""
                                    font.family: Colors.fontFamily
                                    font.pixelSize: 9
                                    color: Colors.subtext0
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
