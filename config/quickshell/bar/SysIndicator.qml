import QtQuick
import QtQuick.Layouts

import "../services"

Item {
    id: root
    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    property string label: ""
    property string icon: ""
    property real value: 0
    property string suffix: "%"
    property color barColor: Colors.success

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: 1

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            font.family: Colors.iconFont
            font.pixelSize: 13
            color: root.barColor

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            font.family: Colors.fontFamily
            font.pixelSize: 7
            font.bold: true
            color: Colors.overlay1
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 24
            height: 3
            radius: 1.5
            color: Colors.withAlpha(Colors.surface0, 0.6)

            Rectangle {
                width: parent.width * Math.min(root.value / 100, 1)
                height: parent.height
                radius: 1.5
                color: root.barColor

                Behavior on width { NumberAnimation { duration: 300 } }
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Math.round(root.value) + root.suffix
            font.family: Colors.fontFamily
            font.pixelSize: 8
            color: Colors.subtext0
        }
    }
}
