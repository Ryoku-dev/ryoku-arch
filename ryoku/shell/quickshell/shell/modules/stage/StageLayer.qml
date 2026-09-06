pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Singletons"

// One stage layer: an alpha PNG at its scene z with feather, lift, angled
// shadow, and — when motion is on — cursor drift, idle animation and audio
// reactivity (docs/stage.md). The Subject-in-front effect uses one of these
// above the widgets with `motionEnabled: false`, so there is no separate depth
// renderer. Knobs come from the daemon's per-layer registry through
// StageBackend; feather/lift/shadow/shadowAngle inherit Config's global look.
Item {
    id: root

    property int layerIndex: 1
    property string wallPath: ""
    property string url: ""
    property string fit: "Cover"
    property real mouseNX: 0
    property real mouseNY: 0
    property real energy: 0
    // Off for the still Subject-in-front effect; on for parallax bands.
    property bool motionEnabled: true

    readonly property int i: root.layerIndex - 1
    readonly property bool layerShown: root.url !== ""
        && StageBackend.isActiveFor(root.wallPath)
        && StageBackend.layerEnabled(root.wallPath, root.i)
        && StageBackend.sceneIndexOfFor(root.wallPath, "layer:" + root.layerIndex) >= 0

    anchors.fill: parent
    visible: root.layerShown

    readonly property real _feather: StageBackend.layerFeather(root.wallPath, root.i, Config.feather)
    readonly property real _lift: StageBackend.layerLift(root.wallPath, root.i, Config.lift)
    readonly property real _shStrength: StageBackend.layerShadow(root.wallPath, root.i, Config.shadow)
    readonly property real _shAngle: StageBackend.layerShadowAngle(root.wallPath, root.i, Config.shadowAngle) * Math.PI / 180
    readonly property real _opacity: StageBackend.layerOpacity(root.wallPath, root.i)
    readonly property real _parallax: StageBackend.layerParallax(root.wallPath, root.i)
    readonly property real _depthFactor: StageBackend.layerDepthFactor(root.wallPath, root.i)
    readonly property real _offsetX: StageBackend.layerOffsetX(root.wallPath, root.i)
    readonly property real _offsetY: StageBackend.layerOffsetY(root.wallPath, root.i)
    readonly property real _mouseMax: StageBackend.layerMouseMax(root.wallPath, root.i)
    readonly property real _audio: StageBackend.layerAudioLevel(root.wallPath, root.i)
    readonly property string _anim: StageBackend.layerAnimType(root.wallPath, root.i)
    readonly property real _animSpeed: StageBackend.layerAnimSpeed(root.wallPath, root.i)
    readonly property real _animAmp: StageBackend.layerAnimAmplitude(root.wallPath, root.i)

    function _fillMode(im) {
        switch (root.fit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= root.width && im.sourceSize.height <= root.height) ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    function _maxShift() { return Math.min(root._mouseMax, root.width * 0.04 * Config.mouseRange); }
    function _cursorX() {
        if (!root.motionEnabled || !Config.mouseEnabled) return 0;
        return root.mouseNX * _maxShift() * 0.8 * root._parallax * (0.4 + root._depthFactor * 1.2) * Config.mouseSensitivity;
    }
    function _cursorY() {
        if (!root.motionEnabled || !Config.mouseEnabled) return 0;
        return root.mouseNY * _maxShift() * 0.8 * root._parallax * (0.4 + root._depthFactor * 1.2) * Config.mouseSensitivity;
    }
    function _audioY() {
        if (!root.motionEnabled || root._audio <= 0) return 0;
        return -root.energy * root._audio * 24;
    }

    readonly property int _dur: Math.max(500, Math.round(3200 / Math.max(0.1, root._animSpeed)))
    property real animT: 0
    Timer {
        id: animTick
        interval: 50
        repeat: true
        running: root.layerShown && root.motionEnabled && root._anim !== "none"
        onTriggered: root.animT += 50
    }
    readonly property real _phase: root.animT * 2 * Math.PI * 4 / root._dur
    readonly property real _animX: (root._anim === "float" || root._anim === "wiggle" || root._anim === "rotate")
        ? Math.sin(root._phase) * root._animAmp : 0
    readonly property real _animY: (root._anim === "float" || root._anim === "wiggle")
        ? Math.cos(root._phase) * root._animAmp : 0
    readonly property real _animOpacity: root._anim === "pulse"
        ? 0.55 + 0.45 * Math.abs(Math.sin(root._phase / 2)) : 1
    readonly property real _animScale: root._anim === "scale"
        ? 1.1 + root._animAmp / 200 * Math.sin(root._phase / 2) : 1
    readonly property real _animRotate: root._anim === "rotate"
        ? Math.sin(root._phase) * root._animAmp * 0.35 : 0

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
        opacity: (status === Image.Ready ? root._opacity : 0) * root._animOpacity
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        transform: Translate {
            x: root._cursorX() + root._offsetX + root._animX
            y: root._cursorY() + root._audioY() + root._offsetY + root._animY - root._lift * 10
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }

        // Edge feather and the angled cast shadow set the cut-out into the scene;
        // the FBO stays off when both are zero.
        layer.enabled: root._feather > 0.001 || root._shStrength > 0.001
        layer.effect: MultiEffect {
            blurEnabled: root._feather > 0.001
            blurMax: 16
            blur: root._feather
            shadowEnabled: root._shStrength > 0.001
            shadowColor: Qt.rgba(0, 0, 0, 0.72 * root._shStrength)
            shadowBlur: 0.55 + 0.45 * root._shStrength
            shadowHorizontalOffset: Math.round(Math.cos(root._shAngle) * 20 * root._shStrength)
            shadowVerticalOffset: Math.round(Math.sin(root._shAngle) * 20 * root._shStrength)
        }
    }
}
