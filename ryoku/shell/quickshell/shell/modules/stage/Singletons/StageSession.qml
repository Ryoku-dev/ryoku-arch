pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell

// Transient state for the Stage desktop edit session (docs/stage.md): which
// element the pointer last selected, whether the Add palette is open, and a live
// readout a drag/resize publishes for the toolbar. None of it is persisted: the
// session is the live desktop, there is no Save. One Escape cancels the current
// selection (the active gesture); a second, with nothing selected, exits.
Singleton {
    id: root

    property string selected: ""
    property bool paletteOpen: true
    // Live "widget  x, y" / "widget  120%" string while a gesture is in flight;
    // driven by the desktop's drag state, "" when idle.
    property string readout: ""

    function select(id) { root.selected = id; }
    function toggleSelect(id) { root.selected = (root.selected === id) ? "" : id; }

    // One Escape cancels the current selection and returns true (stay in edit
    // mode); with nothing selected it returns false so the caller exits.
    function escapeUnwinds() {
        if (root.selected !== "") {
            root.selected = "";
            return true;
        }
        return false;
    }

    // Fresh session each time compose mode opens.
    function reset() {
        root.selected = "";
        root.readout = "";
        root.paletteOpen = true;
    }
}
