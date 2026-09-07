import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// Ryoku Settings entry point. A normal floating window (not a layer-shell
// surface); the Hyprland window rule floats and centres it. `qs -c hub` loads
// this (the config dir and binary keep the internal "hub" name).
ShellRoot {
    FloatingWindow {
        id: win
        title: I18n.tr("Ryoku Settings")
        // The window rule floats this at 1360x880, which a 720p-class (or
        // scaled low-res) screen cannot hold -- the bottom action bar and the
        // right-hand controls land off screen. maximumSize is the
        // counterweight: Hyprland clamps the rule's size into the client's
        // hint and centres the result in the usable area, so the ideal size
        // wins where it fits and a small screen gets a window that actually
        // fits (margins leave room for the shell bar). minimumSize shrinks
        // with it, else the compositor refuses to go down. Roomy screens keep
        // an unbounded maximum, so manual resizing stays possible.
        // Guard on a positive width/height, not just a non-null screen: during a
        // monitor switch Quickshell hides/reshows the window and the screen object
        // briefly dangles -- still non-null, but reporting size 0. Unguarded, fitW/
        // fitH go negative and Quickshell forwards them to the compositor as
        // set_min_size/set_max_size, sizing the toplevel to ~0: invisible, no input
        // region (click-dead), while qs keeps running and pins the single-instance
        // lock so reopening no-ops.
        readonly property int fitW: (win.screen && win.screen.width > 0) ? Math.min(1200, win.screen.width - 24) : 1200
        readonly property int fitH: (win.screen && win.screen.height > 0) ? Math.min(880, win.screen.height - 56) : 880
        readonly property bool cramped: win.fitW < 1360 || win.fitH < 880
        minimumSize: Qt.size(Math.min(1120, win.fitW), Math.min(820, win.fitH))
        maximumSize: win.cramped ? Qt.size(win.fitW, win.fitH) : Qt.size(16777215, 16777215)
        color: Tokens.paper

        // Honour this monitor's Interface scale (Displays page): scale the whole
        // settings UI via Tokens. The window fills its screen, so a smaller scale
        // packs the chrome tighter rather than leaving a margin.
        Binding {
            target: Tokens
            property: "uiScale"
            value: Tokens.uiScaleFor(win.screen && win.screen.name ? win.screen.name : "")
        }

        // The launcher keybind (Super+,) guards against a second instance with
        // `flock` on /tmp/ryoku-hub.lock, held for the life of this process. The
        // in-app dismissals (Escape, close button) already route requestQuit();
        // closing the window through the compositor (Super+Q) only hides it while
        // qs keeps running, which would pin the lock and make Super+, silently
        // no-op until the orphan is killed. Quit on every close so the lock
        // always releases -- through requestQuit, so unsaved live Bar Studio
        // edits are walked back off the desktop first.
        onClosed: hubItem.requestQuit()

        Hub {
            id: hubItem
            anchors.fill: parent
            // Right-to-left languages (Arabic, Hebrew, Persian) mirror the whole
            // settings UI from here: Qt flips anchors, rows, layouts and text
            // alignment for every descendant, so this is the one place that has
            // to know, instead of every component. Live, like the language
            // itself, because I18n.rtl is a binding.
            LayoutMirroring.enabled: I18n.rtl
            LayoutMirroring.childrenInherit: true
        }
    }

    // drive navigation from the CLI (`qs -c hub ipc call nav open <key>`):
    // the QA loop and scripts jump straight to a section without a relaunch.
    IpcHandler {
        target: "nav"
        function open(section: string): void { hubItem.navigate(section); }
        function section(): string { return hubItem.section; }
    }

    // the daemon's `hub close` verb: same exit as the in-app dismissals (the
    // unsaved-restore then quit), so the flock releases and the next open
    // starts clean.
    IpcHandler {
        target: "hub"
        function close(): void { hubItem.requestQuit(); }
    }
}
