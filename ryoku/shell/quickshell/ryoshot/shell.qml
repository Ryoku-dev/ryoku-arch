//@ pragma DefaultEnv QSG_RENDER_LOOP = threaded

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import "Singletons"
import "lib/coords.js" as Coords
import "lib/AnnotationModel.js" as Ann
import "lib/hittest.js" as Hit
import "lib/redact.js" as Redact
import "lib/constrain.js" as Constrain

ShellRoot {
    id: root

    property var globalSel: null
    property var pressPoint: null
    property bool capturing: false
    property string phase: "selecting"
    property string activeTool: "rect"
    property color activeColor: Theme.accent
    property int activeWidth: 4
    property bool activeFill: false
    property bool activeRough: false

    // Redact and spotlight carry a sub-style that the tool key cycles, so one
    // toolbar slot covers both redaction styles and all three lens shapes.
    property string redactStyle: "mosaic"
    property string spotShape: "ellipse"

    property var model: Ann.create()
    property var draft: null
    property int annRevision: 0
    property bool settingsOpen: false
    property bool shortcutsOpen: false
    property bool textEditing: false
    property string openPopover: ""
    property bool eyedropArmed: false

    property var selectedIndex: null
    property var moveOffset: null
    property var moveStart: null
    property var resizing: null
    property var hoverWindow: null
    property var windowRects: []
    property bool dialogMode: false
    // Manual toolbar offset. The bar parks itself under the region and flips
    // above when there is no room; dragging it covers the case where it still
    // sits over something the user wants to annotate.
    property real toolbarDX: 0
    property real toolbarDY: 0
    property string beautifySrc: ""
    property string beautifyBgImage: ""
    property bool composeActive: false
    property string composeMode: ""
    readonly property bool beautifyHasDefault: bcfg.hasDefault

    function textSize() { return activeWidth * 5 + 8; }

    property var overlays: []
    property int frozenCount: 0

    readonly property bool testRect: Quickshell.env("RYOSHOT_TESTRECT") === "1"
    readonly property string mode: Quickshell.env("RYOSHOT_MODE") === "monitor" ? "monitor" : "region"
    // The hover target starts from the launch mode and Space cycles it, so one
    // keybind reaches a region, a window or a whole monitor.
    property string target: mode
    // RYOSHOT_OPEN=<path>: skip selection and open that image straight in the
    // beautify editor (the capture card's "Beautify after" hands the saved shot
    // here). fromFile makes Escape / close quit, since there is no live capture
    // to fall back to an editing phase over.
    readonly property string openPath: Quickshell.env("RYOSHOT_OPEN") || ""
    property bool fromFile: false
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string shotsDir: (Quickshell.env("XDG_PICTURES_DIR") || (homeDir + "/Pictures")) + "/Screenshots"
    readonly property string ryoshotLuaPath: homeDir + "/.config/hypr/modules/ryoshot.lua"
    readonly property string pinDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku/pins"

    /**
     * Canonical tool list. The toolbar renders it, the key handler derives its
     * shortcuts from it and the shortcut sheet prints it, so the three cannot
     * drift apart.
     */
    readonly property var toolDescriptors: [
        { id: "select",    icon: "select",    label: I18n.tr("Select"),     key: "v" },
        { id: "rect",      icon: "rect",      label: I18n.tr("Rectangle"),  key: "r" },
        { id: "ellipse",   icon: "ellipse",   label: I18n.tr("Ellipse"),    key: "o" },
        { id: "line",      icon: "line",      label: I18n.tr("Line"),       key: "l" },
        { id: "arrow",     icon: "arrow",     label: I18n.tr("Arrow"),      key: "a" },
        { id: "pen",       icon: "pen",       label: I18n.tr("Pen"),        key: "p" },
        { id: "marker",    icon: "marker",    label: I18n.tr("Highlight"),  key: "h" },
        { id: "counter",   icon: "counter",   label: I18n.tr("Step"),       key: "n" },
        { id: "text",      icon: "text",      label: I18n.tr("Text"),       key: "t" },
        { id: "blur",      icon: "blur",      label: I18n.tr("Blur"),       key: "b" },
        { id: "redact",    icon: "redact",    label: I18n.tr("Redact"),     key: "d" },
        { id: "spotlight", icon: "spotlight", label: I18n.tr("Spotlight"),  key: "s" },
        { id: "magnify",   icon: "magnify",   label: I18n.tr("Zoom"),       key: "z" },
        { id: "ocr",       icon: "ocr",       label: I18n.tr("Copy text"),  key: "g" }
    ]

    readonly property var toolKeys: {
        var m = {};
        for (var i = 0; i < toolDescriptors.length; i++)
            m[toolDescriptors[i].key] = toolDescriptors[i].id;
        return m;
    }

    property var toolStyle: ({})

    function toolHasFill(t) { return t === "rect" || t === "ellipse"; }
    function isRoughable(t) { return t === "rect" || t === "ellipse" || t === "line" || t === "arrow"; }
    function isFreehand(t) { return t === "pen"; }
    function isEffectTool(t) {
        return t === "blur" || t === "redact" || t === "magnify" || t === "spotlight";
    }

    /** Switches tool, committing any open text and adopting that tool's style. */
    function selectTool(t) {
        if (textEditing) commitText();
        clearSelection();
        root.openPopover = "";
        root.eyedropArmed = false;
        activeTool = t;
        var s = toolStyle[t];
        activeColor = s && s.color ? s.color : Theme.accent;
        activeWidth = s && s.width ? s.width : 4;
        activeFill = s ? (s.filled === true) : false;
    }

    function styleEntry() {
        return { color: String(activeColor), width: activeWidth, filled: activeFill };
    }

    function rememberStyle() {
        var s = Object.assign({}, toolStyle);
        s[activeTool] = styleEntry();
        toolStyle = s;
        persistTimer.restart();
    }

    function setToolColor(c) { activeColor = c; rememberStyle(); }
    function setToolFill(f) { activeFill = f; rememberStyle(); }
    function setToolWidth(w) { activeWidth = w; rememberStyle(); }

    /**
     * Nudges the active width by one notch and pushes it onto an open draft, so
     * a stroke or a text label resizes under the cursor while it is drawn.
     */
    function adjustWidth(dir) {
        var w = Math.max(1, Math.min(20, activeWidth + dir));
        if (w === activeWidth) return;
        setToolWidth(w);
        if (draft) {
            if (draft.type === "text") { draft = Object.assign({}, draft, { size: textSize() }); bumpAnn(); }
            else if (draft.width !== undefined) { draft.width = w; bumpAnn(); }
        }
    }

    /** Coalesces a scroll burst into one settings write. */
    Timer {
        id: persistTimer
        interval: 400
        onTriggered: { Config.toolStyle = root.toolStyle; Config.save(); }
    }

    Connections {
        target: Config
        function onLoaded() {
            if (Config.toolStyle && typeof Config.toolStyle === "object")
                root.toolStyle = Config.toolStyle;
            root.selectTool(root.activeTool);
        }
    }

    // open an existing image straight into beautify (RYOSHOT_OPEN). anchorOverlay
    // needs a globalSel to pick which monitor shows the editor, so seed it to the
    // first screen; beautify itself sizes from the file, not the selection.
    function openForBeautify(path) {
        var scr = Quickshell.screens;
        if (scr.length > 0)
            globalSel = { x: scr[0].x, y: scr[0].y, w: scr[0].width, h: scr[0].height };
        fromFile = true;
        composeActive = false;
        composeMode = "";
        beautifyBgImage = "";
        beautifySrc = path;
        phase = "beautify";
    }
    Component.onCompleted: if (openPath.length > 0) openForBeautify(openPath);

    function beginSelection(gx, gy) {
        pressPoint = { x: gx, y: gy };
        capturing = true;
        globalSel = { x: gx, y: gy, w: 0, h: 0 };
    }
    function updateSelection(gx, gy, mods) {
        if (!pressPoint) return;
        var p = { x: gx, y: gy };
        if (mods & Qt.ShiftModifier) p = Constrain.square(pressPoint, p);
        globalSel = Coords.rectFromPoints(pressPoint, p);
    }
    function endSelection() {
        capturing = false;
        pressPoint = null;
        if (globalSel && globalSel.w > 2 && globalSel.h > 2) { phase = "editing"; hoverWindow = null; }
        else if (hoverWindow) {
            globalSel = { x: hoverWindow.x, y: hoverWindow.y, w: hoverWindow.w, h: hoverWindow.h };
            phase = "editing";
            hoverWindow = null;
        } else globalSel = null;
    }

    /** Starts a region resize; the opposite edge stays anchored for the drag. */
    function beginResize(role, gx, gy) { resizing = role; }
    function updateResize(gx, gy) {
        if (resizing === null || !globalSel) return;
        globalSel = Hit.resizeRect(globalSel, resizing, gx, gy, 8);
    }
    function endResize() { resizing = null; }

    function clampToSel(gx, gy) {
        var x = Math.max(globalSel.x, Math.min(gx, globalSel.x + globalSel.w));
        var y = Math.max(globalSel.y, Math.min(gy, globalSel.y + globalSel.h));
        return { x: x, y: y };
    }

    function placeText(gx, gy) {
        if (textEditing) { commitText(); return; }
        var p = clampToSel(gx, gy);
        draft = { type: "text", points: [p], color: String(activeColor), text: "", size: textSize() };
        textEditing = true;
        bumpAnn();
    }
    function commitText() {
        if (draft && draft.type === "text") {
            if (draft.text && draft.text.length > 0) model.add(draft);
        }
        draft = null;
        textEditing = false;
        bumpAnn();
    }
    function cancelText() {
        draft = null;
        textEditing = false;
        bumpAnn();
    }
    function countCounters() {
        var n = 0, its = model.items;
        for (var i = 0; i < its.length; i++)
            if (its[i].type === "counter") n += 1;
        return n;
    }
    function placeCounter(gx, gy) {
        var p = clampToSel(gx, gy);
        model.add({ type: "counter", points: [p], color: String(activeColor), width: activeWidth, n: countCounters() + 1 });
        bumpAnn();
    }

    function hitTest(gx, gy) { return Hit.hitTest(model.items, gx, gy); }

    function clearSelection() {
        if (selectedIndex !== null) { selectedIndex = null; bumpAnn(); }
    }

    function deleteSelected() {
        if (selectedIndex === null) return;
        model.remove(selectedIndex);
        selectedIndex = null;
        bumpAnn();
    }

    function beginSelect(gx, gy) {
        var idx = hitTest(gx, gy);
        selectedIndex = idx;
        if (idx !== null) {
            capturing = true;
            moveStart = { x: gx, y: gy };
            moveOffset = { x: 0, y: 0 };
        }
        bumpAnn();
    }
    function updateSelect(gx, gy) {
        if (selectedIndex === null || !moveStart) return;
        moveOffset = { x: gx - moveStart.x, y: gy - moveStart.y };
        bumpAnn();
    }
    function endSelect() {
        capturing = false;
        if (selectedIndex !== null && moveOffset
            && (moveOffset.x !== 0 || moveOffset.y !== 0)) {
            model.move(selectedIndex, moveOffset.x, moveOffset.y);
        }
        moveOffset = null;
        moveStart = null;
        bumpAnn();
    }

    /**
     * Grows or shrinks the selected annotation about its centre. A spotlight
     * zooms its lens instead, which is the change that reads as scaling there.
     */
    function scaleSelected(dir) {
        if (selectedIndex === null) return;
        var a = model.items[selectedIndex];
        if (!a) return;
        if (a.type === "spotlight") {
            var z = Math.max(1.0, Math.min(4.0, (a.magnification || 2.0) * (dir > 0 ? 1.1 : 1 / 1.1)));
            a.magnification = z;
            bumpAnn();
            return;
        }
        var f = dir > 0 ? 1.1 : 1 / 1.1;
        var b = Hit.bboxOf(a);
        var cx = b.x + b.w / 2, cy = b.y + b.h / 2;
        for (var i = 0; i < a.points.length; i++) {
            a.points[i].x = cx + (a.points[i].x - cx) * f;
            a.points[i].y = cy + (a.points[i].y - cy) * f;
        }
        if (a.type === "text") a.size = Math.max(8, Math.round((a.size || 16) * f));
        bumpAnn();
    }

    function beginDraw(gx, gy) {
        if (!globalSel || activeTool === "select") return;
        if (activeTool === "text") { placeText(gx, gy); return; }
        if (activeTool === "counter") { placeCounter(gx, gy); return; }
        var p = clampToSel(gx, gy);
        pressPoint = p;
        capturing = true;
        if (isFreehand(activeTool))
            draft = { type: activeTool, points: [p], color: String(activeColor), width: activeWidth };
        else if (activeTool === "marker")
            draft = { type: "marker", points: [p, p], color: String(activeColor), width: activeWidth, filled: true };
        else if (activeTool === "redact")
            draft = { type: "redact", points: [p, p], style: root.redactStyle };
        else if (activeTool === "spotlight")
            draft = { type: "spotlight", points: [p, p], shape: root.spotShape,
                      color: String(activeColor), width: activeWidth, magnification: Config.zoomFactor };
        else if (activeTool === "ocr")
            draft = { type: "ocr", points: [p, p] };
        else
            draft = { type: activeTool, points: [p, p], color: String(activeColor), width: activeWidth,
                      filled: activeFill, rough: activeRough && isRoughable(activeTool) };
        bumpAnn();
    }
    function updateDraw(gx, gy, mods) {
        if (!draft || !pressPoint || draft.type === "text") return;
        var p = clampToSel(gx, gy);
        if (isFreehand(draft.type)) {
            var last = draft.points[draft.points.length - 1];
            if (Math.abs(p.x - last.x) < 2 && Math.abs(p.y - last.y) < 2) return;
            draft.points = draft.points.concat([p]);
        } else {
            if (mods & Qt.ShiftModifier) p = clampToSel2(Constrain.constrain(draft.type, pressPoint, p));
            draft.points = [pressPoint, p];
        }
        bumpAnn();
    }
    function clampToSel2(p) { return clampToSel(p.x, p.y); }

    function endDraw() {
        capturing = false;
        if (!draft || draft.type === "text") return;
        var kept = draft;
        if (isFreehand(kept.type)) {
            if (kept.points.length >= 2) model.add(kept);
        } else {
            var p0 = kept.points[0], p1 = kept.points[1];
            var dx = Math.abs(p1.x - p0.x), dy = Math.abs(p1.y - p0.y);
            var big = kept.type === "line" || kept.type === "arrow"
                ? Math.hypot(dx, dy) > 4
                : dx > 2 && dy > 2;
            if (big) {
                if (kept.type === "ocr") { draft = null; pressPoint = null; runOcr(p0, p1); return; }
                model.add(kept);
                if (kept.type === "redact" && kept.style !== "solid")
                    samplePalette(model.items.length - 1);
            }
        }
        draft = null;
        pressPoint = null;
        bumpAnn();
    }
    function bumpAnn() { annRevision += 1; }

    function undo() { if (model.undo()) { selectedIndex = null; moveOffset = null; moveStart = null; bumpAnn(); } }
    function redo() { if (model.redo()) { selectedIndex = null; moveOffset = null; moveStart = null; bumpAnn(); } }

    function cycleRedactStyle() {
        redactStyle = redactStyle === "mosaic" ? "solid" : "mosaic";
    }
    function cycleSpotShape() {
        spotShape = spotShape === "ellipse" ? "rect" : (spotShape === "rect" ? "rounded" : "ellipse");
    }
    function cycleTarget() {
        if (phase !== "selecting") return;
        target = target === "region" ? "monitor" : "region";
        hoverWindow = null;
    }

    function windowAt(gx, gy) {
        var best = null;
        for (var i = 0; i < windowRects.length; i++) {
            var r = windowRects[i];
            if (gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h) {
                if (best === null || r.z < best.z) best = r;
            }
        }
        return best ? { x: best.x, y: best.y, w: best.w, h: best.h } : null;
    }
    function monitorAt(gx, gy) {
        var scr = Quickshell.screens;
        for (var i = 0; i < scr.length; i++) {
            var s = scr[i];
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height)
                return { x: s.x, y: s.y, w: s.width, h: s.height };
        }
        return null;
    }
    function selectMonitor(gx, gy) {
        var m = monitorAt(gx, gy);
        if (!m) return;
        globalSel = m;
        phase = "editing";
        hoverWindow = null;
    }
    /** Ctrl+A during selection takes the whole monitor under the pointer. */
    function wholeMonitor() {
        if (phase !== "selecting") return;
        var w = overlays.length ? overlays[0] : null;
        var m = hoverWindow ? monitorAt(hoverWindow.x, hoverWindow.y) : null;
        if (!m && w) m = { x: w.modelData.x, y: w.modelData.y, w: w.modelData.width, h: w.modelData.height };
        if (!m) return;
        globalSel = m;
        phase = "editing";
        hoverWindow = null;
    }
    function pointerHover(gx, gy) {
        if (phase !== "selecting") { if (hoverWindow !== null) hoverWindow = null; return; }
        hoverWindow = target === "monitor" ? monitorAt(gx, gy) : windowAt(gx, gy);
    }
    function parseWindows(activeWs, json) {
        var rects = [];
        try {
            var arr = JSON.parse(json);
            for (var i = 0; i < arr.length; i++) {
                var c = arr[i];
                if (!c.mapped || c.hidden) continue;
                if (!c.workspace || activeWs.indexOf(c.workspace.id) === -1) continue;
                if (!c.size || c.size[0] <= 0 || c.size[1] <= 0) continue;
                rects.push({ x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], z: c.focusHistoryID });
            }
        } catch (e) { console.log("ryoshot: parseWindows failed: " + e); }
        windowRects = rects;
    }
    function parseActiveWs(json) {
        var ids = [];
        try {
            var arr = JSON.parse(json);
            for (var i = 0; i < arr.length; i++)
                if (arr[i].activeWorkspace) ids.push(arr[i].activeWorkspace.id);
        } catch (e) { console.log("ryoshot: parseActiveWs failed: " + e); }
        return ids;
    }
    function pointerPressed(gx, gy, mods) {
        root.openPopover = "";
        root.shortcutsOpen = false;
        if (phase === "selecting") {
            if (target === "monitor") selectMonitor(gx, gy);
            else beginSelection(gx, gy);
        }
        else if (activeTool === "select") beginSelect(gx, gy);
        else beginDraw(gx, gy);
    }
    function pointerMoved(gx, gy, mods) {
        if (phase === "selecting") updateSelection(gx, gy, mods);
        else if (activeTool === "select") updateSelect(gx, gy);
        else updateDraw(gx, gy, mods);
    }
    function pointerReleased() {
        if (phase === "selecting") endSelection();
        else if (activeTool === "select") endSelect();
        else endDraw();
    }
    function pointerWheel(dir) {
        if (phase !== "editing") return;
        if (activeTool === "select" && selectedIndex !== null) scaleSelected(dir);
        else adjustWidth(dir);
    }

    // Match Capture.qml's pattern exactly so both capture paths drop identically
    // named files in the same folder: a UTC stamp + "_screenshot.png".
    function timestampName() {
        var d = new Date();
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return d.getUTCFullYear() + "_" + p(d.getUTCMonth() + 1) + "_" + p(d.getUTCDate())
            + "_" + p(d.getUTCHours()) + "_" + p(d.getUTCMinutes()) + "_" + p(d.getUTCSeconds()) + "_screenshot.png";
    }
    readonly property string saveRoot: Config.saveDir.length > 0 ? Config.saveDir : shotsDir
    readonly property string defaultPath: saveRoot + "/" + timestampName()

    function anchorOverlay() {
        if (!globalSel) return null;
        for (var i = 0; i < overlays.length; i++) {
            var w = overlays[i];
            var s = w.modelData;
            if (globalSel.x >= s.x && globalSel.x < s.x + s.width
                && globalSel.y >= s.y && globalSel.y < s.y + s.height) return w;
        }
        return overlays.length ? overlays[0] : null;
    }

    /** The overlay whose monitor holds a global point, for a local-rect grab. */
    function overlayAt(gx, gy) {
        for (var i = 0; i < overlays.length; i++) {
            var s = overlays[i].modelData;
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) return overlays[i];
        }
        return anchorOverlay();
    }

    function spansMonitors() {
        if (!globalSel) return false;
        var hit = 0;
        for (var i = 0; i < overlays.length; i++) {
            var s = overlays[i].modelData;
            if (Coords.intersectRect(globalSel, { x: s.x, y: s.y, width: s.width, height: s.height })) hit++;
        }
        return hit > 1;
    }

    function grabTo(path, after) {
        var w = anchorOverlay();
        if (!w) { if (after) after(false); return; }
        if (spansMonitors()) { seamStitch(path, after); return; }
        w.grabExport(path, function (ok) {
            console.log("ryoshot: grab " + path + " => " + ok);
            if (after) after(ok);
        });
    }

    function seamStitch(path, after) {
        var screens = [];
        for (var i = 0; i < overlays.length; i++) {
            var s = overlays[i].modelData;
            screens.push({ x: s.x, y: s.y, width: s.width, height: s.height });
        }
        var plan = Coords.stitchPlan(globalSel, screens);
        if (plan.slices.length === 0) { if (after) after(false); return; }
        // one screen: grab it straight, at native resolution (crisp, no stitch).
        if (plan.slices.length === 1) { overlays[plan.slices[0].screen].grabExport(path, after); return; }
        // spanning: grab each slice at its LOGICAL size so mixed-scale monitors
        // land on one logical canvas without a HiDPI slice overflowing the seam.
        var parts = [], done = 0, okAll = true;
        for (var j = 0; j < plan.slices.length; j++) {
            (function (sl, idx) {
                var tmp = "/tmp/ryoshot-seam-" + idx + ".png";
                parts.push({ tmp: tmp, ox: sl.ox, oy: sl.oy });
                overlays[sl.screen].grabExport(tmp, function (ok) {
                    if (!ok) okAll = false;
                    done += 1;
                    if (done === plan.slices.length) root.compositeSlices(parts, plan.canvas, path, okAll, after);
                }, Qt.size(Math.round(sl.local.w), Math.round(sl.local.h)));
            })(plan.slices[j], j);
        }
    }

    function compositeSlices(parts, canvas, path, okAll, after) {
        if (!okAll) { console.log("ryoshot: seam-stitch slice grab failed"); if (after) after(false); return; }
        var args = ["magick", "-size", canvas.w + "x" + canvas.h, "xc:black"];
        for (var i = 0; i < parts.length; i++)
            args = args.concat([parts[i].tmp, "-geometry", "+" + parts[i].ox + "+" + parts[i].oy, "-composite"]);
        args.push(path);
        stitchProc.runWith(args, after);
    }

    // shutter cue: the daemon owns the shell's event sounds, so a completed
    // capture asks it to play rather than shipping an asset in this config.
    function shutter() { Quickshell.execDetached(["ryoku-shell", "sound", "shutter"]); }

    Timer { id: quitTimer; interval: 250; onTriggered: Qt.quit() }
    function quitSoon() { quitTimer.restart(); }

    function notifySend(title, body) {
        Quickshell.execDetached(body && body.length > 0
            ? ["notify-send", "-a", "ryoku", title, body]
            : ["notify-send", "-a", "ryoku", title]);
    }

    /** A saved shot carries its own thumbnail, so the toast shows the result. */
    function notifyShot(title, path) {
        Quickshell.execDetached(["notify-send", "-a", "ryoku", "-i", path, title, path]);
    }

    /**
     * Startup watchdog. When the compositor or driver refuses a graphics context
     * for the layer surface, Qt logs it but QML never hears: the process would
     * sit in the event loop holding the single-instance lock, turning every
     * later keypress into a no-op. FrameAnimation only ticks on a real render
     * pass, so no tick after 15s means the overlay will never appear.
     */
    property bool framePainted: false

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            if (root.framePainted) return;
            console.error("ryoshot: no frame rendered 15s after launch, giving up");
            root.notifySend(I18n.tr("ryoshot could not draw its overlay"),
                I18n.tr("graphics init failed, press the key again"));
            quitFallback.start();
        }
    }
    Timer {
        id: quitFallback
        interval: 3000
        onTriggered: Qt.quit()
    }

    // Export exactly once per session. The beautify compose can emit copy/save
    // more than once as overlays settle; without this guard each emission spawns
    // another clip-copy, and the racing wl-copy owners cancel out so the live
    // selection ends up empty (or replaced). The first grab wins; the rest no-op.
    property bool exported: false

    // Hand the copy to the persistent ryoku-shell daemon: it owns the Wayland
    // selection (so it survives ryoshot quitting) and ingests the entry into
    // clipboard history directly. A wl-copy run from ryoshot itself would die
    // with the app and never reach history.
    function copyImageAndQuit(file) {
        if (root.exported) return;
        root.exported = true;
        Quickshell.execDetached(["ryoku-shell", "clip-copy", "image/png", file]);
        if (Config.copyOnSave) {
            Quickshell.execDetached(["sh", "-c",
                "mkdir -p \"$(dirname \"$2\")\"; [ \"$1\" = \"$2\" ] || cp -- \"$1\" \"$2\"", "sh", file, root.defaultPath]);
        }
        root.quitSoon();
        root.notifySend(I18n.tr("Screenshot copied to clipboard"), "");
    }
    function copyTextAndQuit(text) {
        if (root.exported) return;
        root.exported = true;
        Quickshell.execDetached(["sh", "-c",
            "f=$(mktemp); printf %s \"$1\" > \"$f\"; ryoku-shell clip-copy text/plain \"$f\"; rm -f \"$f\"", "sh", text]);
        root.quitSoon();
    }
    // Save straight to the Screenshots folder (no dialog), matching Super+S. A
    // beautify render arrives as a temp file and is copied in.
    function saveToScreenshots(src) {
        if (root.exported) return;
        root.exported = true;
        var dest = root.defaultPath;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$2\")\"; [ \"$1\" = \"$2\" ] || cp -- \"$1\" \"$2\"", "sh", src, dest]);
        if (Config.copyOnSave)
            Quickshell.execDetached(["ryoku-shell", "clip-copy", "image/png", src]);
        root.notifyShot(I18n.tr("Screenshot saved"), dest);
        root.quitSoon();
    }

    function doCopy() {
        var auto = defaultPath;
        grabTo(auto, function (ok) {
            if (ok) { root.shutter(); root.copyImageAndQuit(auto); }
            else Qt.quit();
        });
    }

    function doSave() {
        var auto = root.defaultPath;
        grabTo(auto, function (ok) {
            if (!ok) { Qt.quit(); return; }
            root.shutter();
            if (Config.copyOnSave)
                Quickshell.execDetached(["ryoku-shell", "clip-copy", "image/png", auto]);
            root.notifyShot(I18n.tr("Screenshot saved"), auto);
            root.quitSoon();
        });
    }

    function doCopyAndSave() {
        var auto = root.defaultPath;
        grabTo(auto, function (ok) {
            if (!ok) { Qt.quit(); return; }
            root.shutter();
            root.notifyShot(I18n.tr("Screenshot saved"), auto);
            root.copyImageAndQuit(auto);
        });
    }

    function doUpload() {
        var tmp = "/tmp/ryoshot-upload.png";
        grabTo(tmp, function (ok) {
            if (ok) { root.shutter(); uploadProc.run(tmp); }
            else Qt.quit();
        });
    }

    /**
     * Pins the finished shot: the PNG lands in the pin directory, the poke file
     * wakes an already running host, and the flock spawn starts one if there is
     * none. ryoshot then leaves, so the pin outlives it.
     */
    function doPin() {
        if (root.exported) return;
        var id = String(Date.now()) + "-" + String(Math.floor(Math.random() * 100000));
        var path = root.pinDir + "/pin-" + id + ".png";
        Quickshell.execDetached(["mkdir", "-p", root.pinDir]);
        grabTo("/tmp/ryoshot-pin.png", function (ok) {
            if (!ok) { Qt.quit(); return; }
            root.exported = true;
            root.shutter();
            Spawn.run(["sh", "-c",
                "mkdir -p \"$1\"; cp -- \"$2\" \"$3\"; date +%s%N > \"$1/.poke\"; "
                + "flock -n -o /tmp/ryopin.lock qs -c ryopin >/dev/null 2>&1 &",
                "sh", root.pinDir, "/tmp/ryoshot-pin.png", path]);
            root.quitSoon();
        });
    }

    /**
     * Copies the text inside a dragged region. The crop comes from the annotated
     * scene, so a blur or a redaction placed over text is honoured and the text
     * under it cannot be read back out.
     */
    function runOcr(p0, p1) {
        var gx = Math.min(p0.x, p1.x), gy = Math.min(p0.y, p1.y);
        var w = Math.abs(p1.x - p0.x), h = Math.abs(p1.y - p0.y);
        var ov = overlayAt(gx, gy);
        if (!ov) { bumpAnn(); return; }
        var s = ov.modelData;
        var tmp = "/tmp/ryoshot-ocr.png";
        ov.grabRegion({ x: gx - s.x, y: gy - s.y, w: w, h: h }, tmp, function (ok) {
            if (!ok) { root.notifySend(I18n.tr("Could not read that region"), ""); return; }
            root.exported = true;
            Quickshell.execDetached(["ryoku-cmd-ocr", "--file", tmp]);
            root.quitSoon();
        });
        bumpAnn();
    }

    /**
     * Reads the dominant colours out of a fresh redaction. Until they arrive the
     * block paints solid, so the source is never briefly legible.
     */
    function samplePalette(index) {
        var a = model.items[index];
        if (!a || a.points.length < 2) return;
        var gx = Math.min(a.points[0].x, a.points[1].x), gy = Math.min(a.points[0].y, a.points[1].y);
        var w = Math.abs(a.points[1].x - a.points[0].x), h = Math.abs(a.points[1].y - a.points[0].y);
        var ov = overlayAt(gx, gy);
        if (!ov) return;
        var s = ov.modelData;
        var tmp = "/tmp/ryoshot-redact.png";
        a.seed = Redact.seedFor({ x: Math.round(gx), y: Math.round(gy), w: Math.round(w), h: Math.round(h) });
        ov.grabPlate({ x: gx - s.x, y: gy - s.y, w: w, h: h }, tmp, function (ok) {
            if (ok) palProc.read(index, tmp);
        }, Qt.size(Math.min(64, Math.max(1, Math.round(w))), Math.min(64, Math.max(1, Math.round(h)))));
    }

    Process {
        id: palProc
        property int target: -1
        stdout: StdioCollector { id: palOut }
        function read(index, file) {
            target = index;
            command = ["magick", file, "-alpha", "off", "-colors", "6", "-unique-colors", "txt:-"];
            running = true;
        }
        onExited: (code) => {
            var idx = palProc.target;
            palProc.target = -1;
            if (code !== 0 || idx < 0 || idx >= root.model.items.length) return;
            var found = palOut.text.match(/#[0-9A-Fa-f]{6}/g);
            if (!found || found.length === 0) return;
            var uniq = [];
            for (var i = 0; i < found.length; i++)
                if (uniq.indexOf(found[i]) === -1) uniq.push(found[i]);
            root.model.items[idx].pal = uniq;
            root.bumpAnn();
        }
    }

    // toolbar Copy/Save with a saved beautify default: bake the default and export
    // straight away, skipping the editor.
    function styledExport(mode) {
        if (root.textEditing) root.commitText();
        root.clearSelection();
        root.beautifySrc = "";
        root.grabTo("/tmp/ryoshot-beautify-src.png", function (ok) {
            if (!ok) return;
            root.shutter();
            root.composeMode = mode;
            root.composeActive = true;
            root.beautifySrc = "/tmp/ryoshot-beautify-src.png";
            root.phase = "beautify";
        });
    }
    function exportCopyOrStyled() { if (root.beautifyHasDefault) styledExport("copy"); else root.doCopy(); }
    function exportSaveOrStyled() { if (root.beautifyHasDefault) styledExport("save"); else root.doSave(); }

    function openBeautify() {
        if (root.textEditing) root.commitText();
        root.clearSelection();
        root.beautifySrc = "";
        root.grabTo("/tmp/ryoshot-beautify-src.png", function (ok) {
            if (!ok) return;
            root.beautifySrc = "/tmp/ryoshot-beautify-src.png";
            root.phase = "beautify";
        });
    }

    FileView {
        id: beautifyCfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/ryoshot-beautify.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter { id: bcfg; property bool hasDefault: false }
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", root.saveRoot]
        Component.onCompleted: running = true
    }

    Process {
        id: bgDialog
        stdout: StdioCollector { id: bgOut }
        function open() {
            command = ["sh", "-c",
                "zenity --file-selection --file-filter='Images | *.png *.jpg *.jpeg *.webp *.bmp' 2>/dev/null"
                + " || kdialog --getopenfilename ~ 'image/png image/jpeg image/webp' 2>/dev/null",
                "_"];
            running = true;
        }
        onExited: (code) => {
            var chosen = bgOut.text.trim();
            if (code === 0 && chosen.length > 0) root.beautifyBgImage = chosen;
            root.dialogMode = false;
        }
    }

    Process {
        id: uploadProc
        stdout: StdioCollector { id: uploadOut }
        function run(file) {
            command = ["curl", "-sf", "--max-time", "30", "-A", "Mozilla/5.0", "-F", "reqtype=fileupload",
                "-F", "time=72h", "-F", "fileToUpload=@" + file,
                "https://litterbox.catbox.moe/resources/internals/api.php"];
            running = true;
        }
        onExited: (code) => {
            var url = uploadOut.text.trim();
            console.log("ryoshot: upload exit " + code + " url=" + JSON.stringify(url));
            if (code === 0 && url.indexOf("http") === 0) root.copyTextAndQuit(url);
            else Qt.quit();
        }
    }

    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector { id: monitorsOut }
        onExited: { clientsProc.activeWs = root.parseActiveWs(monitorsOut.text); clientsProc.running = true; }
    }

    Process {
        id: clientsProc
        property var activeWs: []
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { id: clientsOut }
        onExited: root.parseWindows(activeWs, clientsOut.text)
    }

    Process {
        id: stitchProc
        property var cb: null
        function runWith(args, after) { cb = after; command = args; running = true; }
        onExited: (code) => {
            console.log("ryoshot: seam-stitch composite exit " + code);
            var f = cb;
            cb = null;
            if (f) f(code === 0);
        }
    }

    function noteFrozen() {
        frozenCount += 1;
        if (testRect && frozenCount >= Quickshell.screens.length) testDriver.start();
    }

    function toolbarFor(win) {
        if (phase !== "editing" || !globalSel) return { visible: false, x: 0, y: 0 };
        if (anchorOverlay() !== win) return { visible: false, x: 0, y: 0 };
        return { visible: true };
    }

    /** The staged Escape ladder: the innermost open thing closes first. */
    function escapeStep() {
        if (root.eyedropArmed) { root.eyedropArmed = false; return; }
        if (root.textEditing) { root.cancelText(); return; }
        if (root.openPopover.length > 0) { root.openPopover = ""; return; }
        if (root.shortcutsOpen) { root.shortcutsOpen = false; return; }
        if (root.settingsOpen) { root.settingsOpen = false; return; }
        if (root.selectedIndex !== null) { root.clearSelection(); return; }
        if (root.phase === "beautify") {
            if (root.fromFile) Qt.quit();
            else root.phase = "editing";
            return;
        }
        Qt.quit();
    }

    /** Keys that apply once a region exists. Returns true when one matched. */
    function editKey(e) {
        var ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
        if (ctrl) {
            if (e.key === Qt.Key_C) { root.exportCopyOrStyled(); return true; }
            if (e.key === Qt.Key_S) { root.exportSaveOrStyled(); return true; }
            if (e.key === Qt.Key_P) { root.doPin(); return true; }
            if (e.key === Qt.Key_U) { root.doUpload(); return true; }
            if (e.key === Qt.Key_B) { root.openBeautify(); return true; }
            if (e.key === Qt.Key_Z) { if (shift) root.redo(); else root.undo(); return true; }
            if (e.key === Qt.Key_Y) { root.redo(); return true; }
            return false;
        }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.doCopyAndSave(); return true; }
        if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
            if (root.selectedIndex !== null) { root.deleteSelected(); return true; }
            return false;
        }
        if (e.key === Qt.Key_BracketLeft) { root.adjustWidth(-1); return true; }
        if (e.key === Qt.Key_BracketRight) { root.adjustWidth(1); return true; }
        if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8) {
            var sw = Theme.swatches[e.key - Qt.Key_1];
            if (sw !== undefined) { root.setToolColor(sw); return true; }
            return false;
        }
        if (e.key === Qt.Key_F) { root.setToolFill(!root.activeFill); return true; }
        if (e.key === Qt.Key_K) { root.activeRough = !root.activeRough; return true; }
        if (e.key === Qt.Key_I) { root.eyedropArmed = true; root.openPopover = ""; return true; }
        if (e.key === Qt.Key_Question || (shift && e.key === Qt.Key_Slash)) {
            root.shortcutsOpen = !root.shortcutsOpen;
            return true;
        }
        var letter = String.fromCharCode(e.key).toLowerCase();
        var tool = root.toolKeys[letter];
        if (tool !== undefined) {
            if (tool === root.activeTool && tool === "redact") root.cycleRedactStyle();
            else if (tool === root.activeTool && tool === "spotlight") root.cycleSpotShape();
            else root.selectTool(tool);
            return true;
        }
        return false;
    }

    /** Keys that apply while the region is still being chosen. */
    function selectKey(e) {
        if (e.key === Qt.Key_Space) { root.cycleTarget(); return true; }
        if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) { root.wholeMonitor(); return true; }
        if (e.key === Qt.Key_Question) { root.shortcutsOpen = !root.shortcutsOpen; return true; }
        return false;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: !root.dialogMode

            anchors { top: true; left: true; right: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "ryoshot"

            readonly property string scrName: win.modelData.name
            readonly property bool showToolbar: root.toolbarFor(win).visible

            readonly property var selLocal: root.globalSel
                ? Coords.intersectRect(root.globalSel,
                    { x: win.modelData.x, y: win.modelData.y, width: win.width, height: win.height })
                : null

            FrameAnimation {
                running: win.visible && !root.framePainted
                onTriggered: root.framePainted = true
            }

            FocusScope {
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: root.escapeStep()
                Keys.onPressed: (e) => {
                    if (root.textEditing) return;
                    var handled = root.phase === "selecting" ? root.selectKey(e) : root.editKey(e);
                    if (handled) e.accepted = true;
                }

                Overlay {
                    id: ov
                    anchors.fill: parent
                    screenData: win.modelData
                    globalSel: root.globalSel
                    capturing: root.capturing
                    model: root.model
                    draft: root.draft
                    annRevision: root.annRevision
                    textEditing: root.textEditing
                    selectedIndex: root.selectedIndex
                    moveOffset: root.moveOffset
                    hoverWindow: root.hoverWindow
                    resizable: root.phase === "editing"
                    eyedropArmed: root.eyedropArmed

                    onPressedAt: (gx, gy, mods) => root.pointerPressed(gx, gy, mods)
                    onMovedTo: (gx, gy, mods) => root.pointerMoved(gx, gy, mods)
                    onHovered: (gx, gy) => root.pointerHover(gx, gy)
                    onReleased: root.pointerReleased()
                    onWheeled: (dir) => root.pointerWheel(dir)
                    onFrozen: root.noteFrozen()
                    onTextChanged: (t) => { if (root.draft && root.draft.type === "text") { root.draft.text = t; root.bumpAnn(); } }
                    onTextCommitted: root.commitText()
                    onResizeStarted: (role, gx, gy) => root.beginResize(role, gx, gy)
                    onResizeMoved: (gx, gy) => root.updateResize(gx, gy)
                    onResizeEnded: root.endResize()
                    onSampled: (c) => { root.setToolColor(c); root.eyedropArmed = false; }
                }

                Toolbar {
                    id: toolbar
                    visible: win.showToolbar && win.selLocal !== null
                    tools: root.toolDescriptors
                    activeTool: root.activeTool
                    activeColor: root.activeColor
                    activeWidth: root.activeWidth
                    activeFill: root.activeFill
                    activeRough: root.activeRough
                    hasFill: root.toolHasFill(root.activeTool)
                    openPopover: root.openPopover
                    canUndo: { root.annRevision; return root.model ? root.model.canUndo() : false; }
                    canRedo: { root.annRevision; return root.model ? root.model.canRedo() : false; }
                    settingsOpen: root.settingsOpen

                    x: {
                        if (!win.selLocal) return 0;
                        var cx = win.selLocal.x + win.selLocal.w / 2 - width / 2 + root.toolbarDX;
                        return Math.max(8, Math.min(cx, win.width - width - 8));
                    }
                    y: {
                        if (!win.selLocal) return 0;
                        var below = win.selLocal.y + win.selLocal.h + 12;
                        if (below + height > win.height - 8) below = win.selLocal.y - height - 12;
                        return Math.max(8, Math.min(below + root.toolbarDY, win.height - height - 8));
                    }

                    onToolPicked: (t) => root.selectTool(t)
                    onColorButtonClicked: root.openPopover = root.openPopover === "color" ? "" : "color"
                    onWidthButtonClicked: root.openPopover = root.openPopover === "width" ? "" : "width"
                    onFillToggled: root.setToolFill(!root.activeFill)
                    onRoughToggled: root.activeRough = !root.activeRough
                    onUndoRequested: root.undo()
                    onRedoRequested: root.redo()
                    onCopyRequested: root.exportCopyOrStyled()
                    onSaveRequested: root.exportSaveOrStyled()
                    onUploadRequested: root.doUpload()
                    onPinRequested: root.doPin()
                    onHelpRequested: root.shortcutsOpen = !root.shortcutsOpen
                    onSettingsRequested: root.settingsOpen = !root.settingsOpen
                    onBeautifyRequested: root.openBeautify()
                    onDragged: (dx, dy) => { root.toolbarDX += dx; root.toolbarDY += dy; }
                }

                ColorPopover {
                    visible: toolbar.visible && root.openPopover === "color"
                    selected: root.activeColor
                    eyedropArmed: root.eyedropArmed
                    x: Math.max(8, Math.min(toolbar.x + toolbar.colorCenterX - width / 2,
                                            win.width - width - 8))
                    y: toolbar.y - height - 6
                    onPicked: (c) => root.setToolColor(c)
                    onEyedropRequested: { root.openPopover = ""; root.eyedropArmed = true; }
                    onCloseRequested: root.openPopover = ""
                }

                WidthPopover {
                    visible: toolbar.visible && root.openPopover === "width"
                    selected: root.activeWidth
                    x: Math.max(8, Math.min(toolbar.x + toolbar.widthCenterX - width / 2,
                                            win.width - width - 8))
                    y: toolbar.y - height - 6
                    onPicked: (w) => root.setToolWidth(w)
                    onCloseRequested: root.openPopover = ""
                }

                SettingsPanel {
                    id: hotkeyPopover
                    visible: toolbar.visible && root.settingsOpen
                    luaPath: root.ryoshotLuaPath
                    x: Math.max(8, Math.min(toolbar.x + toolbar.gearCenterX - width / 2,
                                            win.width - width - 8))
                    y: Math.max(8, toolbar.y - height - 6)
                    onCloseRequested: root.settingsOpen = false
                    onRebound: Qt.quit()
                }

                ShortcutSheet {
                    anchors.centerIn: parent
                    visible: root.shortcutsOpen && root.anchorOverlay() === win
                    tools: root.toolDescriptors
                    onCloseRequested: root.shortcutsOpen = false
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.phase === "beautify" && root.anchorOverlay() !== win
                    color: Theme.panelSolid
                }

                Beautify {
                    anchors.fill: parent
                    visible: root.phase === "beautify" && root.anchorOverlay() === win
                    srcPath: root.beautifySrc
                    bgImagePath: root.beautifyBgImage
                    composeOnly: root.composeActive
                    composeMode: root.composeMode
                    onCopyRequested: (p) => root.copyImageAndQuit(p)
                    onSaveRequested: (p) => root.saveToScreenshots(p)
                    onPickImageRequested: { root.dialogMode = true; bgDialog.open(); }
                    onCloseRequested: { root.composeActive = false; if (root.fromFile) Qt.quit(); else root.phase = "editing"; }
                }
            }

            Component.onCompleted: root.overlays.push(win)

            function grabExport(path, cb, targetSize) { ov.grabExport(path, cb, targetSize); }
            function grabRegion(rect, path, cb) { ov.grabRegion(rect, path, cb); }
            function grabPlate(rect, path, cb, targetSize) { ov.grabPlate(rect, path, cb, targetSize); }
            function grabToolbar(path, cb) {
                var sched = toolbar.grabToImage(function (r) {
                    var ok = false;
                    try { ok = r ? r.saveToFile(path) : false; } catch (e) { ok = false; }
                    if (cb) cb(ok);
                });
                if (!sched && cb) cb(false);
            }
        }
    }

    Timer {
        id: testDriver
        interval: 400
        repeat: false
        onTriggered: {
            root.globalSel = { x: 2750, y: 350, w: 760, h: 480 };
            root.phase = "editing";
            var bx = 2750, by = 350;
            root.model.add({
                type: "ellipse",
                points: [{ x: bx + 40, y: by + 40 }, { x: bx + 240, y: by + 180 }],
                color: "#4f8fe0", width: 4, filled: false
            });
            root.model.add({
                type: "line",
                points: [{ x: bx + 300, y: by + 60 }, { x: bx + 700, y: by + 200 }],
                color: "#f2c14e", width: 7, filled: false
            });
            root.model.add({
                type: "arrow",
                points: [{ x: bx + 60, y: by + 440 }, { x: bx + 360, y: by + 260 }],
                color: "#e23b3b", width: 5, filled: false
            });
            var pen = [];
            for (var i = 0; i <= 40; i++) {
                var t = i / 40;
                pen.push({ x: bx + 300 + t * 380, y: by + 320 + Math.sin(t * 6.2832) * 60 });
            }
            root.model.add({ type: "pen", points: pen, color: "#5bbf73", width: 3 });
            var mk = [];
            for (var j = 0; j <= 20; j++) {
                var u = j / 20;
                mk.push({ x: bx + 100 + u * 560, y: by + 410 });
            }
            root.model.add({ type: "marker", points: mk, color: "#f2c14e", width: 4 });
            root.model.add({
                type: "blur",
                points: [{ x: bx + 40, y: by + 230 }, { x: bx + 360, y: by + 330 }]
            });
            root.model.add({
                type: "text",
                points: [{ x: bx + 60, y: by + 20 }],
                color: "#ffffff", text: "ryoshot p3b", size: 28
            });
            root.bumpAnn();
            grabTimer.start();
        }
    }

    Timer {
        id: grabTimer
        interval: 250
        repeat: false
        onTriggered: {
            root.grabTo("/tmp/ryoshot-p3b.png", function (ok) {
                console.log("ryoshot-test: annotated grab ok=" + ok);
                var w = root.anchorOverlay();
                if (w) w.grabToolbar("/tmp/ryoshot-toolbar.png", function (tok) {
                    console.log("ryoshot-test: toolbar grab ok=" + tok);
                });
            });
        }
    }
}
