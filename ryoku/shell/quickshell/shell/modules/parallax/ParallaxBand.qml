pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Singletons"

// One parallax layer: an alpha PNG at its scene z with cursor drift,
// feather, lift, angled shadow and idle animation from the config.
Item {
    id: root

    property int layerIndex: 1
    property string wallPath: ""
    property string url: ""
    property string fit: "Cover"
    property real mouseNX: 0
    property real mouseNY: 0
    property real energy: 0

    readonly property int i: root.layerIndex - 1
    readonly property bool enabled: root.url !== "" && Config.enabled
        && Config.wallActiveForPath(root.wallPath)
        && Config.layerEnabled2(root.i)
        && Config.sceneIndexOfForPath(root.wallPath, "layer:" + root.layerIndex) >= 0

    anchors.fill: parent
    visible: root.enabled

    function _fillMode(im) {
        switch (root.fit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= root.width && im.sourceSize.height <= root.height) ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    function _maxShift() {
        return Math.min(Config.mouseMaxFor(root.i), root.width * 0.04 * Config.mouseRange);
    }
    function _cursorX() {
        if (!Config.mouseEnabled) return 0;
        return root.mouseNX * _maxShift() * 0.8
            * Config.parallaxFor(root.i) * (0.4 + Config.depthFor(root.i) * 1.2)
            * Config.mouseSensitivity;
    }
    function _cursorY() {
        if (!Config.mouseEnabled) return 0;
        return root.mouseNY * _maxShift() * 0.8
            * Config.parallaxFor(root.i) * (0.4 + Config.depthFor(root.i) * 1.2)
            * Config.mouseSensitivity;
    }

    function _audioY() {
        const a = Config.audioLevelFor(root.i);
        if (a <= 0) return 0;
        return -root.energy * a * 24;
    }

    readonly property real _lift: Config.liftFor(root.i)


    readonly property string _anim: Config.animTypeFor(root.i)
    readonly property real _amp: Config.animAmplitudeFor(root.i)
    readonly property real _spd: Config.animSpeedFor(root.i)
    readonly property int _dur: Math.max(500, Math.round(3200 / Math.max(0.1, root._spd)))

    property real animT: 0
    Timer {
        id: animTick
        interval: 50
        repeat: true
        running: root.enabled && root._anim !== "none"
        onTriggered: root.animT += 50
    }

    readonly property real _phase: root.animT * 2 * Math.PI * 4 / root._dur
    readonly property real _animX: (root._anim === "float" || root._anim === "wiggle" || root._anim === "rotate")
        ? Math.sin(root._phase) * root._amp : 0
    readonly property real _animY: (root._anim === "float" || root._anim === "wiggle")
        ? Math.cos(root._phase) * root._amp : 0
    readonly property real _animOpacity: root._anim === "pulse"
        ? 0.55 + 0.45 * Math.abs(Math.sin(root._phase / 2)) : 1
    readonly property real _animScale: root._anim === "scale"
        ? 1.1 + root._amp / 200 * Math.sin(root._phase / 2) : 1
    readonly property real _animRotate: root._anim === "rotate"
        ? Math.sin(root._phase) * root._amp * 0.35 : 0

    readonly property real _shAngle: Config.shadowAngleFor(root.i) * Math.PI / 180
    readonly property real _shStrength: Config.shadowFor(root.i)

    Image {
        id: img
        anchors.fill: parent
        source: root.url
        cache: false
        asynchronous: true
        fillMode: root._fillMode(img)
        sourceSize.width: root.width
        sourceSize.height: root.height
        scale: 1.1 * root._animScale * (1 + root._lift * 0.06)
        rotation: root._animRotate
        opacity: (status === Image.Ready ? Config.opacityFor(root.i) : 0) * root._animOpacity
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        transform: Translate {
            // Interpolates between the ~25 Hz poll updates for fluid motion.
            x: root._cursorX() + Config.offsetXFor(root.i) + root._animX
            y: root._cursorY() + root._audioY() + Config.offsetYFor(root.i) + root._animY - root._lift * 10
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }

        // Same shadow recipe as the depth effect; the angle knob steers
        // the horizontal/vertical offsets.
        layer.enabled: Config.featherFor(root.i) > 0.001 || root._shStrength > 0.001
        layer.effect: MultiEffect {
            id: fx
            blurEnabled: Config.featherFor(root.i) > 0.001
            blurMax: 16
            blur: Config.featherFor(root.i)
            shadowEnabled: root._shStrength > 0.001
            shadowColor: Qt.rgba(0, 0, 0, 0.72 * root._shStrength)
            shadowBlur: 0.55 + 0.45 * root._shStrength
            shadowHorizontalOffset: Math.round(Math.cos(root._shAngle) * 20 * root._shStrength)
            shadowVerticalOffset: Math.round(Math.sin(root._shAngle) * 20 * root._shStrength)
        }
    }
}
