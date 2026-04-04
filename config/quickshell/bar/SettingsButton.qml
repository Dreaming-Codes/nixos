import QtQuick
import QtQuick.Layouts

import "../services"

MouseArea {
    id: root
    Layout.fillWidth: true
    implicitHeight: 28

    property string icon: ""
    property string label: ""
    signal activated()

    hoverEnabled: true
    onClicked: activated()

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.containsMouse ? Colors.withAlpha(Colors.surface1, 0.5) : "transparent"

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 8
                rightMargin: 8
            }
            spacing: 8

            Text {
                text: root.icon
                font.family: Colors.iconFont
                font.pixelSize: 14
                color: Colors.subtext1
            }

            Text {
                Layout.fillWidth: true
                text: root.label
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeNormal
                color: Colors.text
            }
        }
    }
}
