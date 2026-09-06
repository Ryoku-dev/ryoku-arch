pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live config for the desktop visualiser. One or more visualisers can share the
// desktop: the PRIMARY is the flat top-level config (the one Ryoku Settings'
// Visualizer tab still edits and reset-to-defaults mirrors), and any EXTRAS ride
// an `extras` list, each a full per-viz object. `active` is the instance the
// on-desktop editor is tuning. The renderer paints `list` (primary + extras);
// the editor reads/writes the active instance through here.
//
// JSON at ~/.config/ryoku/visualizer.json, watched, so a save in Settings (or a
// Super+M toggle) retunes the running spectrum on the next file event. Fractions
// are of the monitor, matching how the spectrum sizes itself.
Singleton {
    id: root

    // --- globals (shared by every instance) -----------------------------------
    property alias enabled:  adapter.enabled     // master on/off (also Super+M)
    property alias fps:      adapter.fps          // 30 default, up to 60
    property alias adaptive: adapter.adaptive     // auto-throttle under load

    // The looks the renderer knows, canonical here for cycleStyle.
    readonly property var knownStyles: act.knownStyles

    // --- the instances --------------------------------------------------------
    // The primary as a plain object (its flat keys), so it sits in `list` beside
    // the extras and the renderer treats them uniformly.
    function primaryData() {
        return {
            "style": adapter.style, "shape": adapter.shape,
            "color": adapter.color, "color2": adapter.color2, "gradient": adapter.gradient,
            "bars": adapter.bars, "thickness": adapter.thickness, "bloom": adapter.bloom,
            "reflection": adapter.reflection, "idleWave": adapter.idleWave,
            "mirror": adapter.mirror, "segments": adapter.segments,
            "gain": adapter.gain, "smoothing": adapter.smoothing, "peaks": adapter.peaks,
            "spin": adapter.spin, "x": adapter.x, "y": adapter.y, "w": adapter.w,
            "h": adapter.h, "grow": adapter.grow, "angle": adapter.angle,
            "tiltX": adapter.tiltX, "tiltY": adapter.tiltY
        };
    }
    function dataAt(index) {
        if (index <= 0)
            return root.primaryData();
        return (adapter.extras || [])[index - 1] || ({});
    }
    readonly property var list: {
        var out = [root.primaryData()];
        var ex = adapter.extras || [];
        for (var i = 0; i < ex.length; i++)
            out.push(ex[i]);
        return out;
    }
    readonly property int count: root.list.length
    readonly property int active: Math.max(0, Math.min(root.count - 1, adapter.active))
    readonly property var activeData: root.list[root.active]

    // Never more than this many at once; each adds a full-screen GPU pass.
    readonly property int maxVisualizers: 4
    // A light estimate for the RAM a visualiser costs (its render buffers; cava is
    // shared), so the editor can warn before the desktop is stacked with passes.
    readonly property int ramPerVizMB: 35
    readonly property int ramEstimateMB: root.count * root.ramPerVizMB

    // The active instance, normalised, for the editor and placer to read.
    VizItem { id: act; data: root.activeData }

    readonly property string styleId:       act.styleId
    readonly property bool   isPolar:       act.isPolar
    readonly property bool   peaksApply:    act.peaksApply
    readonly property bool   mirrorApplies: act.mirrorApplies
    readonly property int    bars:          act.bars
    readonly property real   thickness:     act.thickness
    readonly property real   gain:          act.gain

    // Cava is fed once for every instance: at the largest band count any of them
    // wants (each Motion resamples down), and the scope waveform is captured while
    // any instance is the line look.
    readonly property int maxBars: {
        var m = 16;
        for (var i = 0; i < root.list.length; i++)
            m = Math.max(m, Math.round(root.list[i].bars || 64));
        return Math.max(16, Math.min(128, m));
    }
    readonly property bool anyLine: {
        for (var i = 0; i < root.list.length; i++)
            if (("" + (root.list[i].style || "")) === "line")
                return true;
        return false;
    }
    readonly property real   smoothing:     act.smoothing
    readonly property bool   mirror:        act.mirror
    readonly property bool   peaks:         act.peaks
    readonly property int    segments:      act.segments
    readonly property real   spin:          act.spin
    readonly property real   x:             act.x
    readonly property real   y:             act.y
    readonly property real   w:             act.w
    readonly property real   h:             act.h
    readonly property string grow:          act.grow
    readonly property real   angle:         act.angle
    readonly property real   tiltX:         act.tiltX
    readonly property real   tiltY:         act.tiltY

    // Colour + gradient of the active instance, for the editor's picker.
    readonly property bool   hasCustomColor: act.hasCustomColor
    readonly property color  customColor:    act.customColor
    readonly property string colorHex:       act.hasCustomColor ? act.rawColor : ""
    readonly property bool   gradient:       adapter.active <= 0 ? (adapter.gradient === true) : (act.val("gradient", false) === true)
    readonly property bool   hasColor2:      act.hasColor2
    readonly property color  color2Value:    act.color2Value
    readonly property string color2Hex:      act.hasColor2 ? act.rawColor2 : ""

    // --- editing the active instance ------------------------------------------
    // Every per-viz edit lands on the active instance: the primary writes its flat
    // keys, an extra rewrites its slot in the list. Edits settle through one
    // coalescer, since the watched file returns a write as a reload.
    function poke(key, value) {
        if (root.active <= 0) {
            adapter[key] = value;
        } else {
            var arr = (adapter.extras || []).slice();
            var e = Object.assign({}, arr[root.active - 1]);
            e[key] = value;
            arr[root.active - 1] = e;
            adapter.extras = arr;
        }
        settle.restart();
    }

    function setStyle(k) {
        if (root.knownStyles.indexOf(k) < 0)
            return;
        root.poke("style", k);
    }
    function cycleStyle(by) {
        var i = root.knownStyles.indexOf(root.styleId);
        var n = root.knownStyles.length;
        root.setStyle(root.knownStyles[(i + by + n) % n]);
    }
    function setBars(n) { root.poke("bars", Math.max(16, Math.min(128, Math.round(n)))); }
    function toggleMirror() { root.poke("mirror", !root.mirror); }
    function togglePeaks() { root.poke("peaks", !root.peaks); }
    function setGain(v) { root.poke("gain", Math.max(0.5, Math.min(2, v))); }
    function setSmoothing(v) { root.poke("smoothing", Math.max(0, Math.min(1, v))); }

    // Well short of edge-on: past this the bands crowd into a line.
    readonly property real tiltMax: 35
    function setTiltX(v) { root.poke("tiltX", Math.max(-root.tiltMax, Math.min(root.tiltMax, v))); }
    function setTiltY(v) { root.poke("tiltY", Math.max(-root.tiltMax, Math.min(root.tiltMax, v))); }
    function levelTilt() {
        root.poke("tiltX", 0);
        root.poke("tiltY", 0);
    }

    // Colour: a pinned #rrggbb, "" to follow the wallpaper. A gradient adds a
    // second stop; both stops must be valid hex for it to paint.
    function setColor(hex) {
        var t = ("" + hex).trim();
        if (t.length > 0 && t[0] !== "#") t = "#" + t;
        if (!/^#[0-9a-fA-F]{6}$/.test(t)) return;
        root.poke("color", t);
    }
    function clearColor() { root.poke("color", ""); }
    function setColor2(hex) {
        var t = ("" + hex).trim();
        if (t.length > 0 && t[0] !== "#") t = "#" + t;
        if (!/^#[0-9a-fA-F]{6}$/.test(t)) return;
        root.poke("color2", t);
    }
    function setGradient(on) { root.poke("gradient", on === true); }
    function toggleGradient() { root.setGradient(!root.gradient); }

    // persist on/off so the hub toggle and Super+M keybind agree, and it
    // survives a restart. Global, so it always writes the flat key.
    function setEnabled(on) {
        adapter.enabled = on;
        file.writeAdapter();
    }

    // How much of the box's own turned footprint is allowed to hang past a
    // screen edge, an aesthetic choice the box can be left sitting in (not just
    // a mid-drag overshoot that snaps back): 0 keeps the whole look on screen,
    // 0.5 would let it hang out to its own centre. Proportional to the box's
    // footprint rather than a flat screen fraction, so a small look doesn't lose
    // a bigger share of itself than a large one does.
    readonly property real overhang: 0.5

    // The box is a fraction of the screen, and a look can be left hanging
    // `overhang` of its own turned footprint past an edge, on purpose - past
    // that, it is clamped back (the placer used to allow a flat quarter-screen
    // past any edge regardless of the box's own size, and a drag or a wheel
    // resize that stopped past the limit left the spectrum clipped further than
    // intended, saved that way on every login). Size is clamped first, then the
    // position to what the size and the overhang allowance leave.
    //
    // A turned box's own footprint is bigger than its unrotated w/h (the same
    // axis-aligned bounding box SpectrumField.qml works out for coverRect), so
    // clamping position against the raw w/h left a turned look free to swing an
    // arc it never actually needed and still short of the edge it visually
    // reached. `angleDeg` and `aspect` (screenWidth / screenHeight, since width
    // and height are fractions of different physical scales on anything but a
    // square screen) fold that footprint into the same clamp. Callers that omit
    // them keep the old unrotated, square-screen behaviour.
    function fitBox(nx, ny, nw, nh, angleDeg, aspect) {
        var w = Math.max(0.04, Math.min(1, nw));
        var h = Math.max(0.03, Math.min(1, nh));
        var a = ((angleDeg || 0) % 180) * Math.PI / 180;
        var ar = (aspect && aspect > 0) ? aspect : 1;
        var c = Math.abs(Math.cos(a)), s = Math.abs(Math.sin(a));
        // The turned box's own bounding box, back in fraction space.
        var bw = Math.min(1, w * c + h * s / ar);
        var bh = Math.min(1, w * s * ar + h * c);
        var oh = Math.max(0, Math.min(0.5, root.overhang));
        var minCx = bw * (0.5 - oh), maxCx = 1 - minCx;
        var minCy = bh * (0.5 - oh), maxCy = 1 - minCy;
        var cx = Math.max(minCx, Math.min(maxCx, nx + w / 2));
        var cy = Math.max(minCy, Math.min(maxCy, ny + h / 2));
        return { x: cx - w / 2, y: cy - h / 2, w: w, h: h };
    }

    // Placement from the desktop: the properties move with the pointer so the
    // look follows the drag frame by frame, written once the gesture settles.
    function moveBox(nx, ny, aspect) {
        var b = root.fitBox(nx, ny, root.w, root.h, root.angle, aspect);
        root.poke("x", b.x);
        root.poke("y", b.y);
    }
    function sizeBox(nw, nh, aspect) {
        root.setBox(root.x, root.y, nw, nh, aspect);
    }
    // Size and position land together, or a turned box swings between two writes.
    function setBox(nx, ny, nw, nh, aspect) {
        var b = root.fitBox(nx, ny, nw, nh, root.angle, aspect);
        if (root.active <= 0) {
            adapter.w = b.w;
            adapter.h = b.h;
            adapter.x = b.x;
            adapter.y = b.y;
        } else {
            var arr = (adapter.extras || []).slice();
            var e = Object.assign({}, arr[root.active - 1]);
            e.w = b.w;
            e.h = b.h;
            e.x = b.x;
            e.y = b.y;
            arr[root.active - 1] = e;
            adapter.extras = arr;
        }
        settle.restart();
    }
    // Wrapped, so a full circle of dragging never runs into a stop.
    function rotate(deg) {
        var d = deg % 360;
        root.poke("angle", d < 0 ? d + 360 : d);
    }
    // Mirroring what is on screen is a different thing per family.
    function flip() {
        if (root.isPolar)
            root.poke("spin", -root.spin);
        else if (root.grow === "up")
            root.poke("grow", "down");
        else if (root.grow === "down")
            root.poke("grow", "up");
        else if (root.grow === "left")
            root.poke("grow", "right");
        else if (root.grow === "right")
            root.poke("grow", "left");
        else
            root.poke("mirror", !root.mirror);
    }

    // --- instance management --------------------------------------------------
    function setActive(i) {
        adapter.active = Math.max(0, Math.min(root.count - 1, i));
        settle.restart();
    }
    function addVisualizer() {
        if (root.count >= root.maxVisualizers)
            return;
        var arr = (adapter.extras || []).slice();
        // Seed from the active instance, nudged so the new one is not hidden
        // exactly under it, and given a fresh box so it is easy to grab.
        var seed = Object.assign({}, root.activeData);
        seed.x = Math.max(-0.2, Math.min(0.8, (seed.x || 0) + 0.06));
        seed.y = Math.max(-0.2, Math.min(0.8, (seed.y || 0.58) - 0.12));
        arr.push(seed);
        adapter.extras = arr;
        adapter.active = arr.length;   // the new extra is the last instance
        file.writeAdapter();
    }
    function applyPrimary(o) {
        adapter.style = o.style; adapter.shape = o.shape;
        adapter.color = o.color || ""; adapter.color2 = o.color2 || "";
        adapter.gradient = o.gradient === true;
        adapter.bars = o.bars; adapter.thickness = o.thickness; adapter.bloom = o.bloom;
        adapter.reflection = o.reflection; adapter.idleWave = o.idleWave;
        adapter.mirror = o.mirror; adapter.segments = o.segments;
        adapter.gain = o.gain; adapter.smoothing = o.smoothing; adapter.peaks = o.peaks;
        adapter.spin = o.spin; adapter.x = o.x; adapter.y = o.y; adapter.w = o.w;
        adapter.h = o.h; adapter.grow = o.grow; adapter.angle = o.angle;
        adapter.tiltX = o.tiltX; adapter.tiltY = o.tiltY;
    }
    function removeVisualizer(i) {
        var idx = i === undefined ? root.active : i;
        if (idx <= 0) {
            // Removing the primary promotes the first extra into the flat slot, so
            // there is always a primary; refuse if it is the only visualiser.
            var ex = (adapter.extras || []).slice();
            if (ex.length === 0)
                return;
            var promoted = ex.shift();
            root.applyPrimary(promoted);
            adapter.extras = ex;
        } else {
            var arr = (adapter.extras || []).slice();
            if (idx - 1 < arr.length)
                arr.splice(idx - 1, 1);
            adapter.extras = arr;
        }
        adapter.active = Math.max(0, Math.min(root.count - 1, adapter.active));
        file.writeAdapter();
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/visualizer.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool enabled: true
            property int bars: 64
            property real thickness: 0.58
            property real bloom: 0.6
            property real reflection: 0.1
            property bool idleWave: true
            property string style: "bars"
            property string shape: "rounded"
            property string color: ""
            property string color2: ""
            property bool gradient: false
            property bool mirror: false
            property int segments: 10
            property int fps: 30
            property bool adaptive: true
            property real smoothing: 0.5
            property real gain: 1.0
            property bool peaks: false
            property real spin: 0
            property real x: 0
            property real y: 0.58
            property real w: 1
            property real h: 0.42
            property string grow: "up"
            property real angle: 0
            property real tiltX: 0
            property real tiltY: 0
            // Additional visualisers beyond the primary, each a full per-viz
            // object, and which instance the desktop editor is tuning.
            property var extras: []
            property int active: 0
        }
    }

    // A config written before the box carries an anchored position, height, span
    // and origin instead; fold those into the box once so the spectrum stays where
    // its owner put it, then keep only the box.
    function migrate() {
        var o = {};
        try {
            o = JSON.parse(file.text()) || {};
        } catch (e) {
            return false;
        }
        if (o.x !== undefined)
            return o.style === "circle";
        var pos = o.position || "bottom";
        var depth = typeof o.height === "number" ? o.height : 0.42;
        var span = typeof o.span === "number" ? o.span : 1;
        var align = o.align || "center";
        var polar = ["radial", "orb", "spiral", "circle"].indexOf(o.style) >= 0;
        if (polar) {
            var r = (typeof o.size === "number" ? o.size : 0.3);
            var ox = typeof o.originX === "number" ? o.originX : 0.5;
            var oy = typeof o.originY === "number" ? o.originY : 0.5;
            adapter.w = r * 2 * 0.625;   // the radius was a fraction of the short edge
            adapter.h = r * 2;
            adapter.x = ox - adapter.w / 2;
            adapter.y = oy - adapter.h / 2;
            adapter.grow = "center";
        } else {
            var off = align === "start" ? 0 : (align === "end" ? 1 - span : (1 - span) / 2);
            var vertical = pos === "left" || pos === "right";
            adapter.w = vertical ? depth : span;
            adapter.h = vertical ? span : depth;
            adapter.x = pos === "right" ? 1 - depth : (vertical ? 0 : off);
            adapter.y = pos === "top" ? 0
                : (pos === "center" ? (1 - depth) / 2 : (vertical ? off : 1 - depth));
            adapter.grow = pos === "top" ? "down"
                : (pos === "center" ? "center"
                : (pos === "left" ? "right" : (pos === "right" ? "left" : "up")));
        }
        return true;
    }

    // A box saved while overhang was still allowed (or by hand) is folded back
    // inside the screen once, primary and extras alike; true when one moved.
    // Best-effort aspect from whatever screen is up first; a stored box off by
    // a turn on a differently-shaped monitor still lands closer than ignoring
    // the turn entirely, and a live drag re-fits against the real screen anyway.
    function fitStored() {
        var moved = false;
        var scr = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        var aspect = (scr && scr.height > 0) ? scr.width / scr.height : 1;
        var b = root.fitBox(adapter.x, adapter.y, adapter.w, adapter.h, adapter.angle, aspect);
        if (b.x !== adapter.x || b.y !== adapter.y || b.w !== adapter.w || b.h !== adapter.h) {
            adapter.x = b.x; adapter.y = b.y; adapter.w = b.w; adapter.h = b.h;
            moved = true;
        }
        var arr = (adapter.extras || []).slice();
        for (var i = 0; i < arr.length; i++) {
            var e = arr[i] || {};
            var f = root.fitBox(Number(e.x) || 0, Number(e.y) || 0, Number(e.w) || 1, Number(e.h) || 0.42,
                                Number(e.angle) || 0, aspect);
            if (f.x !== e.x || f.y !== e.y || f.w !== e.w || f.h !== e.h) {
                arr[i] = Object.assign({}, e, f);
                moved = true;
            }
        }
        if (moved)
            adapter.extras = arr;
        return moved;
    }

    Component.onCompleted: {
        if (!file.text()) {
            file.writeAdapter();
            return;
        }
        var write = root.migrate();
        if (adapter.style === "circle") {
            adapter.style = "orb";
            write = true;
        }
        if (root.fitStored())
            write = true;
        if (write)
            file.writeAdapter();
    }
}
