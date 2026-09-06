pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."
import "../schema/WindowsPage.js" as Schema

// Windows: everything about a Hyprland window in one place -- Layout (tiling,
// gaps, behaviour), Look (shape, opacity, blur, shadows, glow), Borders
// (thickness, colours, gradient) and Motion (open/close, wobble). Every setting
// rides the hypr draft (hub.hyprVal/hyprEdit); the write ledger and Save belong
// to the shell. Rendered from the schema through the shared SchemaPage, so the
// deep knobs fold under the rail's Advanced switch and the bento grid handles
// space. A dependent row hides until its parent is on. The compositor plugins
// (title bars, glass, image borders) live on the Plugins page.
Item {
    id: pg
    property var hub

    readonly property string pTitle: I18n.tr("Windows")
    readonly property string pEyebrow: I18n.tr("DESKTOP")
    readonly property string pBlurb: I18n.tr("How your windows look and behave: layout, shape, blur, shadows, borders, and motion.")

    readonly property bool ready: pg.hub ? pg.hub.hyprLoaded === true : false
    function hv(path) { return pg.hub ? pg.hub.hyprVal(path) : undefined }
    function cv(path) { return pg.hub ? pg.hub.hyprCommittedVal(path) : undefined }

    // per-row visibility: a dependent stays hidden until its parent toggle is on
    // or the relevant layout is selected. Mirrors the gates the settings carried
    // when they lived on the Appearance page.
    function gateOk(key, d) {
        switch (key) {
        case "dwindle.preserveSplit": case "dwindle.smartSplit": case "dwindle.smartResizing":
        case "dwindle.defaultSplitRatio": case "dwindle.forceSplit": case "dwindle.useActiveForSplits":
            return d["appearance.layout"] === "dwindle";
        case "master.mfact": case "master.newStatus": case "master.newOnTop":
        case "master.orientation": case "master.smartResizing":
            return d["appearance.layout"] === "master";
        case "plugins.hyprscrolling.columnWidth": case "plugins.hyprscrolling.followFocus":
            return d["appearance.layout"] === "scrolling";
        case "appearance.dimStrength": return d["appearance.dimInactive"] === true;
        case "appearance.wobblyWindows": case "appearance.windowStyle": return d["appearance.animations"] === true;
        case "appearance.glowRange": case "appearance.glowColor": return d["appearance.glowEnabled"] === true;
        case "appearance.borderAngleSpeed": return d["appearance.animatedBorder"] === true;
        case "appearance.blurContrast": case "appearance.blurBrightness": case "appearance.blurSpecial":
        case "appearance.blurPopups": case "appearance.blurIgnoreOpacity": case "appearance.blurNewOptimizations":
        case "appearance.blurVibrancyDarkness":
            return d["appearance.blurEnabled"] === true;
        case "appearance.shadowSharp": case "appearance.shadowScale": case "appearance.shadowColor":
            return d["appearance.shadowEnabled"] === true;
        }
        return true;
    }

    // draft/committed are flat maps off the hypr store (dotted keys), the shape
    // the settings sheet reads. draft depends on hyprVal, so an edit rebuilds it.
    readonly property var draft: {
        var d = {};
        if (pg.hub)
            for (var i = 0; i < Schema.rows.length; i++) { var k = Schema.rows[i].key; if (k) d[k] = pg.hv(k); }
        return d;
    }
    readonly property var committed: {
        var d = {};
        if (pg.hub)
            for (var i = 0; i < Schema.rows.length; i++) { var k = Schema.rows[i].key; if (k) d[k] = pg.cv(k); }
        return d;
    }
    readonly property var settingsSchema: {
        var d = pg.draft, out = [];
        for (var i = 0; i < Schema.rows.length; i++)
            if (pg.gateOk(Schema.rows[i].key, d)) out.push(Schema.rows[i]);
        return out;
    }

    function focusKey(k) { sp.focusKey(k) }
    SchemaPage {
        id: sp
        anchors.fill: parent
        schema: pg.settingsSchema
        draft: pg.draft
        defaults: pg.committed
        advanced: pg.hub ? pg.hub.advanced : false
        title: pg.pTitle
        eyebrow: pg.pEyebrow
        blurb: pg.pBlurb
        query: pg.hub ? pg.hub.query : ""
        onEdited: (k, v) => { if (pg.hub) pg.hub.hyprEdit(k, v); }
        onPickRequested: (r) => { if (pg.hub) pg.hub.openPick(r); }
    }
}
