pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// The Parallax backdrop, drawn inside the desktop surface just above the base
// wallpaper (docs/stage.md): the inpainted background.png sized with the
// wallpaper's own fit and drifting with the cursor, so it covers the
// wallpaper's baked subject and can never misalign with ryogami's surface
// underneath. Only Parallax uses it; Depth has no backdrop. This item also owns
// the per-monitor cursor poll and shares the smoothed value so every StageLayer
// on the screen drifts in lockstep.
Item {
    id: root

    property var screen
    property string wallpaperPath: ""
    property string wallpaperFit: "Cover"

    anchors.fill: parent

    readonly property bool owns: StageBackend.isParallaxFor(root.wallpaperPath)
    readonly property string url: StageBackend.backgroundUrlFor(root.wallpaperPath)
    readonly property bool shown: root.owns && root.url !== ""

    property real cursorNX: 0
    property real cursorNY: 0
    // The backdrop is the farthest plane, so it drifts the least; Amount scales it.
    readonly property real _max: root.width * 0.04
    // Backdrop drift scales the farthest plane on its own; Follow mouse and
    // Sensitivity gate and scale the pointer's pull like every layer.
    readonly property real _gain: Config.followMouse
        ? Config.amountFactor * Config.sensitivity * Config.backdrop * 0.25 : 0
    function offsetX() { return root.cursorNX * root._max * root._gain; }
    function offsetY() { return root.cursorNY * root._max * root._gain; }

    function fillModeFor(im) {
        switch (root.wallpaperFit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= root.width && im.sourceSize.height <= root.height)
                ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    Image {
        id: bg
        anchors.fill: parent
        source: root.url
        cache: false
        asynchronous: true
        fillMode: root.fillModeFor(bg)
        sourceSize.width: root.width
        sourceSize.height: root.height
        // Never scaled: there are no pixels past the wallpaper's edge, so any
        // overscan is the whole picture zooming when Parallax turns on. The far
        // plane stays still by default; Backdrop drift moves it at the cost of
        // a sliver of the base wallpaper at the trailing edge.
        opacity: (root.shown && status === Image.Ready) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        transform: Translate {
            x: root.offsetX()
            y: root.offsetY()
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }
    }

    // The drift follows the pointer while it is over the desktop surface: an
    // event, not a poll, so nothing runs while the pointer is over a window.
    HoverHandler {
        enabled: root.owns
        acceptedButtons: Qt.NoButton
        onPointChanged: {
            const m = root.screen;
            if (!m || root.width <= 0 || root.height <= 0) return;
            const nx = Math.max(-1, Math.min(1, point.position.x / root.width * 2 - 1));
            const ny = Math.max(-1, Math.min(1, point.position.y / root.height * 2 - 1));
            root.cursorNX = root.cursorNX + (nx - root.cursorNX) * 0.55;
            root.cursorNY = root.cursorNY + (ny - root.cursorNY) * 0.55;
            StageBackend.setCursor(m.name, root.cursorNX, root.cursorNY);
        }
    }
}
