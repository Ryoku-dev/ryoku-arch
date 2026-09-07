pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "../Combos.js" as Combos

// Keybinds (DESIGN.md section 8, SYSTEM). Two surfaces under one head: the live
// shortcut legend (every desktop bind, read straight from what Hyprland has
// bound via `ryoku-hub keybinds`) and the custom-bind editor (add/edit/remove
// user shortcuts layered on top). The legend is the source of truth; custom
// binds show in it once saved and reloaded. This is a full-bleed page: it owns
// its whole content region, so it draws its own head, its own tab switch and
// -- because the shell hides its global action bar -- its own Save/Revert
// controls for the shared hypr store. Custom binds live in that store under the
// `keybinds` key; nothing writes to disk until Save. Every value is a Token.
Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    // guard the harness and the pre-load window: the shell injects a real hub
    // exposing hyprVal/hyprEdit; a bare probe object exposes neither.
    readonly property bool hubReady: pg.hub && typeof pg.hub.hyprVal === "function"
    // the live custom-bind array from the draft: a list of { keys, action, value }.
    readonly property var customRows: pg.hubReady ? (pg.hub.hyprVal("keybinds") || []) : []
    // gated so the editor empty state does not flash before `hypr get` returns.
    readonly property bool ready: pg.hubReady ? pg.hub.hyprLoaded === true : false
    readonly property int dirtyCount: pg.hubReady ? (pg.hub.dirty || 0) : 0

    // "apps" = app-role launchers, "system" = the shipped legend, "custom" = the
    // editor. Transient, not persisted.
    property string tab: "apps"

    // the shipped legend, parsed live from binds.lua by the backend. Owned here
    // (a self-contained page fetches its own backend), forwarded to both the
    // legend view and the conflict check.
    property var categories: []

    Process {
        id: legendGet
        command: ["ryoku-hub", "keybinds"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    pg.categories = o.categories || [];
                } catch (e) { console.log("keybinds: legend parse failed: " + e); }
            }
        }
    }

    // ── app roles (Default Apps, merged into this page) ─────────────────────
    // the swappable launcher roles + candidates + each role's shipped combo,
    // from `ryoku-hub apps` (installed candidates flagged). Shown on the Apps
    // tab, where the key rebinds too; the choice is stored in the store's "apps".
    property var roles: []
    Process {
        id: appsGet
        command: ["ryoku-hub", "apps"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    pg.roles = JSON.parse(this.text) || [];
                } catch (e) { console.log("keybinds: apps parse failed: " + e); }
            }
        }
    }

    property var shellState: ({ current: "", choices: [] })
    property string shellError: ""
    property bool shellBusy: false
    Process {
        id: shellGet
        command: ["ryoku-hub", "shell", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    pg.shellState = JSON.parse(this.text);
                } catch (e) {
                    pg.shellError = I18n.tr("Couldn't read the login shell.");
                }
            }
        }
    }
    Process {
        id: shellSet
        stderr: StdioCollector { id: shellSetError }
        onExited: (code, status) => {
            pg.shellBusy = false;
            pg.shellError = code === 0 ? "" : (shellSetError.text.trim() || I18n.tr("Couldn't change the login shell."));
            shellGet.running = true;
        }
    }
    function setShell(key) {
        if (pg.shellBusy || key === pg.shellState.current)
            return;
        pg.shellBusy = true;
        pg.shellError = "";
        shellSet.command = ["ryoku-hub", "shell", "set", key];
        shellSet.running = true;
    }
    function setZshPrompt(mode) {
        if (pg.shellBusy || mode === pg.shellState.zshPrompt)
            return;
        pg.shellBusy = true;
        pg.shellError = "";
        shellSet.command = ["ryoku-hub", "shell", "prompt", mode];
        shellSet.running = true;
    }
    // role -> chosen command (draft); empty/absent uses the shipped fallback.
    readonly property var chosen: pg.hubReady ? (pg.hub.hyprVal("apps") || ({})) : ({})
    function effOf(role, fallback) {
        var v = pg.chosen[role];
        return (v && ("" + v).length) ? ("" + v) : fallback;
    }
    function setApp(role, cmd) {
        if (!pg.hubReady)
            return;
        var cur = pg.hub.hyprVal("apps") || {};
        var m = {};
        for (var k in cur)
            m[k] = cur[k];
        cmd = ("" + (cmd || "")).trim();
        if (!cmd)
            delete m[role];
        else
            m[role] = cmd;
        pg.hub.hyprEdit("apps", m);
    }
    function clearApps() { if (pg.hubReady) pg.hub.hyprEdit("apps", ({})); }
    function hasApps() { return Object.keys(pg.chosen).length > 0; }

    // shipped combos that launch an app role, so the System tab drops them
    // (they live on the Apps tab, where the key rebinds beside the app).
    readonly property var roleComboSet: {
        var s = {};
        for (var i = 0; i < pg.roles.length; i++) {
            var c = pg.roles[i].combo || "";
            if (c.length)
                s[c] = true;
        }
        return s;
    }
    // the legend minus the app-role binds: everything that is a system action.
    readonly property var systemCategories: {
        var out = [];
        for (var c = 0; c < pg.categories.length; c++) {
            var cat = pg.categories[c];
            var kept = [];
            var binds = cat.binds || [];
            for (var b = 0; b < binds.length; b++)
                if (!pg.roleComboSet[binds[b].combo || ""])
                    kept.push(binds[b]);
            if (kept.length)
                out.push({ name: cat.name, binds: kept });
        }
        return out;
    }

    // ── the app catalogue + picker overlay (shared: roles + custom binds) ────
    // every installed application as { name, cmd } for the filterable picker; the
    // command is the parsed Exec, runnable as a keybind or a ryoku-app role.
    readonly property var appCatalog: {
        var out = [];
        var src = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications)
            ? DesktopEntries.applications.values : [];
        for (var i = 0; i < src.length; i++) {
            var e = src[i];
            if (!e || e.noDisplay)
                continue;
            var cmd = ("" + ((e.command || []).join(" "))).trim();
            if (!cmd)
                continue;
            out.push({ name: e.name || cmd, cmd: cmd });
        }
        out.sort(function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()); });
        return out;
    }
    // the picker targets an app role (by name) or a custom row (by index).
    property string appPickRole: ""
    property int appPickCustomRow: -1
    readonly property bool appPicking: pg.appPickRole.length > 0 || pg.appPickCustomRow >= 0
    function openAppPickerRole(role) { pg.appPickCustomRow = -1; pg.appPickRole = role; }
    function openAppPickerCustom(i) { pg.appPickRole = ""; pg.appPickCustomRow = i; }
    function closeAppPicker() { pg.appPickRole = ""; pg.appPickCustomRow = -1; }
    function appPickCurrent() {
        if (pg.appPickRole.length > 0)
            return pg.chosen[pg.appPickRole] || "";
        if (pg.appPickCustomRow >= 0)
            return (pg.customRows[pg.appPickCustomRow] || ({})).value || "";
        return "";
    }
    function appPickTitle() {
        if (pg.appPickCustomRow >= 0)
            return I18n.tr("Command");
        for (var i = 0; i < pg.roles.length; i++)
            if (pg.roles[i].role === pg.appPickRole)
                return I18n.tr(pg.roles[i].label);
        return I18n.tr("App");
    }
    function applyAppPick(cmd) {
        if (pg.appPickRole.length > 0)
            pg.setApp(pg.appPickRole, cmd);
        else if (pg.appPickCustomRow >= 0)
            pg.patch(pg.appPickCustomRow, "value", cmd);
        pg.closeAppPicker();
    }

    // ── conflict detection (shared with the Import page via Combos.js) ───────
    // catches what a hand-edited user.lua never would: a custom combo that
    // shadows a shipped bind, or duplicates another custom one. The rules live
    // in Combos so both pages classify a clash the same way; these thin readers
    // feed it this page's live legend, custom rows and rebinds.
    function normKeys(s) { return Combos.normKeys(s); }
    readonly property var shippedKeys: Combos.shippedKeys(pg.categories, pg.rebinds)
    function customCount(norm) { return Combos.customCount(pg.customRows, norm); }
    function rowConflict(i) { return Combos.rowConflict(pg.customRows, i, pg.shippedKeys); }
    readonly property int conflictCount: {
        var n = 0;
        for (var i = 0; i < pg.customRows.length; i++)
            if (pg.rowConflict(i) !== "")
                n++;
        for (var c = 0; c < pg.categories.length; c++) {
            var binds = pg.categories[c].binds || [];
            for (var b = 0; b < binds.length; b++) {
                var combo = binds[b].combo || "";
                if (pg.isRebound(combo) && pg.comboConflict(combo))
                    n++;
            }
        }
        return n;
    }

    // the four bind actions, key -> visible label. keys are the exact strings the
    // Go backend switches on, so a rename here silently breaks settings.lua.
    readonly property var actionOpts: [
        { "key": "exec", "label": I18n.tr("Run command") },
        { "key": "close", "label": I18n.tr("Close window") },
        { "key": "fullscreen", "label": I18n.tr("Fullscreen") },
        { "key": "togglefloating", "label": I18n.tr("Toggle floating") }
    ]
    function labelIn(opts, key) {
        for (var i = 0; i < opts.length; i++)
            if (opts[i].key === key)
                return opts[i].label;
        return key;
    }
    function keyIn(opts, label) {
        for (var i = 0; i < opts.length; i++)
            if (opts[i].label === label)
                return opts[i].key;
        return label;
    }
    function labelsOf(opts) {
        return opts.map(function (o) { return o.label; });
    }

    // every mutation hands hyprEdit a fresh slice: the array swap rebinds the
    // Repeater and rebuilds the delegate owning a focused field, so text edits
    // commit on editing-finished, not per keystroke.
    function patch(i, key, val) {
        if (!pg.hubReady)
            return;
        var a = (pg.hub.hyprVal("keybinds") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = val;
        pg.hub.hyprEdit("keybinds", a);
    }
    // switching action clears the value: only "exec" carries a command.
    function setAction(i, key) {
        if (!pg.hubReady)
            return;
        var a = (pg.hub.hyprVal("keybinds") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i].action = key;
        if (key !== "exec")
            a[i].value = "";
        pg.hub.hyprEdit("keybinds", a);
    }
    function addRow() {
        if (!pg.hubReady)
            return;
        var a = (pg.hub.hyprVal("keybinds") || []).slice();
        a.push({ "keys": "", "action": "exec", "value": "", "release": false });
        pg.hub.hyprEdit("keybinds", a);
    }
    function removeRow(i) {
        if (!pg.hubReady)
            return;
        var a = (pg.hub.hyprVal("keybinds") || []).slice();
        a.splice(i, 1);
        pg.hub.hyprEdit("keybinds", a);
    }
    function clearAll() {
        if (pg.hubReady)
            pg.hub.hyprEdit("keybinds", []);
    }
    function saveAll() {
        if (pg.hubReady)
            pg.hub.save();
    }
    function revertAll() {
        if (pg.hubReady)
            pg.hub.revert();
    }

    // ── chord recorder ──────────────────────────────────────────────────────
    // The star of this page: instead of typing "SUPER + J", the user clicks
    // record and presses the combo. Capture is safe because the Hub first enters
    // a do-nothing Hyprland submap (modules/record.lua): in a submap only its
    // own binds fire, so a live chord like SUPER + Q passes through to be read
    // here instead of closing the Hub. recordRow is the row being recorded
    // (-1 = idle); the overlay below drives it.
    property int recordRow: -1
    // recordCombo holds a shipped bind's default combo while it is being rebound
    // (recordRow stays -1); either one active means the recorder overlay is up.
    property string recordCombo: ""
    readonly property bool recording: pg.recordRow >= 0 || pg.recordCombo.length > 0

    function enterRecordSubmap() { Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"record\")"]); }
    function exitRecordSubmap() { Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.submap(\"reset\")"]); }

    function startRecord(i) {
        if (!pg.hubReady || i < 0)
            return;
        pg.recordCombo = "";
        pg.recordRow = i;
        pg.enterRecordSubmap();
        recordTimeout.restart();
    }
    // record a new chord for a shipped bind, keyed by its default combo.
    function startRecordShipped(combo) {
        if (!pg.hubReady || !combo)
            return;
        pg.recordRow = -1;
        pg.recordCombo = combo;
        pg.enterRecordSubmap();
        recordTimeout.restart();
    }
    // commit true writes the captured chord to the custom row or the rebind; false cancels.
    function stopRecord(commit, chord) {
        recordTimeout.stop();
        pg.exitRecordSubmap();
        var i = pg.recordRow;
        var combo = pg.recordCombo;
        pg.recordRow = -1;
        pg.recordCombo = "";
        if (!commit || !chord)
            return;
        if (combo.length > 0)
            pg.setRebind(combo, chord);
        else if (i >= 0)
            pg.patch(i, "keys", chord);
    }

    // never leave the keyboard stranded in the record submap: a hard ceiling
    // exits it even if every other path fails.
    Timer {
        id: recordTimeout
        interval: 15000
        onTriggered: pg.stopRecord(false, "")
    }

    // the submap's Escape binding (or any external reset) fires this; if we were
    // still recording, treat it as a cancel so the overlay closes cleanly.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (pg.recording && event.name === "submap" && (event.data === "" || event.data === "reset"))
                pg.stopRecord(false, "");
        }
    }

    // the recorder's key reader lives in Combos.js, shared with the Import
    // page so a captured chord reads into Hyprland's token the same way.
    function chordFrom(event) { return Combos.chordFrom(event); }
    // the shipped bind a normalised chord shadows, by description, for the
    // conflict badge. "" when nothing shipped matches.
    function shippedDescFor(norm) {
        for (var c = 0; c < pg.categories.length; c++) {
            var binds = pg.categories[c].binds || [];
            for (var b = 0; b < binds.length; b++) {
                if (pg.normKeys((binds[b].keys || []).join(" + ")) === norm)
                    return binds[b].desc || I18n.tr("a shipped shortcut");
            }
        }
        return "";
    }

    // ── shipped-bind rebinds ────────────────────────────────────────────────
    // A rebind remaps a shipped chord to a user-chosen one, held as
    // { "SUPER + Q": "SUPER + X" } in the draft and rendered to rebinds.lua, which
    // binds.lua's K() consults. The shipped default combo is the stable id.
    readonly property var rebinds: pg.hubReady ? (pg.hub.hyprVal("keybindRebinds") || ({})) : ({})
    function effectiveCombo(defCombo) {
        var r = pg.rebinds[defCombo];
        return (r && r.length) ? r : defCombo;
    }
    function isRebound(defCombo) {
        var r = pg.rebinds[defCombo];
        return r !== undefined && r !== null && r.length > 0 && r !== defCombo;
    }
    function hasRebinds() {
        for (var k in pg.rebinds)
            if (pg.rebinds[k] && pg.rebinds[k] !== k)
                return true;
        return false;
    }
    function setRebind(defCombo, chord) {
        if (!pg.hubReady)
            return;
        var cur = pg.hub.hyprVal("keybindRebinds") || {};
        var m = {};
        for (var k in cur)
            m[k] = cur[k];
        if (!chord || chord === defCombo)
            delete m[defCombo];
        else
            m[defCombo] = chord;
        pg.hub.hyprEdit("keybindRebinds", m);
    }
    function clearRebind(defCombo) { pg.setRebind(defCombo, ""); }
    function clearRebinds() {
        if (pg.hubReady)
            pg.hub.hyprEdit("keybindRebinds", ({}));
    }

    // norm -> how many shipped (effective) + custom binds hold it; >1 is a clash.
    readonly property var effectiveCounts: {
        var m = {};
        for (var c = 0; c < pg.categories.length; c++) {
            var binds = pg.categories[c].binds || [];
            for (var b = 0; b < binds.length; b++) {
                var n = pg.normKeys(pg.effectiveCombo(binds[b].combo || ""));
                if (n.length)
                    m[n] = (m[n] || 0) + 1;
            }
        }
        for (var i = 0; i < pg.customRows.length; i++) {
            var cn = pg.normKeys(pg.customRows[i].keys);
            if (cn.length)
                m[cn] = (m[cn] || 0) + 1;
        }
        return m;
    }
    function comboConflict(defCombo) {
        var n = pg.normKeys(pg.effectiveCombo(defCombo));
        return n.length > 0 && pg.effectiveCounts[n] > 1;
    }
    // the other bind an effective combo clashes with, by description.
    function conflictNameFor(defCombo) {
        var n = pg.normKeys(pg.effectiveCombo(defCombo));
        for (var c = 0; c < pg.categories.length; c++) {
            var binds = pg.categories[c].binds || [];
            for (var b = 0; b < binds.length; b++) {
                if ((binds[b].combo || "") === defCombo)
                    continue;
                if (pg.normKeys(pg.effectiveCombo(binds[b].combo || "")) === n)
                    return binds[b].desc || I18n.tr("another shortcut");
            }
        }
        for (var i = 0; i < pg.customRows.length; i++)
            if (pg.normKeys(pg.customRows[i].keys) === n)
                return I18n.tr("a custom bind");
        return I18n.tr("another shortcut");
    }

    // display tokens for a raw combo, matching the legend keycaps. mirrors the
    // backend's prettyKey for the chords the recorder can produce, so a rebound
    // row reads like the shipped ones.
    readonly property var capNames: ({
        "SUPER": "Super", "SHIFT": "Shift", "ALT": "Alt", "CTRL": "Ctrl",
        "Return": "Enter", "comma": ",", "period": ".", "grave": "\u0060",
        "Left": "\u2190", "Right": "\u2192", "Up": "\u2191", "Down": "\u2193"
    })
    function comboToCaps(raw) {
        var parts = ("" + raw).split("+");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            var t = parts[i].trim();
            if (t.length)
                out.push(pg.capNames[t] || t);
        }
        return out;
    }

    // ── head: eyebrow, Fraunces title, blurb (matches every settings page) ──
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s6
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "力"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("APPS & KEYS"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Keybinds"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Every desktop shortcut in one place. Apps sets what the launcher keys open (browser, terminal, editor, files, notes) and rebinds those keys; System rebinds the built-in shortcuts; Custom layers your own. Overlaps are flagged as you go.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // marginalia in the head's right margin, dressing the dead space beside the title. Ink only.
    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s1
        kana: "操作"
        index: "04"; label: I18n.tr("APPS & KEYS")
        glyph: "meander"; glyph2: "torii"
    }

    // ── tab switch: Shortcuts (legend) | Custom (editor) ──
    Tabs {
        id: tabs
        anchors.left: parent.left
        anchors.leftMargin: Tokens.s6
        anchors.top: head.bottom
        anchors.topMargin: Tokens.s5
        options: [I18n.tr("Apps"), I18n.tr("System"), I18n.tr("Custom")]
        current: pg.tab === "apps" ? I18n.tr("Apps") : (pg.tab === "system" ? I18n.tr("System") : I18n.tr("Custom"))
        onChose: (label) => pg.tab = (label === I18n.tr("Apps") ? "apps" : (label === I18n.tr("System") ? "system" : "custom"))
    }

    // ── the tab body: a Loader swaps the whole subtree, fading the new one in ──
    Loader {
        id: loader
        anchors {
            left: parent.left; right: parent.right
            top: tabs.bottom; bottom: bar.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
            topMargin: Tokens.s4; bottomMargin: Tokens.s6
        }
        sourceComponent: pg.tab === "apps" ? appsComp : (pg.tab === "system" ? systemComp : customComp)
        onLoaded: {
            if (!item)
                return;
            item.opacity = 0;
            fade.restart();
        }
    }
    // content exchange -> swap token; nothing travels, so a plain fade is right.
    NumberAnimation {
        id: fade
        target: loader.item; property: "opacity"; to: 1
        duration: Tokens.swap; easing.type: Tokens.ease
    }

    // ── the app-role launchers (Apps): pick the app + rebind its key ─────────
    Component {
        id: appsComp

        Flickable {
            id: appsFlick
            contentWidth: width
            contentHeight: appsCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

            Column {
                id: appsCol
                width: appsFlick.width - Tokens.s3
                spacing: Tokens.s5

                Text {
                    width: appsCol.width
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Pick what each launcher key opens, and rebind the key itself. The key runs the app through ryoku-app, so a swap takes effect on the next press -- no reload.")
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; lineHeight: 1.3
                }

                Repeater {
                    model: pg.roles

                    delegate: Column {
                        id: roleCard
                        required property var modelData
                        width: appsCol.width
                        spacing: Tokens.s2
                        readonly property string role: roleCard.modelData.role
                        readonly property string fallback: roleCard.modelData.fallback || ""
                        readonly property string combo: roleCard.modelData.combo || ""
                        readonly property string eff: pg.effOf(roleCard.role, roleCard.fallback)
                        readonly property bool rebound: pg.isRebound(roleCard.combo)
                        readonly property bool clash: roleCard.rebound && pg.comboConflict(roleCard.combo)
                        readonly property var effKeys: pg.comboToCaps(pg.effectiveCombo(roleCard.combo))

                        // line 1: role label + current command, then the key + rebind cluster.
                        Item {
                            width: parent.width
                            height: 24
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s2
                                Text {
                                    text: I18n.tr(roleCard.modelData.label)
                                    color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                                    font.capitalization: Font.AllUppercase
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, roleCard.width * 0.32)
                                    text: roleCard.eff !== "" ? roleCard.eff : I18n.tr("not set")
                                    color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s2
                                visible: roleCard.combo.length > 0

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.s1
                                    Repeater {
                                        model: roleCard.effKeys
                                        delegate: Row {
                                            id: capW
                                            required property var modelData
                                            required property int index
                                            spacing: Tokens.s1
                                            Text {
                                                visible: capW.index > 0
                                                height: 22; verticalAlignment: Text.AlignVCenter
                                                text: "+"; color: Tokens.inkFaint
                                                font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                implicitHeight: 22
                                                implicitWidth: Math.max(22, cl.implicitWidth + 14)
                                                radius: Tokens.radius; color: "transparent"
                                                border.width: Tokens.border
                                                border.color: roleCard.clash ? Tokens.ink : (roleCard.rebound ? Tokens.lineStrong : Tokens.line)
                                                Text {
                                                    id: cl
                                                    anchors.centerIn: parent
                                                    text: capW.modelData
                                                    color: roleCard.rebound ? Tokens.inkDim : Tokens.inkFaint
                                                    font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
                                                }
                                            }
                                        }
                                    }
                                }
                                IconBtn {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: roleCard.rebound
                                    glyph: "\u21ba"
                                    onAct: pg.clearRebind(roleCard.combo)
                                }
                                IconBtn {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pg.hubReady
                                    glyph: "\u25cf"
                                    onAct: pg.startRecordShipped(roleCard.combo)
                                }
                            }
                        }

                        // line 2: installed candidate chips + Browse (the app catalogue).
                        Flow {
                            width: parent.width
                            spacing: Tokens.s2

                            Repeater {
                                model: roleCard.modelData.candidates || []
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    visible: chip.modelData.installed === true
                                    readonly property bool sel: roleCard.eff === chip.modelData.cmd
                                    implicitWidth: chLbl.implicitWidth + Tokens.s4
                                    implicitHeight: 28
                                    radius: Tokens.radius
                                    color: chip.sel ? Tokens.ink : (chHov.hovered ? Tokens.tint10 : "transparent")
                                    border.width: Tokens.border
                                    border.color: chip.sel ? Tokens.ink : (chHov.hovered ? Tokens.lineStrong : Tokens.line)
                                    Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                    Text {
                                        id: chLbl
                                        anchors.centerIn: parent
                                        text: I18n.tr(chip.modelData.label)
                                        color: chip.sel ? Tokens.paper : Tokens.inkDim
                                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                    }
                                    HoverHandler { id: chHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: pg.setApp(roleCard.role, chip.modelData.cmd) }
                                }
                            }

                            Rectangle {
                                implicitWidth: brLbl.implicitWidth + Tokens.s4
                                implicitHeight: 28
                                radius: Tokens.radius
                                color: brHov.hovered ? Tokens.tint10 : "transparent"
                                border.width: Tokens.border
                                border.color: brHov.hovered ? Tokens.lineStrong : Tokens.line
                                Text {
                                    id: brLbl
                                    anchors.centerIn: parent
                                    text: I18n.tr("Browse\u2026")
                                    color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                }
                                HoverHandler { id: brHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: pg.openAppPickerRole(roleCard.role) }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Tokens.s2
                            visible: roleCard.role === "terminal"

                            Row {
                                spacing: Tokens.s2
                                Text {
                                    text: I18n.tr("SHELL")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fMicro
                                    font.weight: Font.Medium
                                    font.letterSpacing: Tokens.trackMark
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: I18n.tr("Account-wide; new terminals, TTYs and SSH sessions use this shell.")
                                    color: Tokens.inkFaint
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fTiny
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: Tokens.s2
                                Repeater {
                                    model: pg.shellState.choices || []
                                    Rectangle {
                                        id: shellChip
                                        required property var modelData
                                        readonly property bool selected: pg.shellState.current === shellChip.modelData.key
                                        implicitWidth: shellLabel.implicitWidth + Tokens.s4
                                        implicitHeight: 28
                                        radius: Tokens.radius
                                        opacity: shellChip.modelData.installed && !pg.shellBusy ? 1 : 0.35
                                        color: shellChip.selected ? Tokens.ink : (shellHover.hovered ? Tokens.tint10 : "transparent")
                                        border.width: Tokens.border
                                        border.color: shellChip.selected ? Tokens.ink : Tokens.line
                                        Text {
                                            id: shellLabel
                                            anchors.centerIn: parent
                                            text: I18n.tr(shellChip.modelData.label)
                                            color: shellChip.selected ? Tokens.paper : Tokens.inkDim
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fSmall
                                        }
                                        HoverHandler {
                                            id: shellHover
                                            enabled: shellChip.modelData.installed && !pg.shellBusy
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        }
                                        TapHandler {
                                            enabled: shellChip.modelData.installed && !pg.shellBusy
                                            onTapped: pg.setShell(shellChip.modelData.key)
                                        }
                                    }
                                }
                            }

                            Row {
                                spacing: Tokens.s2
                                Text {
                                    text: I18n.tr("ZSH PROMPT")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fMicro
                                    font.weight: Font.Medium
                                    font.letterSpacing: Tokens.trackMark
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: I18n.tr("Used when Zsh is selected.")
                                    color: Tokens.inkFaint
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fTiny
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: Tokens.s2
                                Repeater {
                                    model: [
                                        { "mode": "starship", "label": I18n.tr("Starship") },
                                        { "mode": "oh-my-zsh", "label": I18n.tr("Oh My Zsh") }
                                    ]
                                    delegate: Rectangle {
                                        id: promptChip
                                        required property var modelData
                                        readonly property bool selected: pg.shellState.zshPrompt === promptChip.modelData.mode
                                        implicitWidth: promptLabel.implicitWidth + Tokens.s4
                                        implicitHeight: 28
                                        radius: Tokens.radius
                                        opacity: pg.shellBusy ? 0.35 : 1
                                        color: promptChip.selected ? Tokens.ink : (promptHover.hovered ? Tokens.tint10 : "transparent")
                                        border.width: Tokens.border
                                        border.color: promptChip.selected ? Tokens.ink : Tokens.line
                                        Text {
                                            id: promptLabel
                                            anchors.centerIn: parent
                                            text: I18n.tr(promptChip.modelData.label)
                                            color: promptChip.selected ? Tokens.paper : Tokens.inkDim
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fSmall
                                        }
                                        HoverHandler {
                                            id: promptHover
                                            enabled: !pg.shellBusy
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        }
                                        TapHandler {
                                            enabled: !pg.shellBusy
                                            onTapped: pg.setZshPrompt(promptChip.modelData.mode)
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: I18n.tr("Custom: ~/.config/fish/user.fish · ~/.config/bash/user.bash · ~/.config/zsh/user.zsh · ~/.config/zsh/oh-my-zsh/")
                                color: Tokens.inkFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fTiny
                                wrapMode: Text.Wrap
                            }
                            Text {
                                visible: pg.shellError !== ""
                                text: pg.shellError
                                color: Tokens.alert
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fTiny
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Tokens.lineSoft }
                    }
                }
            }
        }
    }

    // ── the shipped-bind legend (read-only) ─────────────────────────────────
    Component {
        id: systemComp

        Flickable {
            id: legend
            contentWidth: width
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

            Column {
                id: col
                width: legend.width - Tokens.s3   // reserve a lane for the scroll rail
                spacing: Tokens.s5

                Repeater {
                    model: pg.systemCategories

                    delegate: Column {
                        id: grp
                        required property var modelData
                        width: col.width
                        spacing: 0

                        // section head: dot + category caps + hairline leader.
                        Item {
                            width: parent.width
                            height: 30
                            Row {
                                id: grpLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s2
                                Rectangle {
                                    width: 4; height: 4; color: Tokens.ink
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: grp.modelData.name; color: Tokens.ink
                                    font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                                    font.capitalization: Font.AllUppercase
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Rectangle {
                                anchors.left: grpLabel.right; anchors.leftMargin: Tokens.s3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 1; color: Tokens.lineSoft
                            }
                        }

                        Repeater {
                            model: grp.modelData.binds

                            delegate: Column {
                                id: bindWrap
                                required property var modelData
                                required property int index
                                readonly property string combo: bindWrap.modelData.combo || ""
                                readonly property bool rebound: pg.isRebound(bindWrap.combo)
                                readonly property bool clash: bindWrap.rebound && pg.comboConflict(bindWrap.combo)
                                readonly property var effKeys: bindWrap.rebound ? pg.comboToCaps(pg.effectiveCombo(bindWrap.combo)) : (bindWrap.modelData.keys || [])
                                width: grp.width

                                // row separators inside the group.
                                Rectangle {
                                    visible: bindWrap.index > 0
                                    width: parent.width; height: 1; color: Tokens.lineSoft
                                }

                                // one legend line: description left, keycaps + rebind right.
                                Item {
                                    width: parent.width
                                    height: 44

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: rightCluster.left; anchors.rightMargin: Tokens.s4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: bindWrap.modelData.desc || ""
                                        color: Tokens.inkDim
                                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        id: rightCluster
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Tokens.s2

                                        Row {
                                            id: caps
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Tokens.s1

                                            Repeater {
                                                model: bindWrap.effKeys

                                                delegate: Row {
                                                    id: capWrap
                                                    required property var modelData
                                                    required property int index
                                                    spacing: Tokens.s1

                                                    Text {
                                                        visible: capWrap.index > 0
                                                        height: 22
                                                        verticalAlignment: Text.AlignVCenter
                                                        text: "+"
                                                        color: Tokens.inkFaint
                                                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                                                    }
                                                    // keycap: hairline rect, mono. ink border when the combo clashes.
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        implicitHeight: 22
                                                        implicitWidth: Math.max(22, capLabel.implicitWidth + 14)
                                                        radius: Tokens.radius
                                                        color: "transparent"
                                                        border.width: Tokens.border
                                                        border.color: bindWrap.clash ? Tokens.ink : (bindWrap.rebound ? Tokens.lineStrong : Tokens.line)
                                                        Text {
                                                            id: capLabel
                                                            anchors.centerIn: parent
                                                            text: capWrap.modelData
                                                            color: bindWrap.rebound ? Tokens.inkDim : Tokens.inkFaint
                                                            font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // reset a rebound shortcut to its shipped default.
                                        IconBtn {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: bindWrap.rebound
                                            glyph: "\u21ba"
                                            onAct: pg.clearRebind(bindWrap.combo)
                                        }
                                        // record a new chord for this shortcut.
                                        IconBtn {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: bindWrap.modelData.rebindable === true && pg.hubReady
                                            glyph: "\u25cf"
                                            onAct: pg.startRecordShipped(bindWrap.combo)
                                        }
                                    }
                                }

                                // conflict note: names what the rebound chord clashes with. Ink only.
                                Text {
                                    visible: bindWrap.clash
                                    width: parent.width
                                    leftPadding: Tokens.s2
                                    bottomPadding: Tokens.s2
                                    text: I18n.tr("Clashes with %1").arg(pg.conflictNameFor(bindWrap.combo))
                                    color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // footer explainer: where the legend comes from, and the caveat.
                Text {
                    width: col.width
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Read live from Ryoku's binds plus your Hub custom shortcuts. Binds added by hand in ~/.config/hypr/user.lua do not appear here and are not conflict-checked, so add custom shortcuts in the Custom tab.")
                    color: Tokens.inkFaint; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; lineHeight: 1.3
                }
            }
        }
    }

    // ── the custom-bind editor ──────────────────────────────────────────────
    Component {
        id: customComp

        Item {
            id: editor

            // which row's action catalogue is open; -1 = closed.
            property int pickerRow: -1
            function openPicker(i) { editor.pickerRow = i; picker.open(); }

            // intro: load-bearing product guidance, not decoration.
            Text {
                id: intro
                anchors { left: parent.left; right: parent.right; top: parent.top }
                wrapMode: Text.WordWrap
                text: I18n.tr("Custom shortcuts layered over the ones Ryoku ships and kept in the Hub, so they show in the Shortcuts legend and get conflict-checked. Click record and press the combo -- even SUPER + Q is captured safely -- or type it the way Hyprland writes it, e.g. SUPER + J. Binds hand-written in ~/.config/hypr/user.lua never appear here and are not conflict-checked.")
                color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                lineHeight: 1.3
            }

            // section head: dot + SHORTCUTS + leader + count + add.
            Item {
                id: sect
                anchors { left: parent.left; right: parent.right; top: intro.bottom; topMargin: Tokens.s4 }
                height: 32

                Row {
                    id: sectLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.s2
                    Rectangle {
                        width: 4; height: 4; color: Tokens.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: I18n.tr("SHORTCUTS"); color: Tokens.ink; font.family: Tokens.ui
                        font.pixelSize: Tokens.fMicro; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackMark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    id: sectActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.s3

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // an entry count is file-truth chrome, so mono.
                        text: pg.customRows.length === 1 ? I18n.tr("%1 BIND").arg(pg.customRows.length) : I18n.tr("%1 BINDS").arg(pg.customRows.length)
                        color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "+"
                        armed: pg.hubReady
                        // add a row and drop straight into recording it: the
                        // one-click path to a brand-new shortcut.
                        onAct: { pg.addRow(); Qt.callLater(function() { pg.startRecord(pg.customRows.length - 1); }); }
                    }
                }

                Rectangle {
                    anchors.left: sectLabel.right; anchors.right: sectActions.left
                    anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1; color: Tokens.lineSoft
                }
            }

            // ── the scrolling bind list ──
            Flickable {
                id: flick
                anchors {
                    left: parent.left; right: parent.right
                    top: sect.bottom; bottom: parent.bottom
                    topMargin: Tokens.s4; bottomMargin: Tokens.s3
                }
                contentWidth: width
                contentHeight: Math.max(rowsCol.height, height)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

                Column {
                    id: rowsCol
                    width: flick.width - Tokens.s3   // reserve a lane for the scroll rail
                    spacing: Tokens.s2

                    Repeater {
                        model: pg.customRows

                        delegate: Rectangle {
                            id: rowRect
                            required property int index
                            required property var modelData
                            readonly property bool isRelease: rowRect.modelData.release === true
                            readonly property int lineH: 30
                            readonly property real gap: Tokens.s2
                            readonly property real removeW: 26
                            readonly property real keysW: 200
                            readonly property real recW: 26
                            readonly property string act: rowRect.modelData.action || "exec"
                            readonly property bool needsValue: act === "exec"
                            readonly property string conflict: pg.rowConflict(rowRect.index)

                            width: rowsCol.width
                            height: Tokens.s3 * 2 + lineH + (conflict !== "" ? 18 : 0)
                            radius: Tokens.radius
                            color: rh.hovered ? Tokens.tint5 : "transparent"
                            border.width: Tokens.border
                            // a conflict flags itself in solid ink -- the brightest
                            // tell on the sheet, colour-free (DESIGN.md section 1).
                            border.color: conflict !== "" ? Tokens.ink
                                : (rh.hovered ? Tokens.lineStrong : Tokens.line)
                            Behavior on color { ColorAnimation { duration: Tokens.snap } }
                            Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                            HoverHandler { id: rh }

                            // ── controls line ──
                            Item {
                                id: ctlRow
                                anchors {
                                    left: parent.left; right: parent.right; top: parent.top
                                    leftMargin: Tokens.s3; rightMargin: Tokens.s3; topMargin: Tokens.s3
                                }
                                height: rowRect.lineH

                                // key combo: a Hyprland combo string, so mono.
                                Field {
                                    id: keysF
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: rowRect.keysW - rowRect.recW - rowRect.gap
                                    tabular: true
                                    placeholder: "SUPER + J"
                                    text: rowRect.modelData.keys || ""
                                    onCommitted: (v) => {
                                        if (v !== (rowRect.modelData.keys || ""))
                                            pg.patch(rowRect.index, "keys", v);
                                    }
                                }
                                Rectangle {
                                    id: releaseToggle
                                    anchors.right: removeBtn.left
                                    anchors.rightMargin: rowRect.gap
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitHeight: 24
                                    implicitWidth: relText.implicitWidth + 12
                                    radius: Tokens.radius
                                    color: rowRect.isRelease ? Tokens.ink : "transparent"
                                    border.width: Tokens.border
                                    border.color: rowRect.isRelease ? Tokens.ink : Tokens.line

                                    Text {
                                        id: relText
                                        anchors.centerIn: parent
                                        text: rowRect.isRelease ? I18n.tr("RELEASE") : I18n.tr("PRESS")
                                        color: rowRect.isRelease ? Tokens.paper : Tokens.inkFaint
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fMicro
                                        font.weight: Font.Medium
                                    }

                                    HoverHandler { id: relHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (pg.hubReady)
                                                pg.patch(rowRect.index, "release", !rowRect.isRelease);
                                        }
                                    }
                                }
                                // record: capture the combo by pressing it. Safe
                                // because startRecord enters the record submap
                                // first, so the live chord reaches the field, not
                                // Hyprland.
                                IconBtn {
                                    id: recBtn
                                    anchors.left: keysF.right
                                    anchors.leftMargin: rowRect.gap
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "\u25CF"
                                    armed: pg.hubReady
                                    onAct: pg.startRecord(rowRect.index)
                                }

                                IconBtn {
                                    id: removeBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    // a paired minus, not a trash icon: remove is not
                                    // danger and there is no red on the sheet.
                                    glyph: "\u2212"
                                    onAct: pg.removeRow(rowRect.index)
                                }

                                // command box: shown only for "Run command"; the foot
                                // bar fills whatever is left when it is hidden.
                                Item {
                                    id: cmdBox
                                    anchors.right: releaseToggle.left
                                    anchors.rightMargin: rowRect.gap
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: rowRect.lineH
                                    width: rowRect.needsValue
                                        ? Math.max(180, Math.round((parent.width - rowRect.keysW - rowRect.removeW - rowRect.gap * 3) * 0.5))
                                        : 0

                                    // pick an app from the catalogue, or type the command.
                                    IconBtn {
                                        id: cmdPick
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: rowRect.needsValue
                                        glyph: "\u2026"
                                        armed: pg.hubReady
                                        onAct: pg.openAppPickerCustom(rowRect.index)
                                    }
                                    // command is a shell string, so mono.
                                    Field {
                                        id: cmdF
                                        anchors.left: parent.left
                                        anchors.right: cmdPick.left
                                        anchors.rightMargin: rowRect.gap
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height
                                        visible: rowRect.needsValue
                                        tabular: true
                                        placeholder: I18n.tr("command to run")
                                        text: rowRect.modelData.value || ""
                                        onCommitted: (v) => {
                                            if (v !== (rowRect.modelData.value || ""))
                                                pg.patch(rowRect.index, "value", v);
                                        }
                                    }
                                }

                                // the action catalogue foot bar.
                                PickBar {
                                    id: actionBar
                                    anchors.left: recBtn.right
                                    anchors.leftMargin: rowRect.gap
                                    anchors.right: cmdBox.left
                                    anchors.rightMargin: rowRect.needsValue ? rowRect.gap : 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: pg.labelIn(pg.actionOpts, rowRect.act)
                                    count: pg.actionOpts.length
                                    onOpened: editor.openPicker(rowRect.index)
                                }
                            }

                            // conflict note: names what it clashes with, in ink,
                            // no colour (DESIGN.md section 1).
                            Text {
                                visible: rowRect.conflict !== ""
                                anchors.left: parent.left; anchors.leftMargin: Tokens.s3
                                anchors.bottom: parent.bottom; anchors.bottomMargin: Tokens.s2
                                text: {
                                    if (rowRect.conflict === "duplicate")
                                        return I18n.tr("Duplicate of another custom bind");
                                    var d = pg.shippedDescFor(pg.normKeys(rowRect.modelData.keys || ""));
                                    return d ? I18n.tr("Shadows shipped: %1").arg(d) : I18n.tr("Shadows a shipped bind");
                                }
                                color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            }
                        }
                    }
                }
            }

            // empty state, gated on load so it does not flash before data arrives.
            Text {
                anchors.centerIn: flick
                visible: pg.ready && pg.customRows.length === 0
                text: I18n.tr("No custom shortcuts yet. Add one to bind a command or a window action.")
                color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
            }


            // ── the action catalogue overlay (Picker), shared across rows ──
            MouseArea {
                id: scrim
                anchors.fill: parent
                visible: editor.pickerRow >= 0
                z: 100
                // a bare click-catcher: dismiss on an outside click. No fill --
                // translucency is banned on app surfaces (DESIGN.md section 6).
                onClicked: editor.pickerRow = -1

                Picker {
                    id: picker
                    anchors.centerIn: parent
                    title: I18n.tr("Action")
                    options: pg.labelsOf(pg.actionOpts)
                    current: {
                        if (editor.pickerRow < 0)
                            return "";
                        var r = (pg.customRows[editor.pickerRow] || ({})).action || "exec";
                        return pg.labelIn(pg.actionOpts, r);
                    }
                    onChose: (label) => {
                        pg.setAction(editor.pickerRow, pg.keyIn(pg.actionOpts, label));
                        editor.pickerRow = -1;
                    }
                    onDismissed: editor.pickerRow = -1

                    // absorb clicks inside the card so the scrim does not treat a
                    // header/padding tap as an outside dismiss.
                    MouseArea { anchors.fill: parent; z: -1 }
                }
            }

        }
    }

    // ── action bar: status + reset / revert / save, shared by both tabs ──
    // full-bleed page, so the shell's global bar is hidden; this persists the
    // shared store. Page-level so a rebind recorded on the Shortcuts tab saves
    // from the same bar as a custom bind on the Custom tab.
    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.bottomMargin: Tokens.s5
        height: 60
        color: "transparent"
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1; color: Tokens.line
        }

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3

            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                antialiasing: false
                readonly property bool lit: pg.conflictCount > 0 || pg.dirtyCount > 0
                color: lit ? Tokens.ink : "transparent"
                border.width: lit ? 0 : Tokens.border
                border.color: Tokens.inkFaint
                SequentialAnimation on opacity {
                    running: pg.dirtyCount > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    onStopped: dot.opacity = 1
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pg.conflictCount > 0
                    ? (pg.conflictCount === 1 ? I18n.tr("%1 conflicting shortcut").arg(pg.conflictCount) : I18n.tr("%1 conflicting shortcuts").arg(pg.conflictCount))
                    : (pg.dirtyCount > 0 ? I18n.tr("Unsaved changes") : I18n.tr("Saved"))
                color: (pg.conflictCount > 0 || pg.dirtyCount > 0) ? Tokens.ink : Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                font.weight: Font.Medium
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3

            // tab-aware reset: clears rebinds on Shortcuts, custom binds on Custom.
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: pg.tab === "apps" ? I18n.tr("RESET APPS") : (pg.tab === "system" ? I18n.tr("RESET REBINDS") : I18n.tr("RESTORE DEFAULTS"))
                armed: pg.tab === "apps" ? pg.hasApps() : (pg.tab === "system" ? pg.hasRebinds() : pg.customRows.length > 0)
                onAct: pg.tab === "apps" ? pg.clearApps() : (pg.tab === "system" ? pg.clearRebinds() : pg.clearAll())
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("REVERT")
                armed: pg.dirtyCount > 0
                onAct: pg.revertAll()
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("SAVE")
                primary: true
                armed: pg.dirtyCount > 0
                onAct: pg.saveAll()
            }
        }

        Marginalia {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            kana: "操作"
            glyph: "meander"; glyph2: "torii"
        }
    }

    // ── the app catalogue picker (shared: Apps roles + custom Run binds) ─────
    MouseArea {
        id: appScrim
        anchors.fill: parent
        visible: pg.appPicking
        z: 150
        onClicked: pg.closeAppPicker()

        // Ryoku.Ui's AppPicker (the one this page resolves; the hub root's
        // AppPicker.qml is not on this directory's import path) emits picked(cmd).
        AppPicker {
            id: appPicker
            anchors.centerIn: parent
            title: pg.appPickTitle()
            apps: pg.appCatalog
            current: pg.appPickCurrent()
            onPicked: (cmd) => pg.applyAppPick(cmd)
            onDismissed: pg.closeAppPicker()
            Connections {
                target: pg
                function onAppPickingChanged() { if (pg.appPicking) appPicker.open(); }
            }
            MouseArea { anchors.fill: parent; z: -1 }
        }
    }

    // ── chord recorder overlay (page-level: serves both tabs) ──
    // the capture Item holds focus so the combo the record submap lets through
    // arrives as a plain KeyEvent; chordFrom turns it into Hyprland's string.
    MouseArea {
        id: recScrim
        anchors.fill: parent
        visible: pg.recording
        z: 200
        onClicked: pg.stopRecord(false, "")
        onVisibleChanged: if (visible) capture.forceActiveFocus()

        Item {
            id: capture
            anchors.fill: parent
            focus: true
            Keys.onPressed: (event) => {
                event.accepted = true;
                if (event.isAutoRepeat)
                    return;
                if (event.key === Qt.Key_Escape) {
                    pg.stopRecord(false, "");
                    return;
                }
                var chord = pg.chordFrom(event);
                if (chord !== "")
                    pg.stopRecord(true, chord);
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 340; height: 156
            radius: Tokens.radius
            color: Tokens.paper
            border.width: Tokens.border
            border.color: Tokens.lineStrong

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.s4 * 2
                spacing: Tokens.s3

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("PRESS YOUR SHORTCUT")
                    color: Tokens.ink; font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Hold your modifiers and tap the key. Esc cancels.")
                    color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                }
                Btn {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("CANCEL")
                    armed: true
                    onAct: pg.stopRecord(false, "")
                }
            }

            MouseArea { anchors.fill: parent; z: -1 }
        }
    }
}
