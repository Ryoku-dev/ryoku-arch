pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global Stage settings on ~/.config/ryoku/stage.json (docs/stage.md). Only the
// look every layer inherits and the parallax drift live here; anything
// per-wallpaper (effect, scene, per-layer knobs, cut artifacts) is daemon-owned
// in the registry and reaches the shell through StageBackend's `stage` topic.
// Watched and self-seeded like the visualiser/depth singletons; drag-y setters
// coalesce writes through one settle timer.
Singleton {
    id: root

    property alias quality: adapter.quality
    property alias feather: adapter.feather
    property alias lift: adapter.lift
    property alias shadow: adapter.shadow
    property alias shadowAngle: adapter.shadowAngle
    property alias motion: adapter.motion
    property alias preset: adapter.preset
    property alias front: adapter.front

    // Motion sub-fields, read directly by the renderers (defaults guard a
    // half-written file).
    readonly property bool mouseEnabled: (root.motion && root.motion.mouse !== undefined) ? root.motion.mouse === true : true
    readonly property real mouseSensitivity: (root.motion && typeof root.motion.sensitivity === "number") ? root.motion.sensitivity : 1
    readonly property real mouseRange: (root.motion && typeof root.motion.range === "number") ? root.motion.range : 0.3
    readonly property real wallpaperParallax: (root.motion && typeof root.motion.wallpaper === "number") ? root.motion.wallpaper : 0.2

    function isFront(id) {
        return (adapter.front || []).indexOf(id) >= 0;
    }
    function toggleFront(id) {
        var arr = (adapter.front || []).slice();
        var i = arr.indexOf(id);
        if (i >= 0)
            arr.splice(i, 1);
        else
            arr.push(id);
        adapter.front = arr;
        settle.restart();
    }

    // Quality is a plain tier the daemon maps to model + matting when it cuts;
    // the UI never names "u2netp" or "alpha matting". Written eagerly because a
    // tier change is a deliberate act, not a drag.
    function setQuality(tier) {
        if (tier !== "draft" && tier !== "standard" && tier !== "fine")
            return;
        adapter.quality = tier;
        file.writeAdapter();
    }

    function setFeather(v) { adapter.feather = Math.max(0, Math.min(1, v)); settle.restart(); }
    function setLift(v) { adapter.lift = Math.max(0.2, Math.min(1, v)); settle.restart(); }
    function setShadow(v) { adapter.shadow = Math.max(0, Math.min(1, v)); settle.restart(); }
    function setShadowAngle(v) { adapter.shadowAngle = Math.round(v); settle.restart(); }

    function _setMotion(key, v) {
        var m = {};
        var src = adapter.motion || {};
        for (var k in src)
            m[k] = src[k];
        m[key] = v;
        adapter.motion = m;
        settle.restart();
    }
    function setMouseEnabled(on) { root._setMotion("mouse", on === true); }
    function setMouseSensitivity(v) { root._setMotion("sensitivity", Math.max(0.05, Math.min(2, v))); }
    function setMouseRange(v) { root._setMotion("range", Math.max(0.02, Math.min(1, v))); }
    function setWallpaperParallax(v) { root._setMotion("wallpaper", Math.max(0, Math.min(1, v))); }

    function setPreset(id) {
        if (["none", "softdepth", "audiopulse", "cinematic"].indexOf(id) < 0)
            return;
        adapter.preset = id;
        file.writeAdapter();
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/stage.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string quality: "draft"
            property real feather: 0.15
            property real lift: 1.0
            property real shadow: 0.0
            property int shadowAngle: 90
            property var motion: ({ mouse: true, sensitivity: 1, range: 0.3, wallpaper: 0.2 })
            property string preset: "none"
            property var front: []
        }
    }

    Component.onCompleted: if (!file.text())
        file.writeAdapter()
}
