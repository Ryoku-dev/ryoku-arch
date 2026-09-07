pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.FrameBars
import shell.services
import "../../stage/Singletons" as Stage

// The Edit shell layout session's model (docs/stage.md): the five surfaces the
// shell puts on a screen edge -- the Bar, the Dock, and the Quick settings,
// Theme and Wallpaper menus -- with each one's current edge and the edges it may
// legally take. Edges are written through the same seams the Hub uses: the Dock
// singleton for the dock, and a settings.patch over the daemon socket for the
// bar (qsbar.barPosition) and the frame menus (frameBars.menus.*.anchor), so the
// shell never fights the daemon for shell.json.
Singleton {
    id: root

    readonly property var surfaces: [
        { id: "bar", label: "Bar", kind: "bar" },
        { id: "dock", label: "Dock", kind: "dock" },
        { id: "quick-settings", label: "Quick settings", kind: "menu" },
        { id: "theme", label: "Theme", kind: "menu" },
        { id: "wallpaper", label: "Wallpaper", kind: "menu" }
    ]

    function _primary(a) {
        const s = "" + a;
        if (s.indexOf("top") === 0) return "top";
        if (s.indexOf("bottom") === 0) return "bottom";
        return s === "left" || s === "right" ? s : "top";
    }
    function _barEdge() {
        return (Config.qsbar && Config.qsbar.barPosition === "bottom") ? "bottom" : "top";
    }

    // The current edge a surface sits on (the dock's "auto" resolves to the edge
    // opposite the bar, matching DockSurface).
    function edgeOf(id) {
        if (id === "bar")
            return root._barEdge();
        if (id === "dock") {
            const e = Dock.cfg("edge", "auto");
            if (e === "top" || e === "bottom" || e === "left" || e === "right")
                return e;
            return root._barEdge() === "bottom" ? "top" : "bottom";
        }
        const m = (Config.frameBars && Config.frameBars.menus) ? Config.frameBars.menus[id] : null;
        return root._primary(m ? m.anchor : "top");
    }
    // The edges a surface may take: the bar is top/bottom only; everything else
    // takes all four.
    function legalEdges(id) {
        return id === "bar" ? ["top", "bottom"] : ["top", "bottom", "left", "right"];
    }

    // How many earlier surfaces share this one's current edge, so outlines that
    // land on the same edge stack instead of hiding one another.
    function orderOnEdge(id) {
        const e = root.edgeOf(id);
        let n = 0;
        for (let i = 0; i < root.surfaces.length; i++) {
            const s = root.surfaces[i];
            if (s.id === id) break;
            if (root.edgeOf(s.id) === e) n++;
        }
        return n;
    }

    function setEdge(id, edge) {
        if (root.legalEdges(id).indexOf(edge) < 0)
            return;
        if (id === "bar") {
            const q = {};
            const cur = Config.qsbar || {};
            for (const k in cur) q[k] = cur[k];
            q.barPosition = edge;
            Config.qsbar = q;
            root._patch("qsbar", q);
        } else if (id === "dock") {
            Dock.setCfg("edge", edge);
        } else {
            const next = FrameBars.setMenu(Config.frameBars, id, { anchor: edge }, MenuCatalog);
            Config.frameBars = next;
            root._patch("frameBars", next);
        }
        Stage.StageSession.markDirty();
    }

    // --- Reset: restore the edges every surface had when the session opened ----
    property var _snap: null
    function _capture() {
        const s = {};
        s["bar"] = (Config.qsbar && Config.qsbar.barPosition === "bottom") ? "bottom" : "top";
        s["dock"] = Dock.cfg("edge", "auto");
        const menus = (Config.frameBars && Config.frameBars.menus) ? Config.frameBars.menus : {};
        s["quick-settings"] = (menus["quick-settings"] || {}).anchor || "left";
        s["theme"] = (menus["theme"] || {}).anchor || "right";
        s["wallpaper"] = (menus["wallpaper"] || {}).anchor || "bottom";
        root._snap = s;
    }
    function _restore() {
        if (!root._snap)
            return;
        const s = root._snap;
        const q = {};
        const cur = Config.qsbar || {};
        for (const k in cur) q[k] = cur[k];
        q.barPosition = s["bar"];
        Config.qsbar = q;
        root._patch("qsbar", q);
        Dock.setCfg("edge", s["dock"]);
        let fb = Config.frameBars;
        fb = FrameBars.setMenu(fb, "quick-settings", { anchor: s["quick-settings"] }, MenuCatalog);
        fb = FrameBars.setMenu(fb, "theme", { anchor: s["theme"] }, MenuCatalog);
        fb = FrameBars.setMenu(fb, "wallpaper", { anchor: s["wallpaper"] }, MenuCatalog);
        Config.frameBars = fb;
        root._patch("frameBars", fb);
    }

    Connections {
        target: Stage.StageSession
        function onModeChanged() {
            if (Stage.StageSession.mode === "layout")
                root._capture();
        }
        function onResetRequested() { root._restore(); }
    }

    // The daemon owns shell.json and serialises every writer, so a change reaches
    // it as a settings.patch over the control socket -- the Dock/Bar Studio seam.
    function _patch(path, value) {
        patchCtl.queued += "call settings.patch " + JSON.stringify({ path: path, value: value }) + "\n";
        if (patchCtl.connected)
            patchCtl.flushQueued();
        else
            patchCtl.connected = true;
    }
    Socket {
        id: patchCtl
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"
        property string queued: ""
        function flushQueued() {
            if (patchCtl.queued.length === 0)
                return;
            patchCtl.write(patchCtl.queued);
            patchCtl.flush();
            patchCtl.queued = "";
        }
        onConnectionStateChanged: if (patchCtl.connected) patchCtl.flushQueued()
    }
}
