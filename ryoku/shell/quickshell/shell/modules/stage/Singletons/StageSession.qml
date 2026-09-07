pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The live editor session (docs/stage.md): one on-desktop editor in one of two
// modes -- "widgets" (Ryostage: Depth, Widgets, Visualizer scopes) or "layout"
// (the shell's surfaces) -- never both. It carries the current scope, the one
// selected thing, whether anything changed this session (so Reset can appear and
// revert), and where each floating panel last sat per monitor. Panel positions
// are the only persisted state, in ~/.local/state/ryoku/stage-ui.json; the rest
// is the live desktop, and there is no Save.
Singleton {
    id: root

    // "" | "widgets" | "layout".
    property string mode: ""
    // widgets: "depth" | "widgets" | "visualizer"; layout: "surfaces".
    property string scope: "depth"
    // Selected element/surface id, or "" for none.
    property string selected: ""
    // A floating panel that is open right now: "" | "depth" | "settings" |
    // "style" | "add". One at a time; opening another replaces it.
    property string panel: ""
    property bool panelPinned: false

    readonly property bool widgets: root.mode === "widgets"
    readonly property bool layout: root.mode === "layout"

    // Non-look edits (a widget moved/hidden, a layer added, a surface's edge
    // changed) flip this; the reactive look diff below catches Depth's sliders
    // and the effect. Either makes the session dirty, so Reset can appear.
    property bool touched: false
    property var snap: null

    readonly property bool lookDirty: root.widgets && root.snap !== null
        && (Config.edge !== root.snap.edge || Config.shadow !== root.snap.shadow
            || Config.shadowAngle !== root.snap.shadowAngle
            || Config.quality !== root.snap.quality
            || Config.amount !== root.snap.amount || Config.idle !== root.snap.idle
            || Config.music !== root.snap.music
            || StageBackend.effect !== root.snap.effect)
    readonly property bool dirty: root.touched || root.lookDirty

    // The layout session owns its own revert (surface edges are its state), so
    // it listens for this and restores its baseline.
    signal resetRequested()

    function _snapshot() {
        return {
            edge: Config.edge, shadow: Config.shadow, shadowAngle: Config.shadowAngle,
            quality: Config.quality, amount: Config.amount, idle: Config.idle,
            music: Config.music, effect: StageBackend.effect
        };
    }

    function enterWidgets(scope) {
        root.mode = "widgets";
        root.scope = (scope && scope.length > 0) ? scope : "depth";
        root.selected = "";
        root.panel = root.scope === "depth" ? "depth" : "";
        root.panelPinned = false;
        root.touched = false;
        root.snap = root._snapshot();
    }
    function enterLayout() {
        root.mode = "layout";
        root.scope = "surfaces";
        root.selected = "";
        root.panel = "";
        root.panelPinned = false;
        root.touched = false;
        root.snap = null;
    }
    function leave() {
        root.mode = "";
        root.selected = "";
        root.panel = "";
        root.panelPinned = false;
        root.touched = false;
        root.snap = null;
    }

    function setScope(s) {
        if (root.scope === s)
            return;
        root.scope = s;
        root.selected = "";
        root.panelPinned = false;
        // Each scope owns its default panel: Depth shows its panel, the others
        // open a panel only on demand (Settings, Style, Add).
        root.panel = s === "depth" ? "depth" : "";
    }

    function select(id) { root.selected = id; }
    function deselect() {
        root.selected = "";
        if (!root.panelPinned && (root.panel === "settings" || root.panel === "style"))
            root.panel = "";
    }
    function toggleSelect(id) {
        if (root.selected === id)
            root.deselect();
        else
            root.select(id);
    }

    function isLayer(id) { return ("" + id).indexOf("layer:") === 0; }
    function layerIndex(id) { return root.isLayer(id) ? parseInt(("" + id).slice(6), 10) : -1; }

    function openPanel(kind) {
        root.panel = kind;
        root.panelPinned = false;
    }
    function closePanel() {
        root.panel = "";
        root.panelPinned = false;
    }
    function togglePin() { root.panelPinned = !root.panelPinned; }

    function markDirty() { root.touched = true; }

    // Escape unwinds one level at a time (docs/stage.md): an open unpinned panel
    // or a live gesture first, then the selection, then the session leaves.
    // Returns "gesture" | "selection" | "leave" so the host can act on "leave".
    function escapeStep() {
        if (root.panel !== "" && !root.panelPinned) {
            root.panel = "";
            return "gesture";
        }
        if (root.selected !== "") {
            root.deselect();
            return "selection";
        }
        return "leave";
    }

    function reset() {
        if (root.widgets && root.snap !== null) {
            Config.setQuality(root.snap.quality);
            Config.setEdge(root.snap.edge);
            Config.setShadow(root.snap.shadow);
            Config.setShadowAngle(root.snap.shadowAngle);
            Config.setAmount(root.snap.amount);
            Config.setIdle(root.snap.idle);
            Config.setMusic(root.snap.music);
            if (StageBackend.effect !== root.snap.effect)
                StageBackend.setEffect(root.snap.effect);
            root.snap = root._snapshot();
        }
        if (root.layout)
            root.resetRequested();
        root.touched = false;
    }

    // --- per-monitor panel positions (the only persisted state) ---------------
    function _key(monitor, kind) { return ("" + monitor) + "|" + kind; }
    function panelPos(monitor, kind) {
        const p = (adapter.positions || {})[root._key(monitor, kind)];
        return (p && typeof p.x === "number") ? p : null;
    }
    function setPanelPos(monitor, kind, x, y) {
        const next = {};
        const src = adapter.positions || {};
        for (const k in src)
            next[k] = src[k];
        next[root._key(monitor, kind)] = { x: Math.round(x), y: Math.round(y) };
        adapter.positions = next;
        settle.restart();
    }

    Timer { id: settle; interval: 400; onTriggered: file.writeAdapter() }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
            + "/ryoku/stage-ui.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        JsonAdapter {
            id: adapter
            property var positions: ({})
        }
    }
}
