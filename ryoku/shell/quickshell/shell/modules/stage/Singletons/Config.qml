pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global Stage settings on ~/.config/ryoku/stage.json (docs/stage.md). Only the
// look every layer inherits (edge, shadow) and the motion the whole stack shares
// (amount, idle, music) live here; anything per-wallpaper (effect, per-layer
// front/depth, cut artifacts) is daemon-owned in the registry and reaches the
// shell through StageBackend's `stage` topic. `front` is the widget ids the user
// lifted above the in-front layers from the desktop editor. Watched and
// self-seeded; drag-y setters coalesce writes through one settle timer, while
// deliberate segmented picks write eagerly.
Singleton {
    id: root

    property alias quality: adapter.quality
    property alias edge: adapter.edge
    property alias shadow: adapter.shadow
    property alias shadowAngle: adapter.shadowAngle
    property alias motion: adapter.motion
    property alias front: adapter.front

    // Motion sub-fields, read directly by the renderer (defaults guard a
    // half-written file). Amount is a word the UI shows; the renderer needs the
    // drift/idle multiplier it stands for.
    readonly property string amount: (root.motion && typeof root.motion.amount === "string") ? root.motion.amount : "normal"
    readonly property string idle: (root.motion && typeof root.motion.idle === "string") ? root.motion.idle : "none"
    readonly property bool music: !!(root.motion && root.motion.music === true)
    readonly property real amountFactor: root.amount === "subtle" ? 0.5 : root.amount === "strong" ? 1.8 : 1.0

    // `front` is read-only now: the layer owns whether it sits behind or in
    // front of the widgets, so the desktop editor never writes a per-widget
    // lift. Kept only so an existing stage.json that pinned widgets still
    // renders them above the in-front layers (docs/stage.md).
    function isFront(id) {
        return (adapter.front || []).indexOf(id) >= 0;
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

    function setEdge(v) { adapter.edge = Math.max(0, Math.min(1, v)); settle.restart(); }
    function setShadow(v) { adapter.shadow = Math.max(0, Math.min(1, v)); settle.restart(); }
    function setShadowAngle(v) { adapter.shadowAngle = Math.round(v); settle.restart(); }

    function _setMotion(key, v) {
        var m = {};
        var src = adapter.motion || {};
        for (var k in src)
            m[k] = src[k];
        m[key] = v;
        adapter.motion = m;
        file.writeAdapter();
    }
    function setAmount(a) { if (["subtle", "normal", "strong"].indexOf(a) >= 0) root._setMotion("amount", a); }
    function setIdle(i) { if (["none", "float", "breathe"].indexOf(i) >= 0) root._setMotion("idle", i); }
    function setMusic(on) { root._setMotion("music", on === true); }

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
            property real edge: 0.15
            property real shadow: 0.0
            property int shadowAngle: 90
            property var motion: ({ amount: "normal", idle: "none", music: false })
            property var front: []
        }
    }

    Component.onCompleted: if (!file.text())
        file.writeAdapter()
}
