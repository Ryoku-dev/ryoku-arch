pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "../Singletons"

// Animations, ported to the monochrome instrument. The Hyprland animation tree
// (read once via `hyprctl animations -j`) plus a bezier curve editor; per-leaf
// overrides and user curves persist through the shell's hypr store, which
// previews them live on the desktop and restores on revert.
//
// The shell owns the rail, side panel (preview/state/diff), the action bar
// (Save/Revert/Reset read the same hub.dirty/diff this page feeds) and the
// live preview. This page is pure: it owns only the content region (the global
// switch, the focus flash group, the curve editor, the animation table) and
// edits the draft through hub.hyprEdit. It never previews, restores or writes.
Item {
    id: pg
    property var hub

    // ── store shortcuts (reactive: reading hyprDraft/hyprCommitted inside a
    // binding tracks them, so cells refresh on edit/save/revert) ────────────
    function hv(path) { return pg.hub ? pg.hub.hyprVal(path) : undefined }
    function cv(path) { return pg.hub ? pg.hub.hyprCommittedVal(path) : undefined }
    function he(path, v) { if (pg.hub) pg.hub.hyprEdit(path, v) }
    function chg(path) { return JSON.stringify(pg.hv(path)) !== JSON.stringify(pg.cv(path)) }
    function cap(s) { s = String(s); return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    // ── the live animation tree, read once at construction ──────────────────
    property var liveAnims: []
    property var liveCurves: []
    property string selectedCurve: ""

    // theme.motion in shell.json, written instantly through the settings seam
    // (not the staged hypr draft); the shell's ui tokens read the same keys.
    readonly property real motionScale: { Settings.revision; var v = Settings.get("theme.motion.scale"); return (typeof v === "number" && v > 0) ? v : 1.0; }
    readonly property bool reduceMotion: { Settings.revision; return Settings.get("theme.motion.reduce") === true; }
    readonly property string motionScaleLabel: Math.round(pg.motionScale * 100) + "%"
    function setMotion(key, v) { Settings.patch("theme.motion." + key, v); }

    Process {
        id: animProc
        command: ["hyprctl", "animations", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    pg.liveAnims = (d[0] || []).filter(function (a) { return a.overridden && a.name.indexOf("__") !== 0; });
                    pg.liveCurves = d[1] || [];
                    if (pg.selectedCurve === "" && pg.liveCurves.length > 0)
                        pg.selectedCurve = pg.liveCurves[0].name;
                } catch (e) {
                    console.log("hub: animations parse failed: " + e);
                }
            }
        }
    }

    // Hyprland animation personality: the preset the loader picks. Read from the
    // backend at load; setAnimPreset writes ~/.config/ryoku/anim-preset + reloads.
    property string animPreset: "ryoku"
    readonly property var animPresets: [
        { "id": "ryoku", "label": "Ryoku" },
        { "id": "dusky", "label": "Dusky" },
        { "id": "bounce", "label": "Bounce" },
        { "id": "fade", "label": "Fade" },
        { "id": "fast", "label": "Fast" },
        { "id": "mechanical", "label": "Mechanical" },
        { "id": "minimal", "label": "Minimal" },
        { "id": "air", "label": "Air" },
        { "id": "slowmotion", "label": "Slow-mo" },
        { "id": "exaggerated", "label": "Exaggerated" },
        { "id": "hallucination", "label": "Hallucination" },
        { "id": "rage", "label": "Rage" },
        { "id": "disable", "label": "Off" }
    ]
    readonly property var animPresetLabels: pg.animPresets.map(p => p.label)
    function animPresetLabel(id) { for (var i = 0; i < pg.animPresets.length; i++) if (pg.animPresets[i].id === id) return pg.animPresets[i].label; return "Ryoku"; }
    function animPresetId(label) { for (var i = 0; i < pg.animPresets.length; i++) if (pg.animPresets[i].label === label) return pg.animPresets[i].id; return "ryoku"; }
    function setAnimPreset(id) { pg.animPreset = id; animPresetSet.command = ["ryoku-hub", "hypr", "anim-preset", id]; animPresetSet.running = true; }

    Process {
        id: animPresetGet
        command: ["ryoku-hub", "hypr", "anim-preset"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { var d = JSON.parse(this.text); if (d && d.preset) pg.animPreset = d.preset; } catch (e) {} } }
    }
    Process { id: animPresetSet }

    // ── curves model ────────────────────────────────────────────────────────
    function curvesArr() { var a = pg.hv("anim.curves"); return Array.isArray(a) ? a : []; }
    function itemsArr() { var a = pg.hv("anim.items"); return Array.isArray(a) ? a : []; }

    function curveNames() {
        var seen = ({}), out = [];
        for (var i = 0; i < pg.liveCurves.length; i++) {
            var n = pg.liveCurves[i].name;
            if (!seen[n]) { seen[n] = true; out.push(n); }
        }
        var cs = pg.curvesArr();
        for (var j = 0; j < cs.length; j++) {
            var m = cs[j].name;
            if (!seen[m]) { seen[m] = true; out.push(m); }
        }
        return out;
    }
    function curveOf(name) {
        var cs = pg.curvesArr();
        for (var i = 0; i < cs.length; i++)
            if (cs[i].name === name)
                return cs[i];
        // live curves report capital X0/Y0/X1/Y1; overrides store lowercase.
        for (var j = 0; j < pg.liveCurves.length; j++)
            if (pg.liveCurves[j].name === name)
                return { "name": name, "x0": pg.liveCurves[j].X0, "y0": pg.liveCurves[j].Y0, "x1": pg.liveCurves[j].X1, "y1": pg.liveCurves[j].Y1 };
        return { "name": name, "x0": 0.25, "y0": 0.1, "x1": 0.25, "y1": 1 };
    }
    readonly property bool selectedIsCustom: {
        for (var i = 0; i < pg.liveCurves.length; i++)
            if (pg.liveCurves[i].name === pg.selectedCurve)
                return false;
        return pg.selectedCurve !== "";
    }
    readonly property bool selectedHasOverride: {
        var cs = pg.curvesArr();
        for (var i = 0; i < cs.length; i++)
            if (cs[i].name === pg.selectedCurve)
                return true;
        return false;
    }
    function upsertCurve(name, x0, y0, x1, y1) {
        if (name === "")
            return;
        var arr = pg.curvesArr().slice(), found = false;
        for (var i = 0; i < arr.length; i++)
            if (arr[i].name === name) {
                arr[i] = { "name": name, "x0": x0, "y0": y0, "x1": x1, "y1": y1 };
                found = true;
                break;
            }
        if (!found)
            arr.push({ "name": name, "x0": x0, "y0": y0, "x1": x1, "y1": y1 });
        pg.he("anim.curves", arr);
    }
    function resetCurve(name) {
        var arr = [], cs = pg.curvesArr();
        for (var i = 0; i < cs.length; i++)
            if (cs[i].name !== name)
                arr.push(cs[i]);
        pg.he("anim.curves", arr);
        if (pg.selectedIsCustom && pg.liveCurves.length > 0)
            pg.selectedCurve = pg.liveCurves[0].name;
    }
    function addCurve() {
        var n = 1, name = "custom", names = pg.curveNames();
        while (names.indexOf(name) >= 0) { name = "custom" + n; n++; }
        pg.upsertCurve(name, 0.25, 0.1, 0.25, 1);
        pg.selectedCurve = name;
    }

    // named feels: one-tap curve shapes, friendlier than dragging handles.
    readonly property var feels: [
        { "name": "Linear", "c": [0.0, 0.0, 1.0, 1.0] },
        { "name": "Gentle", "c": [0.45, 0.0, 0.25, 1.0] },
        { "name": "Smooth", "c": [0.25, 0.1, 0.25, 1.0] },
        { "name": "Snappy", "c": [0.3, 0.0, 0.1, 1.0] },
        { "name": "Bouncy", "c": [0.34, 1.5, 0.64, 1.0] }
    ]
    function feelActive(c) {
        var q = pg.curveOf(pg.selectedCurve);
        return Math.abs(q.x0 - c[0]) < 0.03 && Math.abs(q.y0 - c[1]) < 0.03
            && Math.abs(q.x1 - c[2]) < 0.03 && Math.abs(q.y1 - c[3]) < 0.03;
    }

    // ── per-leaf overrides ──────────────────────────────────────────────────
    function itemOf(leaf) {
        var items = pg.itemsArr();
        for (var i = 0; i < items.length; i++)
            if (items[i].leaf === leaf)
                return items[i];
        for (var j = 0; j < pg.liveAnims.length; j++)
            if (pg.liveAnims[j].name === leaf)
                return { "leaf": leaf, "enabled": pg.liveAnims[j].enabled, "speed": pg.liveAnims[j].speed, "bezier": pg.liveAnims[j].bezier, "style": pg.liveAnims[j].style };
        return { "leaf": leaf, "enabled": true, "speed": 1, "bezier": "", "style": "" };
    }
    function upsertItem(leaf, key, val) {
        var cur = pg.itemOf(leaf);
        var next = { "leaf": leaf, "enabled": cur.enabled, "speed": cur.speed, "bezier": cur.bezier, "style": cur.style };
        next[key] = val;
        var arr = pg.itemsArr().slice(), found = false;
        for (var i = 0; i < arr.length; i++)
            if (arr[i].leaf === leaf) { arr[i] = next; found = true; break; }
        if (!found)
            arr.push(next);
        pg.he("anim.items", arr);
    }
    // Hyprland style options are grouped by leaf family; keys are the config
    // literals, labels are the human reading.
    function styleOptionsFor(leaf) {
        if (leaf.indexOf("windows") === 0)
            return [{ "key": "", "label": I18n.tr("Default") }, { "key": "slide", "label": I18n.tr("Slide") }, { "key": "popin 80%", "label": I18n.tr("Pop in") }, { "key": "gnomed", "label": I18n.tr("Gnomed") }];
        if (leaf.indexOf("workspaces") === 0 || leaf.indexOf("specialWorkspace") === 0)
            return [{ "key": "", "label": I18n.tr("Default") }, { "key": "slide", "label": I18n.tr("Slide") }, { "key": "slidevert", "label": I18n.tr("Slide vertical") }, { "key": "fade", "label": I18n.tr("Fade") }, { "key": "slidefade", "label": I18n.tr("Slide + fade") }, { "key": "slidefadevert", "label": I18n.tr("Slide + fade vertical") }];
        if (leaf.indexOf("layers") === 0)
            return [{ "key": "", "label": I18n.tr("Default") }, { "key": "slide", "label": I18n.tr("Slide") }, { "key": "popin 90%", "label": I18n.tr("Pop in") }, { "key": "fade", "label": I18n.tr("Fade") }];
        return [];
    }

    // ── search integration ──────────────────────────────────────────────────
    readonly property string query: pg.hub ? (pg.hub.query || "") : ""
    function hit(s) { return pg.query === "" || String(s).toLowerCase().indexOf(pg.query.toLowerCase()) >= 0 }
    readonly property bool gVisible: pg.hit("global animations master switch desktop motion")
    readonly property bool fVisible: pg.hit("focus flash animate focused window style opacity bounce strength slide height")
    readonly property bool cVisible: pg.hit("feel motion smooth easing preset speed curves bezier curve editor control point handles " + pg.curveNames().join(" "))
    readonly property bool aVisible: {
        if (pg.query === "") return true;
        if (pg.hit("animations")) return true;
        for (var i = 0; i < pg.liveAnims.length; i++)
            if (String(pg.liveAnims[i].name).toLowerCase().indexOf(pg.query.toLowerCase()) >= 0)
                return true;
        return false;
    }
    readonly property bool anyVisible: pg.gVisible || pg.fVisible || pg.cVisible || pg.aVisible

    // ── the page-local catalogue overlay (curve + style + bezier pickers) ────
    // The shell's picker is wired to its JSON store, not the hypr store, so the
    // dropdowns here open this instead. Short lists, so no filter field.
    function openPicker(title, opts, current, cb) {
        var norm = [];
        for (var i = 0; i < opts.length; i++) {
            var o = opts[i];
            norm.push((typeof o === "string") ? { "key": o, "label": o } : o);
        }
        pk.title = title; pk.opts = norm; pk.current = current; pk.cb = cb;
    }
    function closePicker() { pk.opts = null; pk.cb = null; }
    function choosePick(key) { if (pk.cb) pk.cb(key); pg.closePicker(); }

    // ── inline components ────────────────────────────────────────────────────

    // a fractional stepper (speed is 0.1s units; the module Step is integer).
    component NumStep: Row {
        id: ns
        property real value: 1
        property real min: 0.1
        property real max: 10
        property real by: 0.1
        signal changed(real v)
        spacing: 0
        function clamp(v) { return Math.max(ns.min, Math.min(ns.max, Math.round(v * 10) / 10)); }
        Rectangle {
            readonly property bool spent: ns.value <= ns.min + 0.0001
            width: 29; height: Tokens.ctlH; radius: Tokens.radius
            opacity: spent ? 0.3 : 1
            color: mh.hovered && !spent ? Tokens.tint10 : "transparent"
            border.width: Tokens.border
            border.color: mh.hovered && !spent ? Tokens.lineStrong : Tokens.line
            Behavior on color { ColorAnimation { duration: Tokens.snap } }
            Text { anchors.centerIn: parent; text: "\u2212"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall }
            HoverHandler { id: mh; enabled: !parent.spent; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !parent.spent; onTapped: ns.changed(ns.clamp(ns.value - ns.by)) }
        }
        Text {
            width: 46; height: Tokens.ctlH
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: ns.value.toFixed(1); color: Tokens.ink; font.family: Tokens.mono; font.pixelSize: Tokens.fSmall
        }
        Rectangle {
            readonly property bool spent: ns.value >= ns.max - 0.0001
            width: 29; height: Tokens.ctlH; radius: Tokens.radius
            opacity: spent ? 0.3 : 1
            color: ph.hovered && !spent ? Tokens.tint10 : "transparent"
            border.width: Tokens.border
            border.color: ph.hovered && !spent ? Tokens.lineStrong : Tokens.line
            Behavior on color { ColorAnimation { duration: Tokens.snap } }
            Text { anchors.centerIn: parent; text: "+"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall }
            HoverHandler { id: ph; enabled: !parent.spent; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: !parent.spent; onTapped: ns.changed(ns.clamp(ns.value + ns.by)) }
        }
    }

    // a compact dropdown trigger. Emits activated() to open the overlay and
    // picked() when the overlay reports a choice.
    component MiniPick: Rectangle {
        id: mp
        property var opts: []
        property string current: ""
        property string ph: I18n.tr("select")
        property string heading: I18n.tr("Select")
        signal picked(string key)
        signal activated()
        width: 132; height: Tokens.ctlH; radius: Tokens.radius
        color: mph.hovered ? Tokens.tint10 : "transparent"
        border.width: Tokens.border
        border.color: mph.hovered ? Tokens.lineStrong : Tokens.line
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        function labelOf(k) {
            for (var i = 0; i < mp.opts.length; i++) {
                var o = mp.opts[i], kk = (typeof o === "string") ? o : o.key;
                if (kk === k) return (typeof o === "string") ? o : o.label;
            }
            return "";
        }
        readonly property string curLabel: mp.labelOf(mp.current)
        Text {
            anchors { left: parent.left; leftMargin: Tokens.s2; right: car.left; rightMargin: Tokens.s1; verticalCenter: parent.verticalCenter }
            text: mp.curLabel !== "" ? mp.curLabel : mp.ph
            color: mp.curLabel !== "" ? Tokens.inkDim : Tokens.inkMuted
            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; elide: Text.ElideRight
        }
        Text {
            id: car
            anchors { right: parent.right; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
            text: "\u25be"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
        }
        HoverHandler { id: mph; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: mp.activated() }
    }

    // the cubic bezier editor. Endpoints pinned at (0,0) and (1,1); the two
    // control points drag freely. X clamps to [0,1] (monotonic in time), Y to
    // [-1,2] (overshoot for bounce). antialiasing off, ink strokes.
    component BezierEditor: Item {
        id: ed
        property real x0: 0.25
        property real y0: 0.1
        property real x1: 0.25
        property real y1: 1.0
        signal changed(real x0, real y0, real x1, real y1)
        readonly property real pad: 18
        readonly property real yMin: -1.0
        readonly property real yMax: 2.0
        implicitWidth: 300
        implicitHeight: 280
        function px(x) { return ed.pad + x * (ed.width - 2 * ed.pad); }
        function py(y) { return ed.height - ed.pad - (y - ed.yMin) / (ed.yMax - ed.yMin) * (ed.height - 2 * ed.pad); }
        function ux(p) { return Math.max(0, Math.min(1, (p - ed.pad) / (ed.width - 2 * ed.pad))); }
        function uy(p) { return Math.max(ed.yMin, Math.min(ed.yMax, ed.yMin + (ed.height - ed.pad - p) / (ed.height - 2 * ed.pad) * (ed.yMax - ed.yMin))); }
        onX0Changed: cv.requestPaint()
        onY0Changed: cv.requestPaint()
        onX1Changed: cv.requestPaint()
        onY1Changed: cv.requestPaint()
        onWidthChanged: cv.requestPaint()
        onHeightChanged: cv.requestPaint()

        Rectangle { anchors.fill: parent; radius: Tokens.radius; color: "transparent"; border.width: Tokens.border; border.color: Tokens.line }

        Canvas {
            id: cv
            anchors.fill: parent
            antialiasing: false
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                // baselines at progress 0 and 1
                ctx.lineWidth = 1;
                ctx.strokeStyle = Tokens.lineSoft;
                ctx.beginPath();
                ctx.moveTo(ed.px(0), ed.py(0));
                ctx.lineTo(ed.px(1), ed.py(0));
                ctx.moveTo(ed.px(0), ed.py(1));
                ctx.lineTo(ed.px(1), ed.py(1));
                ctx.stroke();
                // handle arms
                ctx.strokeStyle = Tokens.inkMuted;
                ctx.beginPath();
                ctx.moveTo(ed.px(0), ed.py(0));
                ctx.lineTo(ed.px(ed.x0), ed.py(ed.y0));
                ctx.moveTo(ed.px(1), ed.py(1));
                ctx.lineTo(ed.px(ed.x1), ed.py(ed.y1));
                ctx.stroke();
                // the curve itself (data plot, not chrome)
                ctx.strokeStyle = Tokens.ink;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(ed.px(0), ed.py(0));
                ctx.bezierCurveTo(ed.px(ed.x0), ed.py(ed.y0), ed.px(ed.x1), ed.py(ed.y1), ed.px(1), ed.py(1));
                ctx.stroke();
            }
        }

        // control-point pucks: hairline square at rest, solid ink while dragging
        Rectangle {
            width: 14; height: 14; radius: Tokens.radius; antialiasing: false
            x: ed.px(ed.x0) - 7; y: ed.py(ed.y0) - 7
            color: hd0.active ? Tokens.ink : "transparent"
            border.width: Tokens.border; border.color: Tokens.ink
            Behavior on color { ColorAnimation { duration: Tokens.snap } }
            DragHandler {
                id: hd0
                target: null
                property real lastX: 0
                property real lastY: 0
                onActiveChanged: if (active) { lastX = 0; lastY = 0; }
                onTranslationChanged: {
                    var nx = ed.ux(ed.px(ed.x0) + (translation.x - lastX));
                    var ny = ed.uy(ed.py(ed.y0) + (translation.y - lastY));
                    lastX = translation.x; lastY = translation.y;
                    ed.changed(nx, ny, ed.x1, ed.y1);
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        Rectangle {
            width: 14; height: 14; radius: Tokens.radius; antialiasing: false
            x: ed.px(ed.x1) - 7; y: ed.py(ed.y1) - 7
            color: hd1.active ? Tokens.ink : "transparent"
            border.width: Tokens.border; border.color: Tokens.ink
            Behavior on color { ColorAnimation { duration: Tokens.snap } }
            DragHandler {
                id: hd1
                target: null
                property real lastX: 0
                property real lastY: 0
                onActiveChanged: if (active) { lastX = 0; lastY = 0; }
                onTranslationChanged: {
                    var nx = ed.ux(ed.px(ed.x1) + (translation.x - lastX));
                    var ny = ed.uy(ed.py(ed.y1) + (translation.y - lastY));
                    lastX = translation.x; lastY = translation.y;
                    ed.changed(ed.x0, ed.y0, nx, ny);
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }

    // a live value preview: a window slides with the selected curve, so the
    // easing is felt, not read off control points. Plays on change and on tap
    // -- feedback, never a perpetual loop (that is the Decor's alone).
    component MotionPreview: Item {
        id: mv
        property real x0: 0.25
        property real y0: 0.1
        property real x1: 0.25
        property real y1: 1.0
        property int dur: 640
        property string label: ""
        readonly property real pad: Tokens.s5
        readonly property real winW: 56
        readonly property real leftW: Math.round(mv.width * 0.24)
        readonly property real trackY: Math.round(mv.height * 0.62)
        readonly property real dest: 0.82 * (mv.width - mv.leftW - 2 * mv.pad - mv.winW)
        height: 122

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius
            color: "transparent"
            border.width: Tokens.border
            border.color: stageH.hovered ? Tokens.lineStrong : Tokens.line
            Behavior on border.color { ColorAnimation { duration: Tokens.snap } }
        }
        Text {
            id: pvLabel
            anchors { left: parent.left; leftMargin: Tokens.s4; top: parent.top; topMargin: Tokens.s3 }
            text: I18n.tr("PREVIEW"); color: Tokens.inkDim
            font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; font.letterSpacing: Tokens.trackMark
        }
        Text {
            anchors { right: parent.right; rightMargin: Tokens.s4; verticalCenter: pvLabel.verticalCenter }
            text: I18n.tr("tap to replay"); color: Tokens.inkFaint
            font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
        }

        // left: what is being previewed
        Column {
            anchors { left: parent.left; leftMargin: Tokens.s4; verticalCenter: parent.verticalCenter; verticalCenterOffset: Tokens.s2 }
            width: mv.leftW - Tokens.s4
            spacing: 2
            Text { text: I18n.tr("CURVE"); color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; font.letterSpacing: Tokens.trackMark }
            Text {
                width: parent.width
                text: mv.label.length ? I18n.tr(mv.label) : I18n.tr("curve")
                color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fBody; font.weight: Font.Medium; elide: Text.ElideRight
            }
            Text { text: mv.dur + " ms"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny }
        }

        // right: the runway the window travels, a measured track
        Item {
            id: runway
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            anchors.leftMargin: mv.leftW + mv.pad; anchors.rightMargin: mv.pad
            clip: true
            Repeater {
                model: 21
                delegate: Rectangle {
                    required property int index
                    readonly property bool major: index % 5 === 0
                    x: index / 20 * runway.width
                    y: mv.trackY; width: 1; height: major ? 7 : 4
                    color: major ? Tokens.line : Tokens.lineSoft
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right }
                y: mv.trackY; height: 1; color: Tokens.line
            }
            Rectangle {
                width: mv.winW; height: 36; radius: Tokens.radius
                color: "transparent"; border.width: Tokens.border; border.color: Tokens.line
                y: mv.trackY - height; x: mv.dest
            }
            Rectangle {
                id: win
                width: mv.winW; height: 36; radius: Tokens.radius
                color: Tokens.bone
                y: mv.trackY - height; x: 0
                Text { anchors.centerIn: parent; text: "\u529b"; color: Tokens.inkOnBone; font.family: Tokens.jp; font.pixelSize: Tokens.fSmall }
            }
            NumberAnimation {
                id: anim
                target: win; property: "x"
                from: 0; to: mv.dest
                duration: mv.dur
                easing.type: Easing.Bezier
                easing.bezierCurve: [mv.x0, mv.y0, mv.x1, mv.y1, 1.0, 1.0]
            }
            Text {
                anchors { left: parent.left; top: parent.top; topMargin: mv.trackY + Tokens.s2 }
                text: I18n.tr("START"); color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; font.letterSpacing: Tokens.trackMark
            }
            Text {
                anchors { right: parent.right; top: parent.top; topMargin: mv.trackY + Tokens.s2 }
                text: I18n.tr("SETTLE"); color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; font.letterSpacing: Tokens.trackMark
            }
        }

        Timer { id: replay; interval: 150; onTriggered: mv._play() }
        function _play() { anim.stop(); win.x = 0; anim.start(); }
        function play() { replay.restart(); }   // debounced: a drag coalesces into one replay
        onX0Changed: mv.play()
        onY0Changed: mv.play()
        onX1Changed: mv.play()
        onY1Changed: mv.play()
        Component.onCompleted: mv.play()
        TapHandler { onTapped: mv._play() }
        HoverHandler { id: stageH; cursorShape: Qt.PointingHandCursor }
    }

    // ── head ─────────────────────────────────────────────────────────────────
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle { width: 16; height: 1; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "力"; color: Tokens.ink; font.family: Tokens.jp; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: I18n.tr("DESKTOP"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: Tokens.fTiny; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text { text: I18n.tr("Animations"); color: Tokens.ink; font.family: Tokens.display; font.pixelSize: Tokens.fTitle }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("How the desktop moves. Pick a feel and watch it live, set the flash on the window that takes focus, and fine-tune any single animation under Advanced.")
            color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
        Item { width: 1; height: Tokens.s1 }
    }

    // ── content ────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; topMargin: Tokens.s5 }
        contentWidth: width
        contentHeight: col.height + Tokens.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { }

        Column {
            id: col
            width: flick.width - Tokens.s4
            spacing: Tokens.s5
            // The shell's own motion (distinct from the Hyprland window editor below).
            SettingCard {
                width: col.width
                title: I18n.tr("SHELL MOTION")
                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s1
                    text: I18n.tr("How fast the shell's own panels, menus and transitions move. Speed scales every Ryoku animation live; Reduce motion snaps them into place for comfort. Separate from the window animations below.")
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Speed")
                    value: pg.motionScaleLabel
                    controlWidth: Math.min(240, Math.max(160, Math.round(col.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0.25; to: 3.0
                        value: pg.motionScale
                        onModified: (v) => pg.setMotion("scale", Math.round(v * 20) / 20)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Reduce motion")
                    desc: I18n.tr("Snap animations to their end instead of playing them.")
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: pg.reduceMotion
                        onToggled: (v) => pg.setMotion("reduce", v)
                    }
                }
            }

            SettingCard {
                width: col.width
                title: I18n.tr("ANIMATION PRESET")
                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s1
                    text: I18n.tr("The window animation personality: how windows, workspaces and layers move. Picking one reloads Hyprland; your curve tweaks below still apply on top.")
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    block: true
                    label: I18n.tr("Preset")
                    Chips {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: pg.animPresetLabels
                        current: pg.animPresetLabel(pg.animPreset)
                        onChose: (l) => pg.setAnimPreset(pg.animPresetId(l))
                    }
                }
            }

            // MOTION -- the global motion switch plus the bespoke curve workshop
            SettingCard {
                width: col.width
                title: I18n.tr("MOTION")
                visible: pg.gVisible || pg.cVisible

                // the one genuine setting: the master switch for desktop motion
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    visible: pg.hit("animations master switch desktop motion")
                    label: I18n.tr("Animations")
                    desc: I18n.tr("Master switch for desktop motion; off, everything snaps into place")
                    def: pg.cv("appearance.animations") ? I18n.tr("ON") : I18n.tr("OFF")
                    changed: pg.chg("appearance.animations")
                    source: "settings.lua"
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.hv("appearance.animations")
                        onToggled: (v) => pg.he("appearance.animations", v)
                    }
                }

                // the curve workshop -- bespoke: curve select + NEW/DELETE, one-tap
                // feels, the live motion preview, and the cubic-bezier editor with
                // its readouts and decor. Kept intact from the original MOTION group.
                Item {
                    width: parent.width
                    height: workshop.height + 2 * Tokens.s4

                    // hairline off the switch row above (only while it is shown)
                    Rectangle {
                        visible: pg.hit("animations master switch desktop motion")
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4
                        height: 1; color: Tokens.lineSoft
                    }

                    Column {
                        id: workshop
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4; anchors.topMargin: Tokens.s4
                        spacing: Tokens.s4

                        // curve selector + NEW / DELETE-RESET
                        Item {
                            width: parent.width
                            height: Tokens.ctlH
                            MiniPick {
                                id: curveSel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(180, parent.width - newBtn.width - delBtn.width - 2 * Tokens.s2)
                                heading: I18n.tr("Curve")
                                ph: I18n.tr("no curves")
                                opts: pg.curveNames()
                                current: pg.selectedCurve
                                onActivated: pg.openPicker(I18n.tr("Curve"), curveSel.opts, curveSel.current, function (k) { curveSel.picked(k); })
                                onPicked: (k) => pg.selectedCurve = k
                            }
                            Btn {
                                id: newBtn
                                anchors.right: delBtn.left
                                anchors.rightMargin: Tokens.s2
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("NEW")
                                onAct: pg.addCurve()
                            }
                            Btn {
                                id: delBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: pg.selectedIsCustom ? I18n.tr("DELETE") : I18n.tr("RESET")
                                armed: pg.selectedIsCustom || pg.selectedHasOverride
                                onAct: pg.resetCurve(pg.selectedCurve)
                            }
                        }

                        // one-tap feels -- a starting point, friendlier than handles
                        Item {
                            width: parent.width
                            height: Tokens.ctlH
                            Text {
                                id: feelLabel
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: I18n.tr("FEEL"); color: Tokens.inkFaint
                                font.family: Tokens.mono; font.pixelSize: Tokens.fMicro; font.letterSpacing: Tokens.trackMark
                            }
                            Row {
                                anchors { left: feelLabel.right; leftMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                                spacing: Tokens.s2
                                Repeater {
                                    model: pg.feels
                                    delegate: Rectangle {
                                        id: chip
                                        required property var modelData
                                        readonly property bool active: pg.feelActive(chip.modelData.c)
                                        width: chipT.implicitWidth + Tokens.s4; height: Tokens.ctlH
                                        radius: Tokens.radius
                                        color: chip.active ? Tokens.bone : (chh.hovered ? Tokens.tint10 : "transparent")
                                        border.width: Tokens.border
                                        border.color: chip.active ? Tokens.bone : (chh.hovered ? Tokens.lineStrong : Tokens.line)
                                        Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                        Text {
                                            id: chipT
                                            anchors.centerIn: parent
                                            text: chip.modelData.name
                                            color: chip.active ? Tokens.inkOnBone : Tokens.inkDim
                                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                        }
                                        HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: pg.upsertCurve(pg.selectedCurve, chip.modelData.c[0], chip.modelData.c[1], chip.modelData.c[2], chip.modelData.c[3]) }
                                    }
                                }
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: I18n.tr("a one-tap starting point"); color: Tokens.inkFaint
                                font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                            }
                        }

                        // the selected curve, felt -- sits between its controls
                        MotionPreview {
                            width: parent.width
                            label: pg.selectedCurve
                            x0: pg.curveOf(pg.selectedCurve).x0
                            y0: pg.curveOf(pg.selectedCurve).y0
                            x1: pg.curveOf(pg.selectedCurve).x1
                            y1: pg.curveOf(pg.selectedCurve).y1
                        }

                        // editor + readouts + decor
                        Row {
                            width: parent.width
                            spacing: Tokens.s5

                            BezierEditor {
                                id: bez
                                width: 300
                                height: 280
                                x0: pg.curveOf(pg.selectedCurve).x0
                                y0: pg.curveOf(pg.selectedCurve).y0
                                x1: pg.curveOf(pg.selectedCurve).x1
                                y1: pg.curveOf(pg.selectedCurve).y1
                                onChanged: (a, b, c, d) => pg.upsertCurve(pg.selectedCurve, a, b, c, d)
                            }

                            Column {
                                id: readouts
                                width: 220
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s3

                                Text { text: I18n.tr("Fine-tune the handles."); color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall }
                                Text { text: I18n.tr("P1   ") + bez.x0.toFixed(2) + ", " + bez.y0.toFixed(2); color: Tokens.ink; font.family: Tokens.mono; font.pixelSize: Tokens.fSmall }
                                Text { text: I18n.tr("P2   ") + bez.x1.toFixed(2) + ", " + bez.y1.toFixed(2); color: Tokens.ink; font.family: Tokens.mono; font.pixelSize: Tokens.fSmall }
                                Text {
                                    width: 200
                                    text: I18n.tr("Presets set the shape; drag to fine-tune. Curves are shared by name, and Advanced animations reference them.")
                                    color: Tokens.inkFaint; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                                }
                            }
                            Decor {
                                id: motionDecor
                                width: parent.width - bez.width - readouts.width - 2 * Tokens.s5
                                height: bez.height
                                images: ["bounce.gif", "cradle.gif", "horse.gif", "disc.gif", "earth.gif"]
                                seed: 0
                                title: "\u6ed1\u3089\u304b"
                                sub: "\u30a4\u30fc\u30ba"
                                tate: "\u306a\u3081\u3089\u304b\u306b"
                                caption: I18n.tr("Every motion here rides an easing curve, so nothing on the desktop just snaps into place.")
                                code: "MOVE-02"; seal: "\u52d5"; boxId: "anim.motion"
                            }
                        }
                    }
                }
            }

            // FOCUS FLASH
            SettingCard {
                id: fsec
                width: col.width
                title: I18n.tr("FOCUS FLASH")
                visible: pg.fVisible

                readonly property bool ffOn: !!pg.hv("plugins.hyprfocus.enabled")
                readonly property string ffMode: String(pg.hv("plugins.hyprfocus.mode"))

                // group note, shown once the effect is on (was the trailing blurb)
                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s1
                    visible: fsec.ffOn
                    text: I18n.tr("Briefly flashes, bounces, or slides a window when it gains focus. Applies on Save.")
                    color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: fsec.ffOn
                    visible: pg.hit("animate the focused window enabled")
                    label: I18n.tr("Animate the focused window")
                    desc: I18n.tr("Short effect on the window that takes focus; applies on Save only")
                    def: pg.cv("plugins.hyprfocus.enabled") ? I18n.tr("ON") : I18n.tr("OFF")
                    changed: pg.chg("plugins.hyprfocus.enabled")
                    source: "settings.lua"
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: fsec.ffOn
                        onToggled: (v) => pg.he("plugins.hyprfocus.enabled", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    block: true
                    visible: fsec.ffOn && pg.hit("style flash bounce slide")
                    label: I18n.tr("Style")
                    desc: I18n.tr("Flash dips opacity, Bounce shrinks and springs, Slide nudges it")
                    def: pg.cap(String(pg.cv("plugins.hyprfocus.mode")))
                    changed: pg.chg("plugins.hyprfocus.mode")
                    source: "settings.lua"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["flash", "bounce", "slide"]
                        current: fsec.ffMode
                        onChose: (k) => pg.he("plugins.hyprfocus.mode", k)
                    }
                }
                // opacity/bounce are fractional (0..1); the module Slid is integer,
                // so map to a 0..100 percent domain and store /100.
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    visible: fsec.ffOn && fsec.ffMode === "flash" && pg.hit("flash opacity")
                    label: I18n.tr("Flash opacity")
                    desc: I18n.tr("Opacity the flash dips to, lower is deeper; Flash style only")
                    unit: "%"
                    value: String(Math.round((Number(pg.hv("plugins.hyprfocus.opacity")) || 0) * 100))
                    def: String(Math.round((Number(pg.cv("plugins.hyprfocus.opacity")) || 0) * 100))
                    changed: pg.chg("plugins.hyprfocus.opacity")
                    source: "settings.lua"
                    controlWidth: Math.min(240, Math.max(160, Math.round(fsec.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 100
                        value: Math.round((Number(pg.hv("plugins.hyprfocus.opacity")) || 0) * 100)
                        onModified: (v) => pg.he("plugins.hyprfocus.opacity", v / 100)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    visible: fsec.ffOn && fsec.ffMode === "bounce" && pg.hit("bounce strength")
                    label: I18n.tr("Bounce strength")
                    desc: I18n.tr("Scale the window shrinks to, lower bounces harder; Bounce style only")
                    unit: "%"
                    value: String(Math.round((Number(pg.hv("plugins.hyprfocus.bounce")) || 0) * 100))
                    def: String(Math.round((Number(pg.cv("plugins.hyprfocus.bounce")) || 0) * 100))
                    changed: pg.chg("plugins.hyprfocus.bounce")
                    source: "settings.lua"
                    controlWidth: Math.min(240, Math.max(160, Math.round(fsec.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 50; to: 100
                        value: Math.round((Number(pg.hv("plugins.hyprfocus.bounce")) || 0) * 100)
                        onModified: (v) => pg.he("plugins.hyprfocus.bounce", v / 100)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    visible: fsec.ffOn && fsec.ffMode === "slide" && pg.hit("slide height")
                    label: I18n.tr("Slide height")
                    desc: I18n.tr("How far the window hops, in pixels; Slide style only")
                    unit: "px"
                    value: String(Math.round(Number(pg.hv("plugins.hyprfocus.slide")) || 0))
                    def: String(Math.round(Number(pg.cv("plugins.hyprfocus.slide")) || 0))
                    changed: pg.chg("plugins.hyprfocus.slide")
                    source: "settings.lua"
                    controlWidth: 58
                    Step {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 150
                        value: Math.round(Number(pg.hv("plugins.hyprfocus.slide")) || 0)
                        onModified: (v) => pg.he("plugins.hyprfocus.slide", v)
                    }
                }
            }

            // ADVANCED -- per-animation control; the leaf table is a bespoke list
            SettingCard {
                width: col.width
                title: I18n.tr("ADVANCED")
                visible: pg.aVisible

                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s1
                    text: I18n.tr("Per-animation control, for when a feel isn't enough. Each row is one desktop animation: turn it off, change its speed, its curve, or its style.")
                    color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4; bottomPadding: Tokens.s3
                    visible: pg.liveAnims.length === 0
                    text: I18n.tr("No tunable animations reported.")
                    color: Tokens.inkFaint; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                }

                // one flat drawer row per tunable leaf: name, then its four controls
                // (enable, speed, style, curve). A bespoke multi-control list, so not
                // a SettingRow, but styled to sit in the drawer.
                Repeater {
                    model: pg.liveAnims
                    delegate: Item {
                        id: ar
                        required property var modelData
                        readonly property string leaf: modelData.name
                        readonly property var it: pg.itemOf(ar.leaf)
                        readonly property var styleOpts: pg.styleOptionsFor(ar.leaf)
                        readonly property bool on: !!ar.it.enabled

                        anchors.left: parent.left; anchors.right: parent.right
                        height: Tokens.rowH
                        visible: pg.hit(ar.leaf)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Tokens.radius
                            color: arh.hovered ? Tokens.tint5 : "transparent"
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4
                            height: 1; color: Tokens.lineSoft
                        }
                        HoverHandler { id: arh }

                        Text {
                            anchors { left: parent.left; leftMargin: Tokens.s4; right: ctl.left; rightMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                            text: ar.leaf
                            elide: Text.ElideRight
                            color: ar.on ? Tokens.ink : Tokens.inkFaint
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                        }
                        Row {
                            id: ctl
                            anchors { right: parent.right; rightMargin: Tokens.s4; verticalCenter: parent.verticalCenter }
                            spacing: Tokens.s3

                            Sw {
                                anchors.verticalCenter: parent.verticalCenter
                                on: ar.on
                                onToggled: (v) => pg.upsertItem(ar.leaf, "enabled", v)
                            }
                            NumStep {
                                anchors.verticalCenter: parent.verticalCenter
                                value: Number(ar.it.speed) || 0
                                min: 0.1; max: 10
                                onChanged: (v) => pg.upsertItem(ar.leaf, "speed", v)
                            }
                            MiniPick {
                                id: styleP
                                anchors.verticalCenter: parent.verticalCenter
                                visible: ar.styleOpts.length > 0
                                heading: I18n.tr("Style"); ph: I18n.tr("style")
                                opts: ar.styleOpts
                                current: String(ar.it.style || "")
                                onActivated: pg.openPicker(I18n.tr("Style"), styleP.opts, styleP.current, function (k) { styleP.picked(k); })
                                onPicked: (k) => pg.upsertItem(ar.leaf, "style", k)
                            }
                            MiniPick {
                                id: bezP
                                anchors.verticalCenter: parent.verticalCenter
                                heading: I18n.tr("Curve"); ph: I18n.tr("curve")
                                opts: pg.curveNames()
                                current: String(ar.it.bezier || "")
                                onActivated: pg.openPicker(I18n.tr("Curve"), bezP.opts, bezP.current, function (k) { bezP.picked(k); })
                                onPicked: (k) => pg.upsertItem(ar.leaf, "bezier", k)
                            }
                        }
                    }
                }
            }
        }
    }

    // no-match state, mirroring the schema sheet
    Column {
        anchors.centerIn: flick
        visible: pg.query !== "" && !pg.anyVisible
        spacing: Tokens.s2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("NO MATCH"); color: Tokens.inkDim; font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall; font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("nothing here matches “%1”").arg(pg.query)
            color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
        }
    }

    // ── catalogue overlay ────────────────────────────────────────────────────
    QtObject {
        id: pk
        property var opts: null
        property string current: ""
        property string title: ""
        property var cb: null
    }
    Item {
        anchors.fill: parent
        visible: pk.opts !== null
        z: 800

        Rectangle {
            anchors.fill: parent
            color: Tokens.paper
            opacity: 0.55
            TapHandler { onTapped: pg.closePicker() }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: Math.min(360, 56 + (pk.opts ? pk.opts.length : 0) * 32)
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineStrong

            Column {
                anchors.fill: parent
                anchors.margins: Tokens.s3
                spacing: Tokens.s2

                Row {
                    width: parent.width
                    Text {
                        id: pkTitle
                        text: pk.title.toUpperCase(); color: Tokens.ink; font.family: Tokens.ui
                        font.pixelSize: Tokens.fMicro; font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                    }
                    Item { width: parent.width - pkTitle.width - pkCount.width; height: 1 }
                    Text {
                        id: pkCount
                        text: I18n.tr("%1 ENTRIES").arg(pk.opts ? pk.opts.length : 0)
                        color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                    }
                }
                Flickable {
                    width: parent.width
                    height: parent.height - pkTitle.height - Tokens.s2
                    contentHeight: pkList.height
                    clip: true
                    ScrollBar.vertical: ScrollRail { }
                    Column {
                        id: pkList
                        width: parent.width
                        Repeater {
                            model: pk.opts
                            delegate: Rectangle {
                                required property var modelData
                                width: pkList.width
                                height: 32
                                color: rh.hovered ? Tokens.bone : "transparent"
                                Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                Text {
                                    anchors { left: parent.left; leftMargin: Tokens.s2; right: dot.left; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                                    text: I18n.tr(modelData.label)
                                    elide: Text.ElideRight
                                    color: rh.hovered ? Tokens.inkOnBone : (modelData.key === pk.current ? Tokens.ink : Tokens.inkDim)
                                    font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                }
                                Rectangle {
                                    id: dot
                                    anchors { right: parent.right; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                                    visible: modelData.key === pk.current
                                    width: 4; height: 4; radius: 2
                                    color: rh.hovered ? Tokens.inkOnBone : Tokens.ink
                                }
                                HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: pg.choosePick(modelData.key) }
                            }
                        }
                    }
                }
            }
        }
    }
}
