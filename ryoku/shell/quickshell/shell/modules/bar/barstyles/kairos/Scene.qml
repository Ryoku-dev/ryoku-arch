// Kairos: one dynamic island on the top edge, carrying the clock. The window
// holds the open island whole, masks input to the island, and reserves only the
// resting band, so tiled windows clear the pill without the surface ever
// resizing during the morph. While the now-playing panel is pinned open the
// window covers the screen and a click anywhere off the panel dismisses it.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import "components" as C

PanelWindow {
    id: win

    // The screen, set by Frame's per-monitor Loader.
    property var modelData: null
    screen: modelData

    // This screen's shell state: while Super+Space has the launcher open, the
    // launcher's own pill stands in for this island, and this one drops back to
    // its resting size underneath it.
    readonly property var state: win.modelData ? ShellState.forScreen(win.modelData) : null

    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    // Reserve the resting band so tiled windows clear the island. The open
    // island overhangs it, which is the point of a floating one.
    exclusiveZone: island.band
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-bar"

    anchors { top: true; left: true; right: true }
    // Rests as tall as the open island plus its shadow, never taller: it holds
    // every frame of the morph without a single surface resize.
    implicitHeight: island.reach

    // Only the island takes input; the strip around it passes clicks through. The
    // full panel closes itself when the pointer leaves, so no dismiss layer is
    // needed.
    mask: Region {
        x: island.x
        y: island.y
        width: island.width
        height: island.height
    }

    C.Island {
        id: island
        y: island.topGap
        // The clock's resting centre lands on the screen's centre line, so the
        // clock rests centred and expands there; the music grows leftward from
        // just beside it.
        x: Math.round(win.width / 2 - island.clockRestCentre)
        suspended: win.state ? win.state.launcherOpen : false
    }
}
