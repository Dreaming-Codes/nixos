import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io
import QtQuick

import "../services"

Scope {
    id: root
    property bool locked: false

    WlSessionLock {
        id: lock
        locked: root.locked

        WlSessionLockSurface {
            id: surface

            color: Colors.crust

            PamContext {
                id: pam
                config: "login"

                property string statusMessage: ""

                onResponseRequiredChanged: {
                    if (responseRequired) {
                        pam.respond(passwordInput.text);
                    }
                }

                onCompleted: result => {
                    if (result === PamResult.Success) {
                        pam.statusMessage = "";
                        unlockAnim.start();
                    } else {
                        pam.statusMessage = "Authentication failed";
                        passwordInput.text = "";
                        shakeAnim.start();
                    }
                }
            }

            // Unlock animation
            SequentialAnimation {
                id: unlockAnim
                NumberAnimation {
                    target: lockContent
                    property: "opacity"
                    to: 0
                    duration: 300
                    easing.type: Easing.OutCubic
                }
                ScriptAction {
                    script: root.locked = false
                }
            }

            // Error shake animation
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: inputContainer; property: "x"; to: inputContainer.baseX - 10; duration: 50 }
                NumberAnimation { target: inputContainer; property: "x"; to: inputContainer.baseX + 10; duration: 50 }
                NumberAnimation { target: inputContainer; property: "x"; to: inputContainer.baseX - 5; duration: 50 }
                NumberAnimation { target: inputContainer; property: "x"; to: inputContainer.baseX; duration: 50 }
            }

            Item {
                id: lockContent
                anchors.fill: parent

                // Background gradient
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Colors.withAlpha(Colors.crust, 0.95) }
                        GradientStop { position: 0.5; color: Colors.withAlpha(Colors.base, 0.9) }
                        GradientStop { position: 1.0; color: Colors.withAlpha(Colors.crust, 0.95) }
                    }
                }

                // Clock
                Text {
                    id: clockText
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.2
                    text: Qt.formatTime(new Date(), "hh:mm")
                    font.family: Colors.fontFamily
                    font.pixelSize: 96
                    font.bold: true
                    color: Colors.withAlpha(Colors.text, 0.7)

                    Timer {
                        interval: 1000
                        running: root.locked
                        repeat: true
                        onTriggered: clockText.text = Qt.formatTime(new Date(), "hh:mm")
                    }
                }

                // Date
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: clockText.bottom
                    anchors.topMargin: 8
                    text: Qt.formatDate(new Date(), "dddd, MMMM d")
                    font.family: Colors.fontFamily
                    font.pixelSize: 22
                    color: Colors.withAlpha(Colors.text, 0.6)

                    Timer {
                        interval: 60000
                        running: root.locked
                        repeat: true
                    }
                }

                // Profile image (circular clip via layer + rounded Rectangle mask)
                Item {
                    id: profileContainer
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.42
                    width: 100
                    height: 100

                    Rectangle {
                        id: profileMask
                        anchors.fill: parent
                        radius: 50
                        color: Colors.surface0
                        clip: true

                        Image {
                            id: profileImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: "file://" + (Quickshell.env("HOME") ?? "") + "/.config/hypr/dreamingcodes.jpeg"
                        }

                        // Fallback icon when image not available
                        Text {
                            anchors.centerIn: parent
                            visible: profileImage.status !== Image.Ready
                            text: ""
                            font.family: Colors.iconFont
                            font.pixelSize: 40
                            color: Colors.subtext1
                        }
                    }
                }

                // Username
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.42 + 115
                    text: Quickshell.env("USER") ?? "user"
                    font.family: Colors.fontFamily
                    font.pixelSize: 16
                    color: Colors.withAlpha(Colors.text, 0.7)
                }

                // Password input area
                Item {
                    id: inputContainer
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.42 + 150
                    width: 280
                    height: 50

                    property real baseX: (parent.width - width) / 2

                    Rectangle {
                        anchors.fill: parent
                        radius: 25
                        color: Colors.withAlpha(Colors.text, 0.1)
                        border.width: 1
                        border.color: Colors.withAlpha(Colors.text, 0.15)

                        TextInput {
                            id: passwordInput
                            anchors {
                                fill: parent
                                leftMargin: 20
                                rightMargin: 20
                            }
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            font.family: Colors.fontFamily
                            font.pixelSize: 14
                            color: Colors.text
                            clip: true
                            focus: root.locked

                            onAccepted: {
                                if (text.length > 0 && !pam.active) {
                                    pam.statusMessage = "Authenticating...";
                                    pam.user = Quickshell.env("USER") ?? "dreamingcodes";
                                    pam.start();
                                }
                            }

                            // Placeholder
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: pam.active ? "Authenticating..." : "Enter Password"
                                font.family: Colors.fontFamily
                                font.pixelSize: 14
                                color: Colors.withAlpha(Colors.text, 0.4)
                                visible: passwordInput.text.length === 0
                            }
                        }
                    }
                }

                // Status message
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: inputContainer.y + 60
                    text: pam.statusMessage
                    font.family: Colors.fontFamily
                    font.pixelSize: 12
                    color: Colors.danger
                    visible: text !== ""
                }

                // Current song (MPRIS)
                Text {
                    id: songText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    font.family: Colors.fontFamily
                    font.pixelSize: 14
                    color: Colors.withAlpha(Colors.text, 0.5)

                    property string songInfo: ""

                    Process {
                        id: songProc
                        command: ["playerctl", "metadata", "--format", "{{title}}      {{artist}}"]
                        stdout: SplitParser {
                            onRead: line => songText.songInfo = line.trim()
                        }
                    }

                    Timer {
                        interval: 2000
                        running: root.locked
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: songProc.running = true
                    }

                    text: songInfo
                }
            }
        }
    }
}
