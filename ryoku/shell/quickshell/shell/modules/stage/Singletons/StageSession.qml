pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

// The live editor session (docs/stage.md, "Session model"): one of two modes,
// "widgets" (the desktop's widgets) or "shell" (the bar, the dock, the edge
// menus, Depth and Parallax), on one monitor, never both. It carries the
// ribbon's tab, the one selected thing, the drop-down that is open, a pending
// confirm, and whether anything changed (so Reset can appear). Each editor
// keeps its own snapshot and restores it on resetRequested; nothing here is
// persisted, and there is no Save: the desktop is the document.
Singleton {
    id: root

    // "" | "widgets" | "shell".
    property string mode: ""
    // The screen the session was opened on (its desktop lifts, its editor shows).
    property string monitor: ""
    // Edit shell's ribbon tab: "bar" | "dock" | "menus" | "depth" | "parallax".
    property string tab: "bar"
    // Selected element: a widget id ("clock", "plugin:x"), a surface id ("bar",
    // "dock", "quick-settings", ...), "layer:N", or "" for none.
    property string selected: ""
    // The drop-down panel open under a toolbar/ribbon button: "" | "add" |
    // "modules" | "apps" | "layers". One at a time.
    property string panel: ""
    // A confirm waiting for its second press: "" | "quality" | "cut" | "clear".
    property string pending: ""

    readonly property bool active: root.mode !== ""
    readonly property bool widgets: root.mode === "widgets"
    readonly property bool shell: root.mode === "shell"

    property bool dirty: false

    // Editors restore their own snapshot on this.
    signal resetRequested()
    signal left()

    function onMonitor(name) { return root.active && ("" + name) === root.monitor; }

    function enterWidgets(monitor) {
        root._enter("widgets", monitor);
    }
    function enterShell(monitor, tab) {
        root._enter("shell", monitor);
        root.tab = (tab && tab.length > 0) ? tab : "bar";
    }
    function _enter(mode, monitor) {
        root.selected = "";
        root.panel = "";
        root.pending = "";
        root.dirty = false;
        root.monitor = "" + (monitor || "");
        root.mode = mode;
    }
    function leave() {
        if (!root.active)
            return;
        root.mode = "";
        root.selected = "";
        root.panel = "";
        root.pending = "";
        root.dirty = false;
        root.left();
    }

    function setTab(t) {
        if (root.tab === t)
            return;
        root.tab = t;
        root.selected = "";
        root.panel = "";
        root.pending = "";
    }

    function select(id) { root.selected = "" + id; }
    function deselect() { root.selected = ""; }
    function toggleSelect(id) {
        if (root.selected === ("" + id))
            root.deselect();
        else
            root.select(id);
    }
    function isLayer(id) { return ("" + id).indexOf("layer:") === 0; }
    function layerIndex(id) { return root.isLayer(id) ? parseInt(("" + id).slice(6), 10) : -1; }

    function openPanel(kind) { root.panel = "" + kind; }
    function closePanel() { root.panel = ""; }
    function togglePanel(kind) { root.panel = root.panel === ("" + kind) ? "" : ("" + kind); }

    function setPending(kind) { root.pending = "" + kind; }
    function clearPending() { root.pending = ""; }

    function markDirty() { root.dirty = true; }
    function reset() {
        root.pending = "";
        root.resetRequested();
        root.dirty = false;
    }

    // Escape unwinds one level per press: an open drop-down, then a pending
    // confirm, then the selection, then the session. Returns what it did.
    function escapeStep() {
        if (root.panel !== "") {
            root.panel = "";
            return "panel";
        }
        if (root.pending !== "") {
            root.pending = "";
            return "pending";
        }
        if (root.selected !== "") {
            root.selected = "";
            return "selection";
        }
        root.leave();
        return "leave";
    }
}
