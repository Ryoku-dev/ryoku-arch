pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import shell.services
import "../stage/Singletons" as StageCfg
import "Singletons"

// The Edit shell session's host (docs/stage.md): one layer-shell overlay per
// monitor, shown only while the shell session is on this screen. Its `visible`
// flips true through a 150 ms timer after the mode changes, so it maps ABOVE the
// bar and dock, which re-map to the Overlay layer at the same moment. It carries
// the canvas (the surface and layer outlines over the lifted desktop), the
// ribbon docked at the top, and an overlay layer the ribbon's drop-downs land in.
Scope {
    id: root

    // Touch the Layout singleton at boot so its snapshot connection is live
    // before the user ever enters the session (it captures on the mode change).
    Component.onCompleted: void Layout.surfaces

    Variants {
        model: ShellState.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property string monitorName: win.modelData ? win.modelData.name : ""
            readonly property real uiScale: Tokens.uiScaleFor(win.monitorName)
            readonly property bool shellHere: StageCfg.StageSession.shell
                && StageCfg.StageSession.monitor === win.monitorName

            screen: win.modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "ryoku-shell-layout"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            anchors { top: true; bottom: true; left: true; right: true }

            visible: false
            // The 150 ms map delay lets the bar and dock step to Overlay first,
            // so this surface maps above them rather than under.
            onShellHereChanged: {
                if (win.shellHere)
                    mapTimer.restart();
                else
                    win.visible = false;
            }
            Timer {
                id: mapTimer
                interval: 150
                onTriggered: win.visible = win.shellHere
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: e => { StageCfg.StageSession.escapeStep(); e.accepted = true; }
                onVisibleChanged: if (content.visible) content.forceActiveFocus()
                Component.onCompleted: if (content.visible) content.forceActiveFocus()

                ShellLayoutCanvas {
                    id: canvasItem
                    anchors.fill: parent
                    z: 0
                    monitor: win.monitorName
                    topReserve: ribbon.y + ribbon.height + 16
                }
                ShellRibbon {
                    id: ribbon
                    z: 10
                    monitor: win.monitorName
                    uiScale: win.uiScale
                    overlay: panelOverlay
                }
                // Drop-down panels reparent here so they draw over the canvas and
                // clear the ribbon; empty space falls through to the canvas.
                Item {
                    id: panelOverlay
                    anchors.fill: parent
                    z: 20
                }
            }
        }
    }
}
