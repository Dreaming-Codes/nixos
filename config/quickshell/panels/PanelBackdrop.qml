import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: root
    signal clicked()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
