pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import shell.services
import "lib/dock.js" as DockList

// Shared dock model: running-window + pinned-app data and the activate action,
// one source for every dock surface (Sumi's in-rail RailDock and the first-class
// modules/dock surface). The list maths live in the tested lib/dock.js. The
// first-class dock's pins and look live in this singleton's `dock` store (below);
// RailDock keeps its own pins.
Singleton {
    id: root

    // Live-update: Hyprland events keep the toplevel LIST live, but a newly opened
    // window's lastIpcObject (its class/title) is not populated until a
    // refreshToplevels() runs -- so without a refresh the dock only picks up new
    // apps on a shell reload. Refresh whenever the window COUNT changes (open or
    // close), which is idempotent: the refresh fires valuesChanged again but the
    // count is unchanged, so it never loops. Bump _rev on every list/toplevel/
    // active change so clients/activeClass re-read (a plain .values read in a
    // binding does not track Quickshell's model).
    property int _rev: 0
    property int _primeTries: 0
    // Icon resolution is not reactive on its own: iconFor() reads the desktop DB and
    // the icon theme through plain function calls, so a binding that resolves before
    // the desktop DB is scanned or the icon-theme cache is warm -- a fresh boot, or
    // right after an app updates its .desktop/icon -- sticks on the generic
    // application-x-executable fallback until a shell reload (the "zen icon keeps
    // resetting to a gear" break). Bump iconRev to force every icon binding to
    // re-resolve: on a desktop-DB change and via a bounded warm-up poll after load.
    property int iconRev: 0
    property int _iconTries: 0
    // True while some toplevel is in the list without its class yet (a freshly
    // opened window, before its ipc object is populated).
    function _needsPrime() {
        const tls = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < tls.length; ++i) {
            const o = tls[i] && tls[i].lastIpcObject;
            if (!o || !(o.class || o.initialClass))
                return true;
        }
        return false;
    }
    // A new window enters the list before a refreshToplevels() fills in its class,
    // and a single refresh can lose the race (rapid opens). Poll-refresh until
    // every toplevel has a class, then stop -- bounded so a genuinely class-less
    // surface cannot spin forever.
    Timer {
        id: primePoll
        interval: 120
        repeat: true
        onTriggered: {
            if (root._primeTries++ > 25 || !root._needsPrime()) {
                primePoll.stop();
                return;
            }
            Hyprland.refreshToplevels();
        }
    }
    Component.onCompleted: Hyprland.refreshToplevels()
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            root._rev++;
            root._primeTries = 0;
            if (root._needsPrime())
                primePoll.restart();
        }
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root._rev++; }
        // Hyprland.activeToplevel never populates on this fork's ipc (the same
        // request-socket parse gap Fullscreen.qml documents), so focus is read out
        // of the toplevel list instead -- hyprctl marks the focused window
        // focusHistoryID 0. That field only moves when the list is re-read, so a
        // focus event has to force the refresh.
        function onRawEvent(event) {
            if (event.name === "activewindow" || event.name === "activewindowv2")
                Qt.callLater(Hyprland.refreshToplevels);
        }
    }
    Instantiator {
        model: Hyprland.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { root._rev++; }
        }
    }

    // A desktop-DB change -- an app installed, updated, or removed -- can add or fix
    // the icon a pin resolves to; re-resolve every dock icon when it fires so a pin
    // recovers its real icon live instead of waiting for a reload.
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.iconRev++; }
    }
    // The icon-theme cache warms a little after the shell starts and nothing signals
    // it, so an icon can be unresolvable at first paint and findable a moment later.
    // Re-resolve a bounded handful of times over the first few seconds after load, so
    // a pin that came up on the generic fallback heals itself without a reload.
    Timer {
        id: iconWarmup
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            root.iconRev++;
            if (++root._iconTries >= 12)
                iconWarmup.stop();
        }
    }

    // Every first-party Quickshell app (the Hub, Ryostore, Ryoport) reaches the
    // compositor as class org.quickshell: Quickshell owns the Wayland app id
    // and offers no way to set one per config. The title is the only thing
    // that tells them apart, so it maps to the desktop entry id the dock
    // groups, launches and draws them by; anything else keeps its class.
    readonly property var quickshellApps: ({ "Ryoku Settings": "ryoku-hub", "Ryostore": "ryostore", "ryovm": "ryovm" })
    function classOf(data) {
        if (!data) return "";
        const cls = data.class || data.initialClass;
        if (cls === "org.quickshell" && root.quickshellApps[data.title || data.initialTitle])
            return root.quickshellApps[data.title || data.initialTitle];
        return cls;
    }

    // Toplevels as { className, address, pid }, pid-sorted for a stable order.
    readonly property var clients: {
        void root._rev;
        const result = [];
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < toplevels.length; ++i) {
            const data = toplevels[i] && toplevels[i].lastIpcObject;
            const className = root.classOf(data);
            if (typeof className === "string" && className)
                result.push({ className: className, address: data.address || "", pid: (typeof data.pid === "number" ? data.pid : 0) });
        }
        result.sort((a, b) => a.pid - b.pid);
        return result;
    }

    // The focused window's ipc object, or null when nothing holds focus:
    // focusHistoryID 0 is hyprctl's focused marker, with quickshell's own
    // activeToplevel as the fallback for an ipc shape that omits the field.
    readonly property var focusedClient: {
        void root._rev;
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < toplevels.length; ++i) {
            const data = toplevels[i] && toplevels[i].lastIpcObject;
            if (data && data.focusHistoryID === 0)
                return data;
        }
        const active = Hyprland.activeToplevel && Hyprland.activeToplevel.lastIpcObject;
        return active || null;
    }

    // True while some window holds focus; a bare desktop reads false, which the
    // dock surface uses to show itself when there is nothing to get out of.
    readonly property bool anyFocused: root.focusedClient !== null

    readonly property string activeClass: root.classOf(root.focusedClient)

    // Pinned first, then running-unpinned in pid order. Omit clients for live.
    function resolve(pinned, activeClients) {
        const p = (pinned === undefined || pinned === null) ? [] : Array.from(pinned);
        return DockList.resolve(p, activeClients === undefined ? root.clients : activeClients);
    }
    function pin(pinned, className) { return DockList.pin(pinned, className); }
    function unpin(pinned, className) { return DockList.unpin(pinned, className); }

    function countFor(className) {
        const list = root.clients;
        let n = 0;
        for (let i = 0; i < list.length; ++i)
            if (list[i].className === className) ++n;
        return n;
    }

    // Fallback pins so an empty dock is not mistaken for a missing one.
    function starterPins() {
        const out = [];
        for (const className of ["kitty", "chromium", "nautilus"])
            if (DesktopEntries.heuristicLookup(className)) out.push(className);
        return out;
    }

    // ── the dock store (shell.json top-level `dock`) ─────────────────────────
    // The dock is a first-class shell surface now, so its look and pins live in
    // one top-level store rather than per bar style. Every consumer reads and
    // writes it through here, so the copy-on-write below is the single path that
    // persists it.

    // The look registry, shaped like Theme.workspaceStyleOptions so one control
    // renders them all. Persisted under `dock.style` (default islands, so an
    // existing desktop is unchanged). A style only changes what the band draws.
    readonly property var styleOptions: [
        { key: "islands", label: "Islands", detail: "Split pills" },
        { key: "rail",    label: "Rail",    detail: "One continuous plate" },
        { key: "ledger",  label: "Ledger",  detail: "Numbered cells" },
        { key: "tanzaku", label: "Tanzaku", detail: "Hanging strips" },
        { key: "seal",    label: "Seal",    detail: "Colour means running" }
    ]
    function cfg(key, fallback) {
        const d = Config.dock;
        return (d && d[key] !== undefined && d[key] !== null) ? d[key] : fallback;
    }
    function setCfg(key, value) {
        const cur = Config.dock || {};
        const next = {};
        for (const k in cur) next[k] = cur[k];
        next[key] = value;
        // A fresh object so the live look changes this frame...
        Config.dock = next;
        // ...and a settings.patch so it survives: the shell's shell.json FileView
        // is read-only (no onAdapterUpdated), because the daemon owns that file and
        // serialises every writer through its settings store. Same channel Bar
        // Studio and the qsbar control centre write on.
        cfgCtl.queued += "call settings.patch " + JSON.stringify({ path: "dock", value: next }) + "\n";
        if (cfgCtl.connected)
            cfgCtl.flushQueued();
        else
            cfgCtl.connected = true;
    }
    function setPinned(array) { root.setCfg("pinned", array); }

    // The daemon's control socket, connected only when there is something to say.
    Socket {
        id: cfgCtl
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"
        property string queued: ""
        function flushQueued() {
            if (cfgCtl.queued.length === 0)
                return;
            cfgCtl.write(cfgCtl.queued);
            cfgCtl.flush();
            cfgCtl.queued = "";
        }
        onConnectionStateChanged: if (cfgCtl.connected) cfgCtl.flushQueued()
    }

    // The effective pin list: the user's order, or the starter set when empty, so
    // an unconfigured dock still shows something instead of reading as broken.
    function pinnedOrStarter() {
        const p = root.cfg("pinned", []);
        return (p && p.length) ? Array.from(p) : root.starterPins();
    }

    // Desktop-entry icon, then class-as-icon-name; "" so callers can fall back.
    function iconFor(className) {
        void root.iconRev;
        const desktop = DesktopEntries.heuristicLookup(className);
        const byEntry = (desktop && desktop.icon) ? Quickshell.iconPath(desktop.icon, true) : "";
        return byEntry !== "" ? byEntry : Quickshell.iconPath(String(className).toLowerCase(), true);
    }

    // No clients -> launch; focused already -> cycle by address; else focus,
    // preferring a client on the active workspace.
    function activate(className) {
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        const matches = [];
        for (let i = 0; i < toplevels.length; ++i) {
            const d = toplevels[i] && toplevels[i].lastIpcObject;
            if (d && root.classOf(d) === className && d.address)
                matches.push(d);
        }
        if (matches.length === 0) {
            const entry = DesktopEntries.heuristicLookup(className);
            if (entry)
                AppLaunch.run(entry, null);
            return;
        }
        matches.sort((a, b) => a.address < b.address ? -1 : (a.address > b.address ? 1 : 0));
        const active = Hyprland.activeToplevel && Hyprland.activeToplevel.lastIpcObject ? Hyprland.activeToplevel.lastIpcObject.address : "";
        const idx = matches.findIndex(m => m.address === active);
        let target;
        if (idx >= 0)
            target = matches[(idx + 1) % matches.length];
        else {
            const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
            target = matches.find(m => m.workspace && m.workspace.id === ws) || matches[0];
        }
        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + target.address + '" })');
    }

    // Close every window of a class (dock menu Close).
    function closeAll(className) {
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < toplevels.length; ++i) {
            const d = toplevels[i] && toplevels[i].lastIpcObject;
            if (d && root.classOf(d) === className && d.address)
                Hyprland.dispatch('closewindow address:' + d.address);
        }
    }

    // ── right-click context menu ───────────────────────────────────────────────
    // One menu at a time, owned by the monitor the click came from (menuScreen);
    // the per-monitor DockMenuOverlay renders it and dismisses on an outside click.
    property string menuClass: ""
    property bool menuPinned: false
    property int menuCount: 0
    property real menuGx: 0
    property real menuGy: 0
    property string menuScreen: ""
    property string menuEdge: "bottom"
    property real menuEdgeClear: 54
    readonly property bool menuOpen: root.menuClass !== ""
    function openMenu(className, pinned, count, gx, gy, screenName, edge, edgeClear) {
        root.menuClass = className;
        root.menuPinned = pinned;
        root.menuCount = count;
        root.menuGx = gx;
        root.menuGy = gy;
        root.menuScreen = screenName;
        root.menuEdge = edge;
        root.menuEdgeClear = edgeClear;
    }
    function closeMenu() { root.menuClass = ""; }
    function menuActOpen() {
        if (root.menuCount > 0) {
            const e = DesktopEntries.heuristicLookup(root.menuClass);
            if (e) AppLaunch.run(e, null);
        } else {
            root.activate(root.menuClass);
        }
        root.closeMenu();
    }
    function menuActPin() {
        const pins = root.pinnedOrStarter();
        root.setPinned(root.menuPinned ? root.unpin(pins, root.menuClass)
                                       : root.pin(pins, root.menuClass));
        root.closeMenu();
    }
    function menuActClose() {
        root.closeAll(root.menuClass);
        root.closeMenu();
    }
}
