import QtQuick

import "../services"

Item {
    id: root
    implicitHeight: 20
    implicitWidth: 100

    property real from: 0
    property real to: 1.0
    property real value: 0
    property real stepSize: 0.01
    signal moved()

    readonly property real ratio: (value - from) / (to - from)

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Colors.withAlpha(Colors.surface1, 0.6)

        Rectangle {
            width: track.width * root.ratio
            height: parent.height
            radius: 3
            color: Colors.primary

            Behavior on width { NumberAnimation { duration: 50 } }
        }
    }

    Rectangle {
        id: handle
        anchors.verticalCenter: parent.verticalCenter
        x: track.width * root.ratio - width / 2
        width: 14
        height: 14
        radius: 7
        color: Colors.text

        Behavior on x { enabled: !dragArea.pressed; NumberAnimation { duration: 50 } }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onPressed: event => updateValue(event.x)
        onPositionChanged: event => { if (pressed) updateValue(event.x); }

        function updateValue(mouseX) {
            const ratio = Math.max(0, Math.min(1, mouseX / track.width));
            root.value = root.from + ratio * (root.to - root.from);
            root.moved();
        }
    }
}
