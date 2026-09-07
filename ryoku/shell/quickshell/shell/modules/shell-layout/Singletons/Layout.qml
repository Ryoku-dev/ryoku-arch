pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.FrameBars
import shell.services
import "../../stage/Singletons" as Stage

// The Edit shell model (docs/stage.md): the shell surfaces a user places on a
// screen edge (the Bar, the Dock, and the Quick settings, Theme, Wallpaper and
// Weather menus) with each one's edge, plus the read/write seams the ribbon
// drives -- the qsbar object, the Dock store, and frameBars.menus -- all through
// the same settings.patch the Hub uses, so the shell never fights the daemon for
// shell.json. It also owns the session's Reset: on enter it snapshots everything
// the tabs can touch (qsbar, dock, menus, the stage.json look/motion, the effect
// and per-layer front/depth), and on resetRequested puts all of it back (never
// the cut-outs themselves).
Singleton {
    id: root

    // The five edge surfaces, plus Weather (a fourth edge menu). `kind` groups
    // them for the canvas; the id is the shared StageSession.selected value.
    readonly property var surfaces: [
        { id: "bar", label: "Bar", kind: "bar" },
        { id: "dock", label: "Dock", kind: "dock" },
        { id: "quick-settings", label: "Quick settings", kind: "menu" },
        { id: "theme", label: "Theme", kind: "menu" },
        { id: "wallpaper", label: "Wallpaper", kind: "menu" },
        { id: "weather", label: "Weather", kind: "menu" }
    ]
    readonly property var menuIds: ["quick-settings", "theme", "wallpaper", "weather"]

    function _clone(o) {
        const out = {};
        const src = o || {};
        for (const k in src)
            out[k] = src[k];
        return out;
    }

    // ── the qsbar object seam ────────────────────────────────────────────────
    // The bar's whole look lives in one shell.json object (`qsbar`); a change
    // clones it, sets the one key, applies it live (Config.qsbar) and persists it
    // (settings.patch), the exact seam Bar Studio and the qsbar control centre
    // use. Defaults mirror the qsbar Theme so a key absent from a fresh file
    // still reads sensibly.
    function barGet(key, fallback) {
        const q = Config.qsbar || {};
        return (q[key] !== undefined && q[key] !== null) ? q[key] : fallback;
    }
    function setBar(key, value) {
        const q = root._clone(Config.qsbar);
        q[key] = value;
        Config.qsbar = q;
        root._patch("qsbar", q);
        Stage.StageSession.markDirty();
    }
    // The persisted { version, left, center, right } layout document, or an empty
    // one, always the three lanes so the modules panel can bind them directly.
    function _arr(a) {
        // JsonAdapter var arrays arrive as QVariantList, which Array.isArray
        // rejects and .slice() may not have, so copy by index into a real array.
        const out = [];
        if (a && a.length !== undefined)
            for (let i = 0; i < a.length; i++)
                out.push(a[i]);
        return out;
    }
    function barLayout() {
        const l = root.barGet("layout", null);
        return {
            version: 1,
            left: l ? root._arr(l.left) : [],
            center: l ? root._arr(l.center) : [],
            right: l ? root._arr(l.right) : []
        };
    }
    function setBarLayout(next) {
        root.setBar("layout", {
            version: 1,
            left: next.left || [], center: next.center || [], right: next.right || []
        });
    }

    // ── edges ────────────────────────────────────────────────────────────────
    function _primary(a) {
        const s = "" + a;
        if (s.indexOf("top") === 0) return "top";
        if (s.indexOf("bottom") === 0) return "bottom";
        return s === "left" || s === "right" ? s : "top";
    }
    function _barEdge() { return root.barGet("barPosition", "top") === "bottom" ? "bottom" : "top"; }

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
    function legalEdges(id) {
        return id === "bar" ? ["top", "bottom"] : ["top", "bottom", "left", "right"];
    }
    // Peers already on this surface's edge, so canvas outlines stack instead of
    // hiding one another.
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
            root.setBar("barPosition", edge);
        } else if (id === "dock") {
            Dock.setCfg("edge", edge);
            Stage.StageSession.markDirty();
        } else {
            root.setMenuAnchor(id, edge);
        }
    }

    // ── menus (frameBars.menus.<id>) ─────────────────────────────────────────
    // FrameBars.setMenu rebuilds the whole entry from the value it is handed
    // (missing keys fall to the catalogue default), so every write passes the
    // menu's FULL current state with just the one field changed; otherwise an
    // edge change would reset the width and back again.
    function _menu(id) {
        const menus = Config.normalizedFrameBars ? Config.normalizedFrameBars.menus : null;
        return (menus && menus[id]) ? menus[id] : {};
    }
    function menuAnchor(id) { return root._primary(root._menu(id).anchor); }
    function menuExpansion(id) { return root._menu(id).expansion === "never" ? "never" : "always"; }
    function menuWidth(id) {
        const w = root._menu(id).minWidth;
        return (typeof w === "number" && isFinite(w)) ? w : 320;
    }
    // The menu's current full value (anchor kept raw so a corner anchor is not
    // flattened by an unrelated edit), with `patch` applied over it.
    function _menuValue(id, patch) {
        const m = root._menu(id);
        const out = {
            anchor: (typeof m.anchor === "string" && m.anchor.length) ? m.anchor : "top",
            minWidth: (typeof m.minWidth === "number" && isFinite(m.minWidth)) ? m.minWidth : 320,
            expansion: m.expansion === "never" ? "never" : "always"
        };
        if (m.widgets) out.widgets = root._arr(m.widgets);
        if (id === "quick-settings" && m.modules) out.modules = root._arr(m.modules);
        for (const k in patch) out[k] = patch[k];
        return out;
    }
    // Setting a menu's edge swaps any menu already parked there onto this one's
    // old edge, so two menus never silently stack (docs/stage.md).
    function setMenuAnchor(id, edge) {
        const prev = root.menuAnchor(id);
        if (prev === edge)
            return;
        let swapId = "";
        for (let i = 0; i < root.menuIds.length; i++) {
            const other = root.menuIds[i];
            if (other !== id && root.menuAnchor(other) === edge) { swapId = other; break; }
        }
        let fb = Config.frameBars;
        if (swapId !== "")
            fb = FrameBars.setMenu(fb, swapId, root._menuValue(swapId, { anchor: prev }), MenuCatalog);
        fb = FrameBars.setMenu(fb, id, root._menuValue(id, { anchor: edge }), MenuCatalog);
        Config.frameBars = fb;
        root._patch("frameBars", fb);
        Stage.StageSession.markDirty();
    }
    function _setMenu(id, patch) {
        const fb = FrameBars.setMenu(Config.frameBars, id, root._menuValue(id, patch), MenuCatalog);
        Config.frameBars = fb;
        root._patch("frameBars", fb);
        Stage.StageSession.markDirty();
    }
    function setMenuExpansion(id, mode) { root._setMenu(id, { expansion: mode === "never" ? "never" : "always" }); }
    function setMenuWidth(id, w) { root._setMenu(id, { minWidth: Math.max(1, Math.round(w)) }); }

    // ── Reset: snapshot on enter, restore on request (never the cut-outs) ──────
    property var _snap: null
    function _capture() {
        const sb = Stage.StageBackend;
        const cfg = Stage.Config;
        const wall = sb.current;
        const ls = sb.layersFor(wall);
        const layers = [];
        for (let i = 0; i < ls.length; i++)
            layers.push({ front: sb.layerFront(wall, i), depth: sb.layerDepth(wall, i) });
        root._snap = {
            qsbar: root._clone(Config.qsbar),
            dock: root._clone(Config.dock),
            frameBars: JSON.parse(JSON.stringify(Config.frameBars || {})),
            edge: cfg.edge, shadow: cfg.shadow, shadowAngle: cfg.shadowAngle,
            motion: root._clone(cfg.motion), quality: cfg.quality,
            wall: wall, effect: sb.effectFor(wall), layers: layers
        };
    }
    function _restore() {
        if (!root._snap)
            return;
        const s = root._snap;
        const cfg = Stage.Config;
        const sb = Stage.StageBackend;

        Config.qsbar = root._clone(s.qsbar);
        root._patch("qsbar", Config.qsbar);
        Config.dock = root._clone(s.dock);
        root._patch("dock", Config.dock);
        Config.frameBars = JSON.parse(JSON.stringify(s.frameBars));
        root._patch("frameBars", Config.frameBars);

        cfg.setEdge(s.edge);
        cfg.setShadow(s.shadow);
        cfg.setShadowAngle(s.shadowAngle);
        const m = s.motion || {};
        cfg.setAmount(m.amount || "normal");
        cfg.setIdle(m.idle || "none");
        cfg.setMusic(m.music === true);
        cfg.setMouse(m.mouse === true);
        cfg.setSensitivity(typeof m.sensitivity === "number" ? m.sensitivity : 1.0);
        cfg.setRange(typeof m.range === "number" ? m.range : 1.0);
        cfg.setBackdrop(typeof m.backdrop === "number" ? m.backdrop : 1.0);
        cfg.setQuality(s.quality);

        sb.setEffect(s.effect);
        for (let i = 0; i < s.layers.length; i++)
            sb.setLayer(i, { front: s.layers[i].front, depth: s.layers[i].depth });
    }

    Connections {
        target: Stage.StageSession
        function onModeChanged() {
            if (Stage.StageSession.mode === "shell")
                root._capture();
        }
        function onResetRequested() { root._restore(); }
    }

    // The daemon owns shell.json and serialises every writer, so a change reaches
    // it as a settings.patch over the control socket (the Dock/Bar Studio seam).
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
