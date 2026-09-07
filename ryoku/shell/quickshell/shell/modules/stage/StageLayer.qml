pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import shell.services
import "Singletons"

// One stage layer: an alpha PNG drawn back-to-front inside the desktop surface
// (docs/stage.md). Edge softness, drop shadow and its angle are the global Look
// every layer inherits (Config); the layer's own `depth` (near..far) scales the
// cursor drift by the shared motion Amount, and the idle animation and music
// reaction are global too. Depth is this same renderer with motionEnabled off:
// no drift, no idle, no overscan, so the still cut sits pixel-locked over the
// wallpaper's own subject and there is never a second, ghosted subject.
Item {
    id: root

    property int layerIndex: 1
    property string wallPath: ""
    property string url: ""
    property string fit: "Cover"
    property real mouseNX: 0
    property real mouseNY: 0
    property real energy: 0
    // Off for the still Depth effect; on for the drifting Parallax stack.
    property bool motionEnabled: true

    readonly property int i: root.layerIndex - 1
    readonly property bool layerShown: root.url !== ""
        && StageBackend.isActiveFor(root.wallPath)
        && StageBackend.layerEnabled(root.wallPath, root.i)

    anchors.fill: parent
    visible: root.layerShown

    // near (depth 0) drifts most, far (depth 1) least; the whole stack scales by
    // the shared Amount so Subtle/Normal/Strong tune every layer at once.
    readonly property real _depth: StageBackend.layerDepth(root.wallPath, root.i)
    readonly property real _near: 0.35 + (1 - root._depth) * 0.9
    readonly property real _baseMax: root.width * 0.04
    readonly property real _edge: Config.edge
    readonly property real _shStrength: Config.shadow
    readonly property real _shAngle: Config.shadowAngle * Math.PI / 180

    function _fillMode(im) {
        switch (root.fit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= root.width && im.sourceSize.height <= root.height) ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    // Pointer drift: Follow mouse gates it, Sensitivity scales the pointer's
    // pull, Range scales how far a layer may travel (the Parallax tab's knobs).
    readonly property real _pointerGain: (root.motionEnabled && Config.followMouse)
        ? Config.sensitivity * Config.range * Config.amountFactor * root._near : 0
    function _driftX() { return root.mouseNX * root._baseMax * root._pointerGain; }
    function _driftY() { return root.mouseNY * root._baseMax * root._pointerGain; }
    // Music lifts near layers more than far ones, so the stack pulses with depth.
    function _musicY() {
        if (!root.motionEnabled || !Config.music) return 0;
        return -root.energy * 34 * Config.musicLevel * Config.amountFactor * root._near;
    }

    // Idle life: Float bobs vertically, Breathe scales gently. Both are gated to
    // Parallax (motionEnabled) and scaled by Amount; Depth stays perfectly still.
    readonly property bool _idleOn: root.motionEnabled && Config.idle !== "none"
    property real animT: 0
    Timer {
        id: animTick
        interval: 50
        repeat: true
        running: root.layerShown && root._idleOn
        onTriggered: root.animT += 50
    }
    // Speed scales the clock; Sway rocks the layer a degree or two around its
    // centre, deeper layers less, so the stack leans rather than spins.
    readonly property real _phase: root.animT / 1000 * Config.speed
    readonly property real _idleY: (root._idleOn && Config.idle === "float")
        ? Math.sin(root._phase * 1.1) * 6 * Config.amountFactor : 0
    readonly property real _idleScale: (root._idleOn && Config.idle === "breathe")
        ? 1 + 0.02 * Config.amountFactor * (0.5 + 0.5 * Math.sin(root._phase * 0.9)) : 1
    readonly property real _idleRot: (root._idleOn && Config.idle === "sway")
        ? Math.sin(root._phase * 0.7) * 1.6 * Config.amountFactor * root._near : 0

    // Cutting progress rides the subject itself, not a panel (docs/stage.md):
    // the subject layer (index 1) dims and a ring with the percent floats over it.
    readonly property bool _busyHere: root.layerIndex === 1 && StageBackend.busy && root.url !== ""

    Image {
        id: img
        anchors.fill: parent
        source: root.url
        cache: false
        asynchronous: true
        fillMode: root._fillMode(img)
        sourceSize.width: root.width
        sourceSize.height: root.height
        // No overscan: a cut-out is transparent at its edges, so drift needs
        // no headroom, and the subject keeps its size in Depth and Parallax
        // alike (a scale jump reads as the picture zooming when Parallax turns
        // on). Breathe is the only thing that scales it.
        scale: root._idleScale
        rotation: root._idleRot
        opacity: (status === Image.Ready ? 1 : 0) * (root._busyHere ? 0.45 : 1)
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        transform: Translate {
            x: root._driftX()
            y: root._driftY() + root._musicY() + root._idleY
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }

        // Edge feather and the angled cast shadow set the cut-out into the scene;
        // the FBO stays off when both are zero.
        layer.enabled: root._edge > 0.001 || root._shStrength > 0.001
        layer.effect: MultiEffect {
            blurEnabled: root._edge > 0.001
            blurMax: 16
            blur: root._edge
            shadowEnabled: root._shStrength > 0.001
            shadowColor: Qt.rgba(0, 0, 0, 0.72 * root._shStrength)
            shadowBlur: 0.55 + 0.45 * root._shStrength
            shadowHorizontalOffset: Math.round(Math.cos(root._shAngle) * 20 * root._shStrength)
            shadowVerticalOffset: Math.round(Math.sin(root._shAngle) * 20 * root._shStrength)
        }
    }

    // Progress ring centred on the subject; tap to cancel the cut.
    Item {
        anchors.centerIn: parent
        width: 96
        height: 96
        visible: root._busyHere
        Canvas {
            id: ring
            anchors.fill: parent
            property int pct: StageBackend.percent
            onPctChanged: ring.requestPaint()
            onVisibleChanged: ring.requestPaint()
            Component.onCompleted: ring.requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                const w = width, cx = w / 2, cy = height / 2, r = w / 2 - 6;
                ctx.reset();
                ctx.lineWidth = 6;
                ctx.lineCap = "round";
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                ctx.stroke();
                ctx.strokeStyle = Theme.primary;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0, Math.min(1, ring.pct / 100)));
                ctx.stroke();
            }
        }
        Text {
            anchors.centerIn: parent
            text: StageBackend.percent + "%"
            color: "white"
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
            font.weight: Font.DemiBold
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: StageBackend.cancel()
        }
    }
}
