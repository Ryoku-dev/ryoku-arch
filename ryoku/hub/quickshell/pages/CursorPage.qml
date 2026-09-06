pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."
import "../schema/CursorPage.js" as Schema

// Cursor: the pointer, a device in its own right rather than a corner of the
// theme page. Its look (theme, size, idle hiding) and its realistic motion ride
// the hypr draft (hub.hyprVal/hyprEdit); the write ledger and Save belong to the
// shell. Rendered from the schema through the shared SchemaPage, except the
// theme, whose list is scanned at runtime, so it is a catalogue pick.
Item {
    id: pg
    property var hub

    readonly property string pTitle: I18n.tr("Cursor")
    readonly property string pEyebrow: I18n.tr("DEVICES")
    readonly property string pBlurb: I18n.tr("The pointer: its theme, size, idle hiding, and realistic motion.")

    // the Material Bibata toggle is a synthetic key: its state mirrors whether
    // the material variant is the active cursor theme, and flipping it swaps
    // cursor.theme (remembering the prior theme to restore on off).
    readonly property string matVariant: "Bibata-Material-Ryoku"
    readonly property string matFallback: "Bibata-Modern-Ice"
    property string prevTheme: ""

    function hv(path) { return pg.hub ? pg.hub.hyprVal(path) : undefined }
    function cv(path) { return pg.hub ? pg.hub.hyprCommittedVal(path) : undefined }
    function setKey(k, v) { if (pg.hub) pg.hub.hyprEdit(k, v); }

    // the theme list is scanned at runtime, so cursor.theme is a catalogue pick
    // over the installed icon sets, not a fixed enum.
    property var cursorThemes: []
    Process {
        id: cursorsProc
        command: ["ryoku-hub", "hypr", "cursors"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { pg.cursorThemes = JSON.parse(this.text); } catch (e) {} }
        }
    }

    // draft/committed are flat maps off the hypr store (dotted keys), the shape
    // the settings sheet reads. draft depends on hyprVal, so an edit rebuilds it.
    readonly property var draft: {
        var d = {};
        if (pg.hub) {
            for (var i = 0; i < Schema.rows.length; i++) { var k = Schema.rows[i].key; if (k) d[k] = pg.hv(k); }
            d["cursor.material"] = (String(pg.hv("cursor.theme")) === pg.matVariant);
        }
        return d;
    }
    readonly property var committed: {
        var d = {};
        if (pg.hub) {
            for (var i = 0; i < Schema.rows.length; i++) { var k = Schema.rows[i].key; if (k) d[k] = pg.cv(k); }
            d["cursor.material"] = (String(pg.cv("cursor.theme")) === pg.matVariant);
        }
        return d;
    }
    readonly property var settingsSchema: {
        var out = [];
        for (var i = 0; i < Schema.rows.length; i++) {
            var r = Schema.rows[i];
            if (r.key === "cursor.theme")
                out.push({ tab: r.tab, group: r.group, key: r.key, label: r.label,
                           desc: r.desc, ctl: "pick", src: "hypr", opts: pg.cursorThemes });
            else
                out.push(r);
        }
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
        onEdited: (k, v) => {
            if (!pg.hub) return;
            if (k === "cursor.material") {
                if (v) {
                    var cur = String(pg.hv("cursor.theme"));
                    if (cur !== pg.matVariant) pg.prevTheme = cur;
                    pg.hub.hyprEdit("cursor.theme", pg.matVariant);
                    // recolour to the live wallpaper accent right away, so the
                    // pointer follows matugen from the moment it is turned on
                    // rather than showing the packaged fallback until Save.
                    Quickshell.execDetached(["sh", "-c", "command -v ryoku-cursor-material-recolor >/dev/null && ryoku-cursor-material-recolor --force --full"]);
                } else {
                    var back = (pg.prevTheme && pg.prevTheme !== pg.matVariant) ? pg.prevTheme : pg.matFallback;
                    pg.hub.hyprEdit("cursor.theme", back);
                }
                return;
            }
            pg.hub.hyprEdit(k, v);
        }
        onPickRequested: (r) => {
            if (r.key === "cursor.theme") cursorPick.show();
            else if (pg.hub) pg.hub.openPick(r);
        }
    }

    // cursor theme catalogue, one z-plane above the page
    Item {
        id: cursorPick
        anchors.fill: parent
        visible: false
        z: 200
        function show() { visible = true; picker.open(); }
        MouseArea { anchors.fill: parent; onClicked: cursorPick.visible = false }
        Picker {
            id: picker
            anchors.centerIn: parent
            title: I18n.tr("CURSOR THEME")
            options: pg.cursorThemes
            current: pg.hub ? String(pg.hub.hyprVal("cursor.theme")) : ""
            onChose: (k) => { pg.setKey("cursor.theme", k); cursorPick.visible = false; }
            onDismissed: cursorPick.visible = false
        }
    }
}
