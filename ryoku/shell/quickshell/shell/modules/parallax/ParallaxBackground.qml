pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Singletons"

// The parallax backdrop surface at WlrLayer.Background: recoloured
// background + drift. The layer bands render inside the desktop surface
// so the scene order interleaves them with the widgets.
Item {
    id: root

    property var screen
    property string wallpaperUrl: ""
    property string wallpaperPath: ""
    property string wallpaperFit: "Cover"
    property string videoUrl: ""
    property bool wallpaperLive: false

    readonly property bool owns: Config.enabled && Config.wallActiveForPath(root.wallpaperPath)
        && root.videoUrl === "" && !root.wallpaperLive

    property real cursorNX: 0
    property real cursorNY: 0

    readonly property bool shown: root.owns && root.wallpaperUrl !== ""

    property real _baseMax: Math.min(root.width * 0.04 * Config.mouseRange, root.width * 0.04)
    function baseOffsetX() {
        if (!Config.mouseEnabled) return 0;
        return root.cursorNX * root._baseMax * Config.wallpaperParallax * Config.mouseSensitivity;
    }
    function baseOffsetY() {
        if (!Config.mouseEnabled) return 0;
        return root.cursorNY * root._baseMax * Config.wallpaperParallax * Config.mouseSensitivity;
    }

    function fillModeFor(im) {
        switch (root.wallpaperFit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= win.width && im.sourceSize.height <= win.height)
                ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    PanelWindow {
        id: win
        screen: root.screen
        visible: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "ryoku-parallax"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: emptyRegion
        Region { id: emptyRegion }

        anchors { top: true; left: true; right: true; bottom: true }

        Item {
            id: stack
            anchors.fill: parent
            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Image {
                id: base
                anchors.fill: parent
                source: root.wallpaperUrl
                cache: false
                asynchronous: true
                fillMode: root.fillModeFor(base)
                sourceSize.width: width
                sourceSize.height: height
                scale: 1.1
                z: -1
                transform: Translate {
                    x: root.baseOffsetX()
                    y: root.baseOffsetY()
                    Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
                    Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
                }
            }
            Image {
                id: bg
                anchors.fill: parent
                source: Config.backgroundUrlForPath(root.wallpaperPath)
                cache: false
                asynchronous: true
                fillMode: root.fillModeFor(bg)
                sourceSize.width: width
                sourceSize.height: height
                scale: 1.1
                z: -1
                visible: status === Image.Ready && Config.backgroundUrlForPath(root.wallpaperPath) !== ""
                transform: Translate {
                    x: root.baseOffsetX()
                    y: root.baseOffsetY()
                    Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
                    Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
                }
            }

        }
    }

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
                const mx = (cx - m.x) / m.width * 2 - 1;
                const my = (cy - m.y) / m.height * 2 - 1;
                const nx = Math.max(-1, Math.min(1, mx));
                const ny = Math.max(-1, Math.min(1, my));
                // Smoothed so the irregular poll timing never jitters.
                root.cursorNX = root.cursorNX + (nx - root.cursorNX) * 0.55;
                root.cursorNY = root.cursorNY + (ny - root.cursorNY) * 0.55;
                Config.setCursor(root.screen.name, root.cursorNX, root.cursorNY);
            }
        }
    }
}
