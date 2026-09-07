pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import "../stage/Singletons" as StageCfg

// The Edit shell layout session's host (docs/stage.md): one layer-shell overlay
// per monitor, shown while the layout session is on, carrying the canvas that
// draws the surface outlines and the island. Its own surface, separate from the
// widgets session (which lives inside the desktop), because moving the bar and
// dock is the opposite of hiding them.
Scope {
    id: root

    Variants {
        model: ShellState.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData
            visible: StageCfg.StageSession.layout
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "ryoku-shell-layout"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            anchors { top: true; bottom: true; left: true; right: true }

            ShellLayoutCanvas {
                anchors.fill: parent
                monitor: win.modelData ? win.modelData.name : ""
            }
        }
    }
}
