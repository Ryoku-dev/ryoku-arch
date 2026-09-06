pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
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
    function offsetX() { return root.cursorNX * root._max * Config.amountFactor * 0.25; }
    function offsetY() { return root.cursorNY * root._max * Config.amountFactor * 0.25; }

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
        scale: 1.1
        opacity: (root.shown && status === Image.Ready) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        transform: Translate {
            x: root.offsetX()
            y: root.offsetY()
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }
    }

    // Parallax needs the global cursor, which Quickshell does not surface without
    // a poll; the value is smoothed and shared per-monitor so the layers above
    // drift in lockstep with this backdrop.
    Timer {
        id: cursorTick
        interval: 40
        repeat: true
        running: root.owns
        onTriggered: {
            const m = root.screen;
            if (!m || m.width <= 0) return;
            cursorProc.running = false;
            cursorProc.running = true;
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = root.screen;
                if (!m || m.width <= 0) return;
                const parts = ("" + this.text).trim().split(",");
                if (parts.length !== 2) return;
                const cx = parseFloat(parts[0]);
                const cy = parseFloat(parts[1]);
                if (isNaN(cx) || isNaN(cy)) return;
                const nx = Math.max(-1, Math.min(1, (cx - m.x) / m.width * 2 - 1));
                const ny = Math.max(-1, Math.min(1, (cy - m.y) / m.height * 2 - 1));
                root.cursorNX = root.cursorNX + (nx - root.cursorNX) * 0.55;
                root.cursorNY = root.cursorNY + (ny - root.cursorNY) * 0.55;
                StageBackend.setCursor(m.name, root.cursorNX, root.cursorNY);
            }
        }
    }
}
