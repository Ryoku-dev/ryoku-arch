pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

// Transient state for the Stage desktop edit session (docs/stage.md): which
// element the pointer last selected, and which inspector tab is showing. None of
// it is persisted: the session is the live desktop, there is no Save. Selection
// drives everything now -- one element outlined at a time, its controls in its
// own inspector tab -- so there are no chips scattered across the desktop. One
// Escape drops the selection (the active gesture); a second, with nothing
// selected, exits.
Singleton {
    id: root

    // "" | a widget id ("clock", "plugin:foo") | "visualizer" | "layer:<n>".
    property string selected: ""
    // effect | look | motion | add | element. The element tab exists only while
    // something is selected.
    property string tab: "effect"

    function select(id) {
        root.selected = id;
        root.tab = "element";
    }
    function deselect() {
        root.selected = "";
        if (root.tab === "element")
            root.tab = "effect";
    }
    function toggleSelect(id) {
        if (root.selected === id)
            root.deselect();
        else
            root.select(id);
    }
    // Ignore a request for the element tab when nothing is selected, so the tab
    // row can bind blindly to it.
    function showTab(t) {
        if (t === "element" && root.selected === "")
            return;
        root.tab = t;
    }

    // Layer selections carry their registry index in the id ("layer:2").
    function isLayer(id) { return ("" + id).indexOf("layer:") === 0; }
    function layerIndex(id) { return root.isLayer(id) ? parseInt(("" + id).slice(6), 10) : -1; }

    // One Escape drops the selection and returns true (stay in edit mode); with
    // nothing selected it returns false so the caller exits.
    function escapeUnwinds() {
        if (root.selected !== "") {
            root.deselect();
            return true;
        }
        return false;
    }

    // Fresh session each time compose mode opens.
    function reset() {
        root.selected = "";
        root.tab = "effect";
    }
}
