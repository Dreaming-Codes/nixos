import QtQuick

import "../services"

Item {
    id: root
    implicitWidth: 28
    implicitHeight: 24

    property string icon: ""
    property bool active: false
    property color activeColor: Colors.primary
    signal clicked()

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Colors.iconFont
        font.pixelSize: 14
        color: root.active ? root.activeColor : Colors.subtext1
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
