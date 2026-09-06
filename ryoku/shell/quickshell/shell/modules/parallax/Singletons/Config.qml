pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Parallax module config (docs/parallax.md). Auto mode runs
// ryoku-parallax-engine (subject + recoloured background); manual mode
// lists the wallpaper's folder. Every artifact lives in
// ~/Pictures/Parallax/<stem>/.
Singleton {
    id: root

    property alias enabled: adapter.enabled
    property alias mode: adapter.mode
    property alias model: adapter.model
    property alias alphaMatting: adapter.alphaMatting
    property alias bands: adapter.bands

    property alias mouseEnabled: adapter.mouseEnabled
    property real mouseSensitivity: adapter.mouseSensitivity
    property real mouseRange: adapter.mouseRange

    property real wallpaperParallax: adapter.wallpaperParallax

    // Per-layer knob arrays (index 0 = layer 1, back of the scene).
    property var parallax: adapter.parallax
    property var opacity: adapter.opacity
    property var depth: adapter.depth
    property var offsetX: adapter.offsetX
    property var offsetY: adapter.offsetY
    property var mouseMax: adapter.mouseMax
    property var audioLevel: adapter.audioLevel
    property var animType: adapter.animType
    property var animSpeed: adapter.animSpeed
    property var animAmplitude: adapter.animAmplitude
    property var shadow: adapter.shadow
    property var shadowAngle: adapter.shadowAngle
    property var feather: adapter.feather
    property var lift: adapter.lift
    property var layerEnabled: adapter.layerEnabled

    property alias scene: adapter.scene

    property var _reg: ({})

    property int wallBands: 0
    readonly property var bandCount: Math.max(1, Math.min(8, root.wallBands > 0 ? root.wallBands : (adapter.bands || 1)))
    readonly property var builtinWidgetIds: ["clock", "calendar", "music", "aio", "stats", "weather", "notes"]

    property string activePath: ""
    property bool wallActive: false
    property string wallMode: "auto"
    property string backgroundUrl: ""
    property string cutProgress: ""
    // Per-monitor cursor (-1..1); a single shared pair made two monitors
    // fight over the values and the layers trembled.
    property var _cursor: ({})
    function setCursor(name, nx, ny) {
        const next = {};
        for (const k in root._cursor)
            next[k] = root._cursor[k];
        next[name] = { nx: nx, ny: ny };
        root._cursor = next;
    }
    function cursorNXFor(name) {
        const e = root._cursor && root._cursor[name];
        return e ? e.nx : 0;
    }
    function cursorNYFor(name) {
        const e = root._cursor && root._cursor[name];
        return e ? e.ny : 0;
    }
    readonly property string progressPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/parallax/progress"
    property var layers: []
    property var wallScene: []

    function wallStem() {
        if (root.activePath === "") return "";
        const base = root.activePath.split("/").pop();
        return base.replace(/\.[^.]+$/, "");
    }
    function wallFolder() {
        const stem = root.wallStem();
        if (stem === "") return "";
        return (Quickshell.env("HOME") || "") + "/Pictures/Parallax/" + stem;
    }
    function backgroundOutUrl() {
        const folder = root.wallFolder();
        if (folder === "") return "";
        // The subject's rev changes per re-cut, so the surface reloads the
        // recoloured background instead of keeping the old texture.
        const ls = root._reg.layers && root.activePath ? root._reg.layers[root.activePath] : null;
        const rev = (ls && ls.length && ls[0].rev) ? ls[0].rev : 0;
        return "file://" + folder + "/background.png?v=" + rev;
    }

    function _recompute() {
        const p = root.activePath;
        const reg = root._reg;
        const w = reg.walls && p ? reg.walls[p] : null;
        const ls = reg.layers && p ? reg.layers[p] : null;
        if (!p) {
            root.wallActive = false;
            root.layers = [];
            root.wallScene = [];
            root.wallMode = root.mode;
            root.wallBands = 0;
            root.backgroundUrl = "";
            return;
        }
        root.wallActive = !!(w && w.enabled && ls && ls.length);
        root.layers = (w && w.enabled && ls) ? ls : [];
        root.wallScene = (w && w.scene && w.scene.length) ? w.scene : [];
        root.wallBands = (w && w.enabled && ls) ? ls.length : 0;
        root.wallMode = (w && w.mode) ? w.mode : root.mode;
        root.backgroundUrl = (w && w.mode === "auto") ? root.backgroundOutUrl() : "";
    }
    onActivePathChanged: root._recompute()

    function setWallEnabled(on) {
        if (!root.activePath) return;
        wallProc.command = ["ryoku-shell", "parallax", "set-enabled", on ? "1" : "0"];
        wallProc.running = false;
        wallProc.running = true;
    }
    function setMode(mode) {
        if (mode !== "auto" && mode !== "manual") return;
        adapter.mode = mode;
        root.wallMode = mode;
        file.writeAdapter();
        if (!root.activePath) return;
        modeProc.command = ["ryoku-shell", "parallax", "set-mode", mode];
        modeProc.running = false;
        modeProc.running = true;
    }
    function setCutTier(tier) {
        if (tier === "fine") { adapter.model = "birefnet-general-lite"; adapter.alphaMatting = true; }
        else if (tier === "standard") { adapter.model = "u2netp"; adapter.alphaMatting = true; }
        else { adapter.model = "u2netp"; adapter.alphaMatting = false; }
        save();
        root.refresh();
    }
    function cutTier() {
        if (adapter.model === "birefnet-general-lite") return "fine";
        return adapter.alphaMatting ? "standard" : "draft";
    }
    function refresh() {
        if (!root.activePath) return;
        refreshProc.running = false;
        refreshProc.running = true;
    }
    function cancel() {
        cancelProc.running = false;
        cancelProc.running = true;
        root.cutProgress = "cancelled";
    }
    function setEnabledGlobal(on) {
        adapter.enabled = on === true;
        save();
        root.ensureDefaults();
    }
    function removeManualLayer(layerPath) {
        if (!root.activePath || !layerPath) return;
        removeLayerProc.command = ["ryoku-shell", "parallax", "remove-layer", layerPath];
        removeLayerProc.running = false;
        removeLayerProc.running = true;
    }
    Process {
        id: wallProc
        command: ["ryoku-shell", "parallax", "set-enabled", "0"]
    }
    Process {
        id: modeProc
        command: ["ryoku-shell", "parallax", "set-mode", "auto"]
    }
    Process {
        id: refreshProc
        command: ["ryoku-shell", "parallax", "refresh"]
    }
    Process {
        id: cancelProc
        command: ["ryoku-shell", "parallax", "cancel"]
    }
    Process {
        id: sceneProc
        command: ["ryoku-shell", "parallax", "set-scene", "[]"]
    }
    Process {
        id: removeLayerProc
        command: ["ryoku-shell", "parallax", "remove-layer", ""]
    }

    function _arr(a, i, def) {
        return (a && i >= 0 && i < a.length && a[i] !== undefined) ? a[i] : def;
    }
    function layerEnabled2(i)  { return root._arr(adapter.layerEnabled, i, true) === true; }
    function parallaxFor(i)    { return root._arr(adapter.parallax, i, 1); }
    function opacityFor(i)     { return root._arr(adapter.opacity, i, 1); }
    function depthFor(i)       { return root._arr(adapter.depth, i, 0.5); }
    function offsetXFor(i)     { return root._arr(adapter.offsetX, i, 0); }
    function offsetYFor(i)     { return root._arr(adapter.offsetY, i, 0); }
    function mouseMaxFor(i)    { return root._arr(adapter.mouseMax, i, 32); }
    function audioLevelFor(i)  { return root._arr(adapter.audioLevel, i, 0); }
    function animTypeFor(i)    { return root._arr(adapter.animType, i, "none"); }
    function animSpeedFor(i)   { return root._arr(adapter.animSpeed, i, 0.5); }
    function animAmplitudeFor(i) { return root._arr(adapter.animAmplitude, i, 10); }
    function shadowFor(i)      { return root._arr(adapter.shadow, i, 0); }
    function shadowAngleFor(i) { return root._arr(adapter.shadowAngle, i, 90); }
    function featherFor(i)     { return root._arr(adapter.feather, i, 0); }
    function liftFor(i)        { return root._arr(adapter.lift, i, 0); }

    function _def(arr) {
        switch (arr) {
        case adapter.layerEnabled: return true;
        case adapter.parallax: return 1;
        case adapter.opacity: return 1;
        case adapter.depth: return 0.5;
        case adapter.mouseMax: return 32;
        case adapter.audioLevel: return 0;
        case adapter.animType: return "none";
        case adapter.animSpeed: return 0.5;
        case adapter.animAmplitude: return 10;
        case adapter.shadow: return 0;
        case adapter.shadowAngle: return 90;
        case adapter.feather: return 0;
        case adapter.lift: return 0;
        }
        return 0;
    }
    function _set(arr, i, v) {
        const a = (arr || []).slice();
        while (a.length <= i) a.push(_def(arr));
        a[i] = v;
        return a;
    }

    function setLayerEnabled2(i, v) { adapter.layerEnabled = _set(adapter.layerEnabled, i, v === true); save(); }
    function setParallaxFor(i, v) { adapter.parallax = _set(adapter.parallax, i, Math.max(0, Math.min(2, v))); save(); }
    function setOpacityFor(i, v) { adapter.opacity = _set(adapter.opacity, i, Math.max(0, Math.min(1, v))); save(); }
    function setDepthFor(i, v) { adapter.depth = _set(adapter.depth, i, Math.max(0, Math.min(1, v))); save(); }
    function setOffsetXFor(i, v) { adapter.offsetX = _set(adapter.offsetX, i, Math.round(v)); save(); }
    function setOffsetYFor(i, v) { adapter.offsetY = _set(adapter.offsetY, i, Math.round(v)); save(); }
    function setMouseMaxFor(i, v) { adapter.mouseMax = _set(adapter.mouseMax, i, Math.max(0, Math.min(96, Math.round(v)))); save(); }
    function setAudioLevelFor(i, v) { adapter.audioLevel = _set(adapter.audioLevel, i, Math.max(0, Math.min(1, v))); save(); }
    function setAnimTypeFor(i, v) { adapter.animType = _set(adapter.animType, i, v); save(); }
    function setAnimSpeedFor(i, v) { adapter.animSpeed = _set(adapter.animSpeed, i, Math.max(0.1, Math.min(3, v))); save(); }
    function setAnimAmpFor(i, v) { adapter.animAmplitude = _set(adapter.animAmplitude, i, Math.max(0, Math.min(64, Math.round(v)))); save(); }
    function setShadowFor(i, v) { adapter.shadow = _set(adapter.shadow, i, Math.max(0, Math.min(1, v))); save(); }
    function setShadowAngleFor(i, v) { adapter.shadowAngle = _set(adapter.shadowAngle, i, Math.round(v)); save(); }
    function setFeatherFor(i, v) { adapter.feather = _set(adapter.feather, i, Math.max(0, Math.min(1, v))); save(); }
    function setLiftFor(i, v) { adapter.lift = _set(adapter.lift, i, Math.max(0, Math.min(1, v))); save(); }

    function setMouseSensitivity(v) { adapter.mouseSensitivity = Math.max(0.05, Math.min(2, v)); save(); }
    function setMouseRange(v) { adapter.mouseRange = Math.max(0.02, Math.min(1, v)); save(); }
    function setWallpaperParallax(v) { adapter.wallpaperParallax = Math.max(0, Math.min(1, v)); save(); }

    // None resets the defaults; the rest tune the whole stack at once.
    function applyPreset(id) {
        const n = root.bandCount;
        var pl = [], dp = [], al = [], amp = [], spd = [], ft = [], lf = [];
        for (var i = 0; i < n; i++) {
            const t = n <= 1 ? 0.5 : i / (n - 1);
            switch (id) {
            case "softdepth":
                pl.push(1 - t * 0.4); dp.push(0.2 + t * 0.8); al.push(0); amp.push(4); spd.push(0.4); ft.push(0); lf.push(0.1 + t * 0.3);
                break;
            case "audiopulse":
                pl.push(0.9); dp.push(0.5); al.push(0.6); amp.push(8); spd.push(0.8); ft.push(0.1); lf.push(0.3);
                break;
            case "cinematic":
                pl.push(1.4 - t * 0.4); dp.push(0.3 + t * 0.4); al.push(0.15); amp.push(16); spd.push(0.15); ft.push(0.2); lf.push(0.5);
                break;
            default: // none
                pl.push(1); dp.push(0.5); al.push(0); amp.push(10); spd.push(0.5); ft.push(0); lf.push(0);
                break;
            }
        }
        adapter.parallax = pl;
        adapter.depth = dp;
        adapter.audioLevel = al;
        adapter.animAmplitude = amp;
        adapter.animSpeed = spd;
        adapter.feather = ft;
        adapter.lift = lf;
        for (var j = 0; j < n; j++) {
            adapter.animType = _set(adapter.animType, j, id === "none" ? "none" : "float");
            adapter.shadow = _set(adapter.shadow, j, id === "cinematic" ? 0.5 : 0);
        }
        // none returns the whole stack to defaults, not just animType/shadow.
        if (id === "none") {
            var op = [], ox = [], oy = [], mm = [], sa = [], le = [];
            for (var k = 0; k < n; k++) { op.push(1); ox.push(0); oy.push(0); mm.push(32); sa.push(90); le.push(true); }
            adapter.opacity = op;
            adapter.offsetX = ox;
            adapter.offsetY = oy;
            adapter.mouseMax = mm;
            adapter.shadowAngle = sa;
            adapter.layerEnabled = le;
        }
        save();
    }

    function save() { file.writeAdapter(); }

    function defaultScene() {
        const out = ["wallpaper"];
        for (var i = 1; i <= root.bandCount; i++) out.push("layer:" + i);
        for (const w of root.builtinWidgetIds) out.push("widget:" + w);
        out.push("visualizer");
        return out;
    }
    function sceneOr(name) { return root.effectiveScene().indexOf(name); }
    function effectiveScene() {
        if (root.wallScene && root.wallScene.length) return root.wallScene;
        return (adapter.scene && adapter.scene.length) ? adapter.scene : root.defaultScene();
    }
    function sceneIndexOf(name) { return root.sceneOr(name); }
    function sceneZ(name) {
        const i = root.sceneOr(name);
        return i < 0 ? 0 : i * 2 + 1;
    }
    function sceneGapZ() {
        const s = root.effectiveScene();
        for (var i = s.length - 1; i >= 0; i--)
            if (s[i].indexOf("layer:") === 0) return i * 2 + 1.5;
        return 1;
    }
    function widgetZ(id) {
        const name = "widget:" + id;
        const i = root.sceneOr(name);
        return i >= 0 ? i * 2 + 2 : root.sceneGapZ();
    }
    function setScene(arr) {
        const list = arr ? arr.slice() : [];
        if (root.activePath) {
            sceneProc.command = ["ryoku-shell", "parallax", "set-scene", JSON.stringify(list)];
            sceneProc.running = false;
            sceneProc.running = true;
            root.wallScene = list;
            return;
        }
        adapter.scene = list;
        save();
    }

    function layerLabel(i) {
        const ls = root.layers;
        const lbl = (i >= 1 && i <= ls.length && ls[i - 1].label) ? ls[i - 1].label : "";
        if (lbl) return lbl.charAt(0).toUpperCase() + lbl.slice(1);
        return "Layer %1".arg(i);
    }
    function layerDepth(i) {
        const ls = root.layers;
        if (i < 1 || i > ls.length) return -1;
        const d = ls[i - 1].depth;
        return typeof d === "number" ? d : -1;
    }
    function layerArea(i) {
        const ls = root.layers;
        if (i < 1 || i > ls.length) return -1;
        const a = ls[i - 1].area;
        return typeof a === "number" ? a : -1;
    }
    function layerUrl(i) {
        const ls = root.layers;
        if (i < 1 || i > ls.length) return "";
        return "file://" + ls[i - 1].out + "?v=" + ls[i - 1].rev;
    }
    function layerPath(i) {
        const ls = root.layers;
        if (i < 1 || i > ls.length) return "";
        return ls[i - 1].out;
    }
    function isLayerReady(i) { return root.layerUrl(i) !== ""; }

    // Per-wallpaper parallax state, so a multi-monitor box does not let one
    // screen's wallpaper overwrite the others'. The layer cut, opt-in, scene
    // order and recoloured background are a pure function of the wallpaper path
    // and the shared registry (_reg), so every surface reads its OWN screen's
    // wallpaper path through these *ForPath helpers. The scalar activePath/wall*
    // above stay as the quick-settings panel's view of the current wallpaper.
    function _stemFor(path) {
        if (!path) return "";
        const base = path.split("/").pop();
        return base.replace(/\.[^.]+$/, "");
    }
    function _folderFor(path) {
        const stem = root._stemFor(path);
        if (stem === "") return "";
        return (Quickshell.env("HOME") || "") + "/Pictures/Parallax/" + stem;
    }
    function _wallOf(path) { return (root._reg.walls && path) ? root._reg.walls[path] : null; }
    function _layersOf(path) { return (root._reg.layers && path) ? root._reg.layers[path] : null; }
    function wallActiveForPath(path) {
        const w = root._wallOf(path);
        const ls = root._layersOf(path);
        return !!(path && w && w.enabled && ls && ls.length);
    }
    function layersForPath(path) {
        const w = root._wallOf(path);
        const ls = root._layersOf(path);
        return (w && w.enabled && ls) ? ls : [];
    }
    function wallModeForPath(path) {
        const w = root._wallOf(path);
        return (w && w.mode) ? w.mode : root.mode;
    }
    function bandCountForPath(path) {
        const n = root.layersForPath(path).length;
        return Math.max(1, Math.min(8, n > 0 ? n : (adapter.bands || 1)));
    }
    function backgroundUrlForPath(path) {
        const w = root._wallOf(path);
        if (!(w && w.mode === "auto")) return "";
        const folder = root._folderFor(path);
        if (folder === "") return "";
        const ls = root._layersOf(path);
        const rev = (ls && ls.length && ls[0].rev) ? ls[0].rev : 0;
        return "file://" + folder + "/background.png?v=" + rev;
    }
    function layerUrlForPath(path, i) {
        const ls = root.layersForPath(path);
        if (i < 1 || i > ls.length) return "";
        return "file://" + ls[i - 1].out + "?v=" + ls[i - 1].rev;
    }
    function defaultSceneForPath(path) {
        const out = ["wallpaper"];
        const n = root.bandCountForPath(path);
        for (var i = 1; i <= n; i++) out.push("layer:" + i);
        for (const wid of root.builtinWidgetIds) out.push("widget:" + wid);
        out.push("visualizer");
        return out;
    }
    function effectiveSceneForPath(path) {
        const w = root._wallOf(path);
        const ws = (w && w.scene && w.scene.length) ? w.scene : [];
        if (ws.length) return ws;
        return (adapter.scene && adapter.scene.length) ? adapter.scene : root.defaultSceneForPath(path);
    }
    function sceneIndexOfForPath(path, name) { return root.effectiveSceneForPath(path).indexOf(name); }
    function sceneZForPath(path, name) {
        const i = root.sceneIndexOfForPath(path, name);
        return i < 0 ? 0 : i * 2 + 1;
    }
    function sceneGapZForPath(path) {
        const s = root.effectiveSceneForPath(path);
        for (var i = s.length - 1; i >= 0; i--)
            if (s[i].indexOf("layer:") === 0) return i * 2 + 1.5;
        return 1;
    }
    function widgetZForPath(path, id) {
        const name = "widget:" + id;
        const i = root.sceneIndexOfForPath(path, name);
        return i >= 0 ? i * 2 + 2 : root.sceneGapZForPath(path);
    }

    function ensureDefaults() {
        const n = root.bandCount;
        function grow(arr, def) {
            let a = arr;
            if (!a) { a = []; }
            while (a.length < n) a.push(def);
            return a;
        }
        adapter.parallax = grow(adapter.parallax, 1);
        adapter.opacity = grow(adapter.opacity, 1);
        adapter.depth = grow(adapter.depth, 0.5);
        adapter.offsetX = grow(adapter.offsetX, 0);
        adapter.offsetY = grow(adapter.offsetY, 0);
        adapter.mouseMax = grow(adapter.mouseMax, 32);
        adapter.audioLevel = grow(adapter.audioLevel, 0);
        adapter.animType = grow(adapter.animType, "none");
        adapter.animSpeed = grow(adapter.animSpeed, 0.5);
        adapter.animAmplitude = grow(adapter.animAmplitude, 10);
        adapter.shadow = grow(adapter.shadow, 0);
        adapter.shadowAngle = grow(adapter.shadowAngle, 90);
        adapter.feather = grow(adapter.feather, 0);
        adapter.lift = grow(adapter.lift, 0);
        adapter.layerEnabled = grow(adapter.layerEnabled, true);
    }
    onEnabledChanged: root.ensureDefaults()
    onWallBandsChanged: root.ensureDefaults()

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/parallax.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool enabled: false
            property string mode: "auto"
            property string model: "u2netp"
            property bool alphaMatting: false
            property int bands: 1
            property bool mouseEnabled: true
            property real mouseSensitivity: 0.9
            property real mouseRange: 1.0
            property real wallpaperParallax: 0.5
            property var parallax: []
            property var opacity: []
            property var depth: []
            property var offsetX: []
            property var offsetY: []
            property var mouseMax: []
            property var audioLevel: []
            property var animType: []
            property var animSpeed: []
            property var animAmplitude: []
            property var shadow: []
            property var shadowAngle: []
            property var feather: []
            property var lift: []
            property var layerEnabled: []
            property var scene: []
        }
    }

    FileView {
        id: wallsFile
        path: (Quickshell.env("HOME") || "") + "/Pictures/Parallax/layers.pz"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._reg = JSON.parse(wallsFile.text());
            } catch (e) {
                root._reg = {};
            }
            root._recompute();
            root.ensureDefaults();
        }
    }

    Component.onCompleted: {
        root.ensureDefaults();
        if (wallsFile.text())
            wallsFile.reload();
    }
}
