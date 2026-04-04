import QtQuick

import "../services"

Item {
    id: root
    implicitWidth: 28
    implicitHeight: 28

    property var notifManager: null
    property bool notifCenterOpen: false
    signal toggleNotifCenter()
    signal toggleDnd()

    readonly property int notifCount: notifManager?.notifications.length ?? 0
    readonly property bool dnd: notifManager?.dnd ?? false

    Text {
        anchors.centerIn: parent
        text: root.dnd ? "\uf1f6" : "\uf0f3"
        font.family: Colors.iconFont
        font.pixelSize: 16
        color: root.notifCount > 0 ? Colors.primary : Colors.subtext1
    }

    Rectangle {
        visible: root.notifCount > 0 && !root.dnd
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 2
            rightMargin: 2
        }
        width: 12
        height: 12
        radius: 6
        color: Colors.danger

        Text {
            anchors.centerIn: parent
            text: root.notifCount > 9 ? "9+" : root.notifCount
            font.family: Colors.fontFamily
            font.pixelSize: 7
            font.bold: true
            color: Colors.crust
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.toggleDnd();
            else
                root.toggleNotifCenter();
        }
    }
}
