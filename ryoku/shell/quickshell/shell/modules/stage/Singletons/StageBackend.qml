pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// The single door to the daemon `stage` topic and the `ryostage` engine
// (docs/stage.md). It subscribes once to the coalesced, per-wallpaper-keyed
// frame the daemon publishes, folds the global look from Config into each
// layer's knobs, and turns every editor gesture into a `ryoku-shell stage`
// intent. Engine provisioning (check / models / install / remove) reads the
// `ryostage` helper directly, since those are not daemon verbs. No polling: the
// frame is the sole source of render + status truth.
Singleton {
    id: root

    // ── engine helper ─────────────────────────────────────────────────
    readonly property string bin: {
        const d = Quickshell.env("RYOKU_SHELL_DIR");
        return (d && d.length > 0) ? d + "/scripts/ryostage" : "ryostage";
    }
    property bool available: false
    property bool checked: false
    property bool installing: false
    property bool removing: false
    // Full curated catalogue objects: {id,tier,label,size,installed,licence,upstream}.
    property var models: []
    property string progress: ""

    function recheck() { checkProc.running = false; checkProc.running = true; }
    function install(model) {
        if (root.installing) return;
        root.installing = true;
        root.progress = "";
        installProc.command = (model && model.length > 0) ? [root.bin, "install", model] : [root.bin, "install"];
        installProc.running = false;
        installProc.running = true;
    }
    function remove(model) {
        if (root.removing || root.installing || !model || model.length === 0) return;
        root.removing = true;
        root.progress = "";
        removeProc.command = [root.bin, "remove", model];
        removeProc.running = false;
        removeProc.running = true;
    }
    function modelById(id) {
        const m = root.models || [];
        for (var i = 0; i < m.length; i++) if (m[i].id === id) return m[i];
        return null;
    }
    function modelByTier(tier) {
        const m = root.models || [];
        for (var i = 0; i < m.length; i++) if (m[i].tier === tier) return m[i];
        return null;
    }
    // Draft and Standard share the draft-tier model (u2netp); Fine needs the
    // fine-tier weights. Returns the catalogue entry a quality tier requires.
    function modelForQuality(q) {
        return q === "fine" ? root.modelByTier("fine") : root.modelByTier("draft");
    }
    function qualityInstalled(q) {
        const m = root.modelForQuality(q);
        return !!(m && m.installed === true);
    }
    // Open ~/Pictures/Stage/<stem> for the wallpaper (its artifact folder).
    function openFolder(wallPath) {
        const p = wallPath || root.current;
        const stem = root._stemFor(p);
        const folder = (Quickshell.env("HOME") || "") + "/Pictures/Stage" + (stem ? "/" + stem : "");
        openProc.command = ["sh", "-c",
            "mkdir -p \"$1\" && (nautilus \"$1\" 2>/dev/null || gio open \"$1\" 2>/dev/null || xdg-open \"$1\")",
            "sh", folder];
        openProc.running = false;
        openProc.running = true;
    }

    Process {
        id: checkProc
        command: [root.bin, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = ("" + this.text).trim() === "available";
                if (root.available)
                    modelsProc.running = true;
                else
                    root.checked = true;
            }
        }
    }
    Process {
        id: modelsProc
        command: [root.bin, "models", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(("" + this.text).trim() || "[]");
                    root.models = Array.isArray(arr) ? arr : [];
                } catch (e) {
                    root.models = [];
                }
                root.checked = true;
            }
        }
    }
    Process {
        id: installProc
        stdout: SplitParser { onRead: line => root.progress = line }
        stderr: SplitParser { onRead: line => root.progress = line }
        onExited: { root.installing = false; root.recheck(); }
    }
    Process {
        id: removeProc
        stdout: SplitParser { onRead: line => root.progress = line }
        stderr: SplitParser { onRead: line => root.progress = line }
        onExited: { root.removing = false; root.recheck(); }
    }
    Process { id: openProc }

    // ── daemon `stage` topic ──────────────────────────────────────────
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"
    property var frame: ({ current: "", busy: false, stage: "", percent: 0, walls: {} })

    readonly property string current: root.frame.current || ""
    readonly property bool busy: root.frame.busy === true
    readonly property string stage: root.frame.stage || ""
    readonly property int percent: (typeof root.frame.percent === "number") ? root.frame.percent : 0

    // Optimistic per-layer overlay so a drag on the current wall's knobs shows
    // instantly instead of waiting for the intent to round-trip through the
    // daemon and republish. Keyed by "<path>|<index>".
    property var _opt: ({})

    function apply(line) {
        var f;
        try {
            f = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!f || typeof f !== "object") return;
        if (!f.walls) f.walls = {};
        root.frame = f;
        // Drop optimistic entries for walls that are no longer current; the
        // active editor only ever touches the current wall.
        const keep = {};
        const cur = f.current || "";
        for (const k in root._opt)
            if (k.indexOf(cur + "|") === 0) keep[k] = root._opt[k];
        root._opt = keep;
    }

    // Transient per-monitor cursor (-1..1), shared so a screen's parallax bands
    // drift in lockstep with its StageBackground. Not persisted; one pair per
    // output keeps two monitors from fighting over the value.
    property var _cursor: ({})
    function setCursor(name, nx, ny) {
        const next = {};
        for (const k in root._cursor) next[k] = root._cursor[k];
        next[name] = { nx: nx, ny: ny };
        root._cursor = next;
    }
    function cursorNXFor(name) { const e = root._cursor && root._cursor[name]; return e ? e.nx : 0; }
    function cursorNYFor(name) { const e = root._cursor && root._cursor[name]; return e ? e.ny : 0; }

    // ── per-wall lookups (each monitor reads its own wallpaper path) ───
    function wallOf(path) { return (path && root.frame.walls) ? (root.frame.walls[path] || null) : null; }
    function effectFor(path) { const w = root.wallOf(path); return w && w.effect ? w.effect : "off"; }
    function modeFor(path) { const w = root.wallOf(path); return w && w.mode ? w.mode : "auto"; }
    function layersFor(path) { const w = root.wallOf(path); return (w && w.layers) ? w.layers : []; }
    function subjectFor(path) { const w = root.wallOf(path); return (w && w.subject) ? w.subject : ""; }
    function backgroundFor(path) { const w = root.wallOf(path); return (w && w.background) ? w.background : ""; }
    function layerCountFor(path) { return root.layersFor(path).length; }
    // Active = an effect is on and there is at least one cut layer to draw.
    function isActiveFor(path) { return root.effectFor(path) !== "off" && root.layerCountFor(path) > 0; }
    function isParallaxFor(path) { return root.effectFor(path) === "parallax" && root.layerCountFor(path) > 0; }
    function isSubjectFor(path) { return root.effectFor(path) === "subject" && root.layerCountFor(path) > 0; }

    function layerUrlFor(path, i) {
        const ls = root.layersFor(path);
        if (i < 0 || i >= ls.length || !ls[i] || !ls[i].out) return "";
        return "file://" + ls[i].out + "?v=" + (ls[i].rev || 0);
    }
    function backgroundUrlFor(path) {
        const bg = root.backgroundFor(path);
        if (bg === "") return "";
        const w = root.wallOf(path);
        return "file://" + bg + "?v=" + (w && w.rev ? w.rev : 0);
    }

    // Current-wall convenience for the sidebar panel.
    readonly property var wall: root.wallOf(root.current)
    readonly property string effect: root.effectFor(root.current)
    readonly property string mode: root.modeFor(root.current)
    readonly property var layers: root.layersFor(root.current)
    readonly property int layerCount: root.layers.length
    readonly property string subject: root.subjectFor(root.current)
    readonly property string background: root.backgroundFor(root.current)

    // ── per-layer knobs, folding the global look for inherited fields ──
    // Merged raw layer object (frame ∪ optimistic overlay); callers fold the
    // global look for the inherited fields via layer*(…, inherit).
    function layerData(path, i) { return root._raw(path, i); }
    function _raw(path, i) {
        const opt = root._opt[path + "|" + i];
        const ls = root.layersFor(path);
        const base = (i >= 0 && i < ls.length && ls[i]) ? ls[i] : {};
        if (!opt) return base;
        const out = {};
        for (const k in base) out[k] = base[k];
        for (const k in opt) out[k] = opt[k];
        return out;
    }
    function _num(v, def) { return (typeof v === "number") ? v : def; }
    // feather/lift/shadow/shadowAngle inherit the caller's global look (Config)
    // when the layer has no own value; StageBackend stays free of Config so the
    // singletons don't cross-reference.
    function layerFeather(path, i, inherit) { return root._num(root._raw(path, i).feather, inherit); }
    function layerLift(path, i, inherit) { return root._num(root._raw(path, i).lift, inherit); }
    function layerShadow(path, i, inherit) { return root._num(root._raw(path, i).shadow, inherit); }
    function layerShadowAngle(path, i, inherit) { return root._num(root._raw(path, i).shadowAngle, inherit); }
    function layerEnabled(path, i) { return root._raw(path, i).enabled !== false; }
    function layerOpacity(path, i) { return root._num(root._raw(path, i).opacity, 1); }
    function layerParallax(path, i) { return root._num(root._raw(path, i).parallax, 1); }
    function layerDepthFactor(path, i) { return root._num(root._raw(path, i).depthFactor, 0.5); }
    function layerOffsetX(path, i) { return root._num(root._raw(path, i).offsetX, 0); }
    function layerOffsetY(path, i) { return root._num(root._raw(path, i).offsetY, 0); }
    function layerMouseMax(path, i) { return root._num(root._raw(path, i).mouseMax, 32); }
    function layerAudioLevel(path, i) { return root._num(root._raw(path, i).audioLevel, 0); }
    function layerAnimType(path, i) { const t = root._raw(path, i).animType; return (typeof t === "string") ? t : "none"; }
    function layerAnimSpeed(path, i) { return root._num(root._raw(path, i).animSpeed, 0.5); }
    function layerAnimAmplitude(path, i) { return root._num(root._raw(path, i).animAmplitude, 10); }
    function layerLabel(path, i) {
        const l = root._raw(path, i);
        const lbl = (typeof l.label === "string" && l.label.length) ? l.label : "";
        if (lbl) return lbl.charAt(0).toUpperCase() + lbl.slice(1);
        return I18n.tr("Layer %1").arg(i + 1);
    }
    function layerPathName(path, i) {
        const out = root._raw(path, i).out || "";
        return out.split("/").pop();
    }
    function layerOut(path, i) { return root._raw(path, i).out || ""; }

    // ── scene z (per path), matching the parallax interleave ──────────
    readonly property var builtinWidgetIds: ["clock", "calendar", "music", "aio", "stats", "weather", "notes"]
    function defaultSceneFor(path) {
        const out = ["wallpaper"];
        const n = root.layerCountFor(path);
        for (var i = 1; i <= n; i++) out.push("layer:" + i);
        for (const w of root.builtinWidgetIds) out.push("widget:" + w);
        out.push("visualizer");
        return out;
    }
    function effectiveSceneFor(path) {
        const w = root.wallOf(path);
        const s = (w && w.scene && w.scene.length) ? w.scene : [];
        return s.length ? s : root.defaultSceneFor(path);
    }
    function sceneIndexOfFor(path, name) { return root.effectiveSceneFor(path).indexOf(name); }
    function sceneZFor(path, name) {
        const i = root.sceneIndexOfFor(path, name);
        return i < 0 ? 0 : i * 2 + 1;
    }
    function sceneGapZFor(path) {
        const s = root.effectiveSceneFor(path);
        for (var i = s.length - 1; i >= 0; i--)
            if (s[i].indexOf("layer:") === 0) return i * 2 + 1.5;
        return 1;
    }
    function widgetZFor(path, id) {
        const i = root.sceneIndexOfFor(path, "widget:" + id);
        return i >= 0 ? i * 2 + 2 : root.sceneGapZFor(path);
    }

    function _stemFor(path) {
        if (!path) return "";
        const base = path.split("/").pop();
        return base.replace(/\.[^.]+$/, "");
    }

    // ── verbs (fire-and-forget; the topic republish is the confirmation) ─
    function call(verb) {
        const cmd = ["ryoku-shell", "stage", verb];
        for (var i = 1; i < arguments.length; i++) cmd.push("" + arguments[i]);
        Quickshell.execDetached(cmd);
    }
    function setEffect(e) { root.call("set-effect", e); }
    function setMode(m) { root.call("set-mode", m); }
    function refresh() { root.call("refresh"); }
    function cancel() { root.call("cancel"); }
    function setScene(arr) { root.call("set-scene", JSON.stringify(arr || [])); }
    function addLayer(p) { root.call("add-layer", p); }
    function removeLayer(p) { root.call("remove-layer", p); }
    function clear() { root.call("clear"); }
    // Per-layer knob edits coalesce: the optimistic overlay shows the value now,
    // one settle flush sends the merged JSON so a drag is a single intent, not
    // one per pixel.
    property var _pending: ({})
    function setLayer(i, obj) {
        const path = root.current;
        if (!path) return;
        const key = path + "|" + i;
        const cur = root._opt[key] || {};
        const merged = {};
        for (const k in cur) merged[k] = cur[k];
        for (const k in obj) merged[k] = obj[k];
        const opt = {};
        for (const k in root._opt) opt[k] = root._opt[k];
        opt[key] = merged;
        root._opt = opt;
        root._pending[i] = merged;
        layerSettle.restart();
    }
    function toggleLayerEnabled(i) { root.setLayer(i, { enabled: !root.layerEnabled(root.current, i) }); }
    Timer {
        id: layerSettle
        interval: 300
        onTriggered: {
            for (const i in root._pending)
                root.call("set-layer", i, JSON.stringify(root._pending[i]));
            root._pending = {};
        }
    }

    Socket {
        id: sub
        path: root.sockPath
        parser: SplitParser { onRead: line => root.apply(line) }
        Component.onCompleted: connected = true
        onConnectionStateChanged: {
            if (connected) {
                write("subscribe stage\n");
                flush();
            } else {
                retry.restart();
            }
        }
    }
    Timer {
        id: retry
        interval: 2000
        onTriggered: if (!sub.connected) sub.connected = true
    }

    Component.onCompleted: root.recheck()
}
