pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Input (DESIGN.md, SYSTEM). Keyboard layout and remaps, pointer and touchpad
// behaviour, and key repeat for the Hyprland session. Rendered as rows off the
// shared taxonomy, but three surfaces refuse a plain schema and are built by
// hand:
//
//   * kb_layout / kb_variant are ONE positional comma string each ("fr,us" +
//     "azerty,"): two catalogue picks edit the halves and keep the variant slot
//     aligned to its layout by position.
//   * kb_options is ONE comma string multiplexed across four controls plus a
//     free-text escape hatch. Caps Lock, Swap Alt/Super, Compose and Switch
//     layouts each own a family of xkb tokens; the family is replaced in place,
//     everything unrecognised round-trips through Extra options so power users
//     lose nothing. grpIds carries grp:caps_toggle deliberately (so it is
//     stripped from Extra options) while the Switch seg never offers it: that
//     asymmetry is load-bearing and reproduced here on purpose.
//   * Apply system-wide is an out-of-band, privileged `ryoku keyboard apply`
//     covering the login screen, the TTYs and the disk passphrase prompt; it
//     has no draft, no revert, no dirty state, and is gated on the keyboard
//     keys already being saved.
//
// The layout/variant catalogues are scanned at runtime (xkb rules), so they are
// filtered picks, not enums. Everything else reads hub.hyprVal / writes
// hub.hyprEdit; the shell owns the rail, side panel, action bar, live preview
// and restore. Nothing here writes a file except Apply system-wide.
Item {
    id: pg

    property var hub

    // gated so nothing paints stale before the first `hypr get` returns.
    readonly property bool ready: pg.hub ? pg.hub.hyprLoaded === true : false

    // ── hub access ──────────────────────────────────────────────────────────
    function hv(path) { return pg.hub ? pg.hub.hyprVal(path) : undefined }
    function cv(path) { return pg.hub ? pg.hub.hyprCommittedVal(path) : undefined }
    function he(path, v) { if (pg.hub) pg.hub.hyprEdit(path, v) }

    // ── keyboard layout: positional comma strings ───────────────────────────
    // kb_layout may hold "fr,us" (primary + secondary). The variant applies to
    // the primary, so a secondary keeps the variant's slot empty ("azerty,")
    // because xkb aligns variants to layouts by position. `committed` reads disk
    // for the struck default.
    function kbLayoutStr(committed) {
        return String((committed ? pg.cv("input.kbLayout") : pg.hv("input.kbLayout")) || "");
    }
    function kbVariantStr(committed) {
        return String((committed ? pg.cv("input.kbVariant") : pg.hv("input.kbVariant")) || "");
    }
    function primaryLayout(committed) { return pg.kbLayoutStr(committed).split(",")[0]; }
    function secondaryLayout(committed) {
        var parts = pg.kbLayoutStr(committed).split(",");
        return parts.length > 1 ? parts[1] : "";
    }
    function primaryVariant(committed) { return pg.kbVariantStr(committed).split(",")[0]; }

    function setLayouts(primary, secondary) {
        pg.he("input.kbLayout", secondary ? primary + "," + secondary : primary);
        var v = pg.primaryVariant(false);
        pg.he("input.kbVariant", secondary && v ? v + "," : v);
    }
    function setVariant(v) {
        pg.he("input.kbVariant", pg.secondaryLayout(false) && v ? v + "," : v);
    }

    // ── curated remaps over kb_options ──────────────────────────────────────
    // Each control owns one xkb option family; anything it does not recognise
    // stays in Extra options. All state lives in the single kb_options string.
    readonly property var capsIds: ["caps:escape", "ctrl:nocaps", "caps:swapescape", "caps:none"]
    readonly property var composeIds: ["compose:ralt", "compose:menu"]
    // grp:caps_toggle is a recognised family member (so it is stripped from
    // Extra options) but is NOT offered by the Switch seg: the asymmetry is
    // deliberate, so a caps_toggle set elsewhere is not leaked into free text.
    readonly property var grpIds: ["grp:alt_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle"]
    readonly property string swapId: "altwin:swap_alt_win"

    function kbOptionsStr(committed) {
        return String((committed ? pg.cv("input.kbOptions") : pg.hv("input.kbOptions")) || "");
    }
    function optTokens(committed) {
        var raw = pg.kbOptionsStr(committed).split(",");
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var t = raw[i].trim();
            if (t.length)
                out.push(t);
        }
        return out;
    }
    // the first recognised token of a family wins, matching the old page.
    function pickFrom(ids, committed) {
        var toks = pg.optTokens(committed);
        for (var i = 0; i < toks.length; i++)
            if (ids.indexOf(toks[i]) !== -1)
                return toks[i];
        return "";
    }
    function knownIds() {
        return pg.capsIds.concat(pg.composeIds).concat(pg.grpIds).concat([pg.swapId]);
    }
    function extraOptions(committed) {
        var known = pg.knownIds();
        var toks = pg.optTokens(committed);
        var out = [];
        for (var i = 0; i < toks.length; i++)
            if (known.indexOf(toks[i]) === -1)
                out.push(toks[i]);
        return out.join(",");
    }
    // rebuild kb_options with one family replaced; "" drops the family.
    function setOption(ids, value) {
        var toks = pg.optTokens(false);
        var out = [];
        for (var j = 0; j < toks.length; j++)
            if (ids.indexOf(toks[j]) === -1)
                out.push(toks[j]);
        if (value.length)
            out.push(value);
        pg.he("input.kbOptions", out.join(","));
    }
    function setExtra(text) {
        var known = pg.knownIds();
        var keep = [];
        var toks = pg.optTokens(false);
        for (var i = 0; i < toks.length; i++)
            if (known.indexOf(toks[i]) !== -1)
                keep.push(toks[i]);
        var raw = String(text || "").split(",");
        for (var j = 0; j < raw.length; j++) {
            var t = raw[j].trim();
            if (t.length)
                keep.push(t);
        }
        pg.he("input.kbOptions", keep.join(","));
    }

    // family key <-> visible label, offered choices per family.
    readonly property var capsMap: [
        { "key": "", "label": I18n.tr("Default") },
        { "key": "caps:escape", "label": I18n.tr("Escape") },
        { "key": "ctrl:nocaps", "label": "Ctrl" },
        { "key": "caps:swapescape", "label": I18n.tr("Swap Esc") },
        { "key": "caps:none", "label": I18n.tr("Off") }
    ]
    readonly property var composeMap: [
        { "key": "", "label": I18n.tr("Off") },
        { "key": "compose:ralt", "label": I18n.tr("Right Alt") },
        { "key": "compose:menu", "label": I18n.tr("Menu") }
    ]
    readonly property var grpMap: [
        { "key": "", "label": I18n.tr("Off") },
        { "key": "grp:alt_shift_toggle", "label": "Alt+Shift" },
        { "key": "grp:win_space_toggle", "label": "Super+Space" }
    ]
    function mapLabel(m, k) {
        for (var i = 0; i < m.length; i++)
            if (String(m[i].key) === String(k === undefined ? "" : k))
                return m[i].label;
        return String(k === undefined ? "" : k);
    }
    function mapKey(m, lb) {
        for (var i = 0; i < m.length; i++)
            if (m[i].label === lb)
                return m[i].key;
        return lb;
    }
    function labels(m) {
        var out = [];
        for (var i = 0; i < m.length; i++)
            out.push(m[i].label);
        return out;
    }

    // ── dynamic xkb catalogues ──────────────────────────────────────────────
    property var layoutOptions: []                                 // [{ code, name }]
    property var variantOptions: [{ "code": "", "name": I18n.tr("Default") }]

    Process {
        id: layoutsProc
        command: ["ryoku-hub", "hypr", "layouts"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { pg.layoutOptions = JSON.parse(this.text); } catch (e) {}
            }
        }
    }

    // xkb variant names repeat the language ("French (AZERTY)"); inside an
    // already-chosen layout that prefix is noise, so keep only the qualifier.
    function variantLabel(name) {
        var m = String(name || "").match(/^[^(]+\((.+)\)$/);
        if (!m)
            return name;
        var q = m[1].trim();
        return q.charAt(0).toUpperCase() + q.slice(1);
    }
    Process {
        id: variantsProc
        property string forLayout: ""
        command: ["ryoku-hub", "hypr", "variants", forLayout]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [{ "code": "", "name": I18n.tr("Default") }];
                try {
                    var arr = JSON.parse(this.text);
                    for (var i = 0; i < arr.length; i++)
                        out.push({ "code": arr[i].code, "name": pg.variantLabel(arr[i].name) });
                } catch (e) {}
                pg.variantOptions = out;
            }
        }
    }
    // guarded so the same layout never refetches and an empty layout is skipped;
    // driven by the primary-layout change below plus first paint.
    function refreshVariants() {
        var l = pg.primaryLayout(false);
        if (l.length === 0 || variantsProc.forLayout === l)
            return;
        variantsProc.forLayout = l;
        variantsProc.running = false;
        variantsProc.running = true;
    }
    readonly property string curPrimary: pg.primaryLayout(false)
    onCurPrimaryChanged: pg.refreshVariants()
    Component.onCompleted: pg.refreshVariants()

    function nameIn(list, code) {
        for (var i = 0; i < list.length; i++)
            if (list[i].code === code)
                return list[i].name;
        return code;
    }

    // ── system-wide keymap: greeter, TTY, and the boot prompt (privileged) ──
    // Out of band: this writes to /etc and rebuilds the boot image, not the
    // draft, and escalates through polkit.
    property string sysApplyState: ""
    function applyLayoutArg() { return String(pg.hv("input.kbLayout") || "us"); }
    function applyVariantArg() { return String(pg.hv("input.kbVariant") || ""); }
    function applyOptionsArg() { return String(pg.hv("input.kbOptions") || ""); }
    // `ryoku keyboard apply` owns all four layers: it sets the greeter and the
    // console through localectl AND rebuilds the boot image, which localectl
    // alone cannot do. mkinitcpio bakes a copy of /etc/vconsole.conf into the
    // image at build time, so without that rebuild the disk passphrase prompt
    // keeps the keymap it was built with however correct /etc looks.
    Process {
        id: sysApplyProc
        command: ["ryoku", "keyboard", "apply", pg.applyLayoutArg()]
        onExited: (code, status) => {
            pg.sysApplyState = code === 0 ? "ok" : "err";
            sysApplyClear.restart();
        }
    }
    Timer {
        id: sysApplyClear
        interval: 6000
        onTriggered: pg.sysApplyState = ""
    }
    // apply what is on disk: gated on the keyboard keys being saved first.
    readonly property bool kbClean: {
        if (!pg.hub)
            return false;
        return JSON.stringify(pg.hv("input.kbLayout")) === JSON.stringify(pg.cv("input.kbLayout"))
            && JSON.stringify(pg.hv("input.kbVariant")) === JSON.stringify(pg.cv("input.kbVariant"))
            && JSON.stringify(pg.hv("input.kbOptions")) === JSON.stringify(pg.cv("input.kbOptions"));
    }

    readonly property bool swipeOn: pg.hv("input.workspaceSwipe") === true

    // ── the catalogue overlay (filtered pick over the runtime xkb lists) ─────
    property var catList: null            // [{ code, name }] while open, else null
    property string catTitle: ""
    property string catCurrent: ""        // current code
    property var catApply: null           // function(code)
    function openCat(title, list, current, apply) {
        pg.catTitle = title;
        pg.catList = list;
        pg.catCurrent = current;
        pg.catApply = apply;
        catPicker.open();
    }
    function closeCat() { pg.catList = null; pg.catApply = null; }
    function chooseCat(name) {
        var code = name;
        if (pg.catList)
            for (var i = 0; i < pg.catList.length; i++)
                if (pg.catList[i].name === name) { code = pg.catList[i].code; break; }
        if (pg.catApply)
            pg.catApply(code);
        pg.closeCat();
    }
    readonly property var catNames: {
        var out = [];
        if (pg.catList)
            for (var i = 0; i < pg.catList.length; i++)
                out.push(pg.catList[i].name);
        return out;
    }
    readonly property string catCurrentName: {
        if (pg.catList)
            for (var i = 0; i < pg.catList.length; i++)
                if (pg.catList[i].code === pg.catCurrent)
                    return pg.catList[i].name;
        return "";
    }

    // ── a scalar row driven straight off a hypr path ────────────────────────
    // sw / seg / slid / step. Fractional ratios ride an integer control scaled
    // by `sc` (the module Slid/Step are integer), and the row numeral shows the
    // real value. Enums whose stored key is not its label carry an opts map, and
    // int-backed enums (followMouse, swipeFingers) write back an int so the
    // draft never diverges from disk as a string.
    component Setting: SettingRow {
        id: st
        property string path: ""
        property string ctl: "sw"
        property var opts: []
        property real lo: 0
        property real hi: 1
        property real sc: 1
        property int dec: 0
        property int stepBy: 1
        property bool asInt: false
        property bool gate: true

        readonly property int optCount: st.opts.length
        readonly property var rawV: (pg.hub && st.path) ? pg.hub.hyprVal(st.path) : undefined
        readonly property var rawD: (pg.hub && st.path) ? pg.hub.hyprCommittedVal(st.path) : undefined
        readonly property real numV: Number(st.rawV) || 0
        readonly property real numD: Number(st.rawD) || 0

        function keyLabel(k) {
            for (var i = 0; i < st.opts.length; i++)
                if (String(st.opts[i].key) === String(k === undefined ? "" : k))
                    return st.opts[i].label;
            return String(k === undefined ? "" : k);
        }
        function labelKey(lb) {
            for (var i = 0; i < st.opts.length; i++)
                if (st.opts[i].label === lb)
                    return st.opts[i].key;
            return lb;
        }
        function fmt(n) { return Number(n).toFixed(st.dec); }

        // a 3+-option segmented needs its own band beneath the text; a switch, a
        // stepper, a slider or a 2-option segmented sits inline at the right.
        readonly property bool segBand: st.ctl === "seg" && st.optCount >= 3

        anchors.left: parent.left
        anchors.right: parent.right
        divider: true
        visible: st.gate
        source: "hypr"
        block: st.segBand
        controlWidth: st.ctl === "sw" ? 54
            : st.ctl === "step" ? 58
            : st.ctl === "slid" ? Math.min(240, Math.max(160, Math.round(st.width * 0.34)))
            : st.ctl === "seg" ? Math.max(120, 62 * Math.max(2, st.optCount))
            : 54

        // the numeric readout is a stepper's or slider's alone; a switch or a
        // segmented shows its own state, so it leaves the readout empty.
        value: (st.ctl === "step" || st.ctl === "slid") ? st.fmt(st.numV) : ""
        def: st.ctl === "sw" ? (st.rawD === true ? I18n.tr("ON") : I18n.tr("OFF"))
            : st.ctl === "seg" ? st.keyLabel(st.rawD)
            : st.fmt(st.numD)
        changed: (st.ctl === "sw" || st.ctl === "seg")
            ? String(st.rawV) !== String(st.rawD)
            : st.numV !== st.numD

        Loader {
            anchors.fill: parent
            sourceComponent: st.ctl === "sw" ? swC
                : st.ctl === "seg" ? segC
                : st.ctl === "slid" ? slidC
                : st.ctl === "step" ? stepC : null
        }
        Component {
            id: swC
            Sw {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: st.rawV === true
                onToggled: (v) => pg.he(st.path, v)
            }
        }
        Component {
            id: segC
            Seg {
                anchors.right: parent.right
                anchors.left: st.segBand ? parent.left : undefined
                anchors.verticalCenter: parent.verticalCenter
                options: pg.labels(st.opts)
                current: st.keyLabel(st.rawV)
                onChose: (lb) => {
                    var k = st.labelKey(lb);
                    pg.he(st.path, st.asInt ? parseInt(k, 10) : k);
                }
            }
        }
        Component {
            id: slidC
            Slid {
                anchors.fill: parent
                from: Math.round(st.lo * st.sc)
                to: Math.round(st.hi * st.sc)
                value: Math.round(st.numV * st.sc)
                onModified: (v) => pg.he(st.path,
                    st.dec > 0 ? Number((v / st.sc).toFixed(st.dec)) : Math.round(v / st.sc))
            }
        }
        Component {
            id: stepC
            Step {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                from: Math.round(st.lo)
                to: Math.round(st.hi)
                stepBy: st.stepBy
                value: Math.round(st.numV)
                onModified: (v) => pg.he(st.path, v)
            }
        }
    }

    // ── a kb_options family row (seg / chips / sw over the shared string) ────
    component OptCell: SettingRow {
        id: oc
        property string cellLabel: ""
        property string cellDesc: ""
        property var ids: []
        property var map: []
        property string kind: "seg"
        property string onKey: ""        // the token written when a sw is on
        property bool gate: true

        readonly property int optCount: oc.map.length
        readonly property string curKey: pg.pickFrom(oc.ids, false)
        readonly property string defKey: pg.pickFrom(oc.ids, true)

        // chips and a 3+-option segmented take a band beneath the text; a switch
        // sits inline at the row's right.
        readonly property bool segBand: oc.kind === "seg" && oc.optCount >= 3

        anchors.left: parent.left
        anchors.right: parent.right
        divider: true
        visible: oc.gate
        source: "hypr"
        block: oc.kind === "chips" || oc.segBand
        controlWidth: oc.kind === "sw" ? 54 : Math.max(120, 62 * Math.max(2, oc.optCount))
        label: oc.cellLabel
        desc: oc.cellDesc
        value: ""
        def: oc.kind === "sw" ? (oc.defKey === oc.onKey ? I18n.tr("ON") : I18n.tr("OFF"))
            : oc.kind === "chips" ? "" : pg.mapLabel(oc.map, oc.defKey)
        changed: oc.curKey !== oc.defKey

        Loader {
            anchors.fill: parent
            sourceComponent: oc.kind === "sw" ? swCmp : oc.kind === "chips" ? chipsCmp : segCmp
        }
        Component {
            id: swCmp
            Sw {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: oc.curKey === oc.onKey
                onToggled: (v) => pg.setOption(oc.ids, v ? oc.onKey : "")
            }
        }
        Component {
            id: segCmp
            Seg {
                anchors.right: parent.right
                anchors.left: oc.segBand ? parent.left : undefined
                anchors.verticalCenter: parent.verticalCenter
                options: pg.labels(oc.map)
                current: pg.mapLabel(oc.map, oc.curKey)
                onChose: (lb) => pg.setOption(oc.ids, pg.mapKey(oc.map, lb))
            }
        }
        Component {
            id: chipsCmp
            Chips {
                anchors.fill: parent
                options: pg.labels(oc.map)
                current: pg.mapLabel(oc.map, oc.curKey)
                onChose: (lb) => pg.setOption(oc.ids, pg.mapKey(oc.map, lb))
            }
        }
    }

    // ── a catalogue pick row (layout / variant) ─────────────────────────────
    // The catalogue rides a PickBar in the row's foot band; the current value is
    // the bar's own readout, and the 2px changed edge carries the dirty cue.
    component PickCell: SettingRow {
        id: pc
        property string cellLabel: ""
        property string cellDesc: ""
        property string pickTitle: ""
        property var list: []
        property string currentCode: ""
        property string committedCode: ""
        property var applyFn: null

        anchors.left: parent.left
        anchors.right: parent.right
        divider: true
        footH: 32
        source: "hypr"
        label: pc.cellLabel
        desc: pc.cellDesc
        value: ""
        changed: pc.currentCode !== pc.committedCode

        PickBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            value: pg.nameIn(pc.list, pc.currentCode)
            count: pc.list.length
            onOpened: pg.openCat(pc.pickTitle, pc.list, pc.currentCode, pc.applyFn)
        }
    }

    // background typography: the section kanji set huge and faint behind the
    // whole page, bled off the lower-right and softened, so it dresses the dead
    // margin without ever competing with a control. Texture, not text to read.
    Watermark {
        anchors.fill: parent
        text: "入力"
    }

    // ── head: eyebrow, Fraunces title, blurb (matches every settings page) ──
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
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
                text: I18n.tr("DEVICES"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Input"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Keyboard layout and remaps, pointer and touchpad behaviour, and key repeat for the Hyprland session. Edits preview live; nothing is written until you save.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // marginalia in the head's right margin: the section register, ink only.
    // Input draws its own head, so it carries its own strip (framed pages get
    // the shared rail + bar registers automatically, but not a head one).
    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s1
        kana: "入力"
        index: "02"; label: I18n.tr("DEVICES")
        glyph: "wave"; glyph2: "column"
    }

    // ── KEYBOARD MAP: pinned under the head so it stays in view while you edit,
    // never scrolled to. A compact live diagram of the layout and the remaps,
    // beside a decorative plate that fills the space the small keyboard leaves.
    // The page's one red head -- a showcase surface, not a settings group.
    Section {
        id: kbmSect
        anchors {
            left: parent.left; right: parent.right; top: head.bottom
            topMargin: Tokens.s5; rightMargin: Tokens.s3
        }
        title: I18n.tr("KEYBOARD MAP")
        titleColor: Tokens.sunDeep

        Row {
            spacing: Tokens.s4
            KeyboardMap {
                id: pinnedMap
                compact: true
                keyMax: 40
                width: Math.round(kbmSect.span(Spans.cols) * 0.46)
                height: implicitHeight
                layoutCode: pg.primaryLayout(false)
                layoutName: pg.nameIn(pg.layoutOptions, pg.primaryLayout(false))
                styleName: pg.nameIn(pg.variantOptions, pg.primaryVariant(false))
                capsFn: pg.pickFrom(pg.capsIds, false)
                swapAltSuper: pg.pickFrom([pg.swapId], false) === pg.swapId
                composeKey: pg.pickFrom(pg.composeIds, false)
                switchChord: pg.pickFrom(pg.grpIds, false)
                numlock: pg.hv("input.numlockByDefault") === true
            }
            Decor {
                width: kbmSect.span(Spans.cols) - pinnedMap.width - Tokens.s4
                height: pinnedMap.height
                title: "入力"; sub: "キーボード"
                tate: "配列と再配置"
                caption: I18n.tr("The layout, and the keys you taught new jobs. It answers live as you edit.")
                code: "INPUT-02"; seal: "力"; seed: 4; ditherFreq: 1.0; boxId: "input.map"
            }
        }
    }

    // ── the scrolling body ──────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors {
            left: parent.left; right: parent.right
            top: kbmSect.bottom; bottom: parent.bottom
            topMargin: Tokens.s5
        }
        contentWidth: width
        contentHeight: Math.max(body.height, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: body
            width: flick.width - Tokens.s3   // reserve a lane for the scroll rail
            spacing: Tokens.s5

            SettingCard {
                width: body.width
                title: I18n.tr("KEYBOARD")

                PickCell {
                    divider: false
                    cellLabel: I18n.tr("Layout")
                    cellDesc: I18n.tr("The main keyboard layout.")
                    pickTitle: I18n.tr("KEYBOARD LAYOUT")
                    list: pg.layoutOptions
                    currentCode: pg.primaryLayout(false)
                    committedCode: pg.primaryLayout(true)
                    applyFn: function (code) { pg.setLayouts(code, pg.secondaryLayout(false)); }
                }
                PickCell {
                    cellLabel: I18n.tr("Style")
                    cellDesc: I18n.tr("A variant of the main layout, like Dvorak or intl.")
                    pickTitle: I18n.tr("LAYOUT STYLE")
                    list: pg.variantOptions
                    currentCode: pg.primaryVariant(false)
                    committedCode: pg.primaryVariant(true)
                    applyFn: function (code) { pg.setVariant(code); }
                }
                PickCell {
                    cellLabel: I18n.tr("Second layout")
                    cellDesc: I18n.tr("A spare layout kept loaded; the chord below switches to it.")
                    pickTitle: I18n.tr("SECOND LAYOUT")
                    list: [{ "code": "", "name": I18n.tr("None") }].concat(pg.layoutOptions)
                    currentCode: pg.secondaryLayout(false)
                    committedCode: pg.secondaryLayout(true)
                    applyFn: function (code) { pg.setLayouts(pg.primaryLayout(false), code); }
                }
                OptCell {
                    gate: pg.secondaryLayout(false).length > 0
                    cellLabel: I18n.tr("Switch layouts")
                    cellDesc: I18n.tr("The chord that toggles between the two loaded layouts.")
                    ids: pg.grpIds
                    map: pg.grpMap
                    kind: "seg"
                }
                Setting {
                    path: "input.numlockByDefault"
                    ctl: "sw"
                    label: I18n.tr("Numlock on at login")
                    desc: I18n.tr("Start each session with the keypad typing digits.")
                }
            }

            SettingCard {
                width: body.width
                title: I18n.tr("KEY REMAPS")

                OptCell {
                    divider: false
                    cellLabel: I18n.tr("Caps Lock")
                    cellDesc: I18n.tr("Turn the Caps Lock key into something more useful.")
                    ids: pg.capsIds
                    map: pg.capsMap
                    kind: "chips"
                }
                OptCell {
                    cellLabel: I18n.tr("Swap Alt and Super")
                    cellDesc: I18n.tr("Exchange the Alt and Super modifier keys.")
                    ids: [pg.swapId]
                    map: []
                    kind: "sw"
                    onKey: pg.swapId
                }
                OptCell {
                    cellLabel: I18n.tr("Compose key")
                    cellDesc: I18n.tr("A key that begins a compose sequence for accents and symbols.")
                    ids: pg.composeIds
                    map: pg.composeMap
                    kind: "seg"
                }

                // Extra options: the free-text escape hatch. Everything the family
                // pickers do not recognise round-trips here. Commit on
                // editing-finished (not per keystroke, which would fight the
                // tokeniser mid-word) and re-bind to the draft on focus loss so
                // Reset/Revert refresh the shown text after a manual edit.
                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    divider: true
                    footH: 32
                    source: "hypr"
                    label: I18n.tr("Extra options")
                    desc: I18n.tr("Raw xkb options, comma separated. The pickers above manage their own.")
                    changed: pg.extraOptions(false) !== pg.extraOptions(true)

                    Field {
                        id: extraField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        tabular: true
                        placeholder: I18n.tr("raw xkb options, comma separated")
                        text: pg.extraOptions(false)
                        onCommitted: (v) => pg.setExtra(v)
                        onFocusedChanged: if (!extraField.focused)
                            extraField.text = Qt.binding(function () { return pg.extraOptions(false); })
                    }
                }

                // Apply system-wide: privileged localectl write to /etc, gated on
                // the keyboard keys already being saved so the console matches
                // what the compositor shows.
                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    divider: true
                    controlWidth: 84
                    source: "vconsole"
                    label: I18n.tr("Apply system-wide")
                    desc: I18n.tr("Also set the login screen, the TTYs, and the disk passphrase prompt.")
                    changed: false

                    Btn {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("APPLY")
                        armed: pg.kbClean && !sysApplyProc.running
                        onAct: sysApplyProc.running = true
                    }
                }
                // paired readout: the last apply result, self-clearing after 6s.
                // No colour; the word carries the state (DESIGN.md section 1).
                SettingRow {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    divider: true
                    source: "vconsole"
                    label: I18n.tr("Login screen, TTY, and boot")
                    value: pg.sysApplyState === "ok" ? I18n.tr("APPLIED")
                        : pg.sysApplyState === "err" ? I18n.tr("FAILED") : I18n.tr("READY")
                    desc: pg.sysApplyState === "ok" ? I18n.tr("Applied to the login screen, console, and boot prompt.")
                        : pg.sysApplyState === "err" ? I18n.tr("Not applied. Cancelled or failed.")
                        : I18n.tr("They keep their own keymap until you apply.")
                    changed: false
                }
            }

            SettingCard {
                width: body.width
                title: I18n.tr("POINTER")

                Setting {
                    divider: false
                    path: "input.sensitivity"
                    ctl: "slid"; lo: -1; hi: 1; sc: 100; dec: 2
                    label: I18n.tr("Sensitivity")
                    desc: I18n.tr("Pointer speed offset; 0 is the device default.")
                }
                Setting {
                    path: "input.mouseScrollFactor"
                    ctl: "slid"; lo: 0.2; hi: 3; sc: 10; dec: 1; unit: "×"
                    label: I18n.tr("Scroll speed")
                    desc: I18n.tr("Multiplier on each wheel notch.")
                }
                Setting {
                    path: "input.followMouse"
                    ctl: "seg"; asInt: true
                    opts: [{ "key": 0, "label": I18n.tr("Ignore pointer movement") }, { "key": 1, "label": I18n.tr("Focus under pointer") }, { "key": 2, "label": I18n.tr("Click to focus") }]
                    label: I18n.tr("Focus behavior")
                    desc: I18n.tr("Click to focus keeps newly launched and dock-selected apps in front.")
                }
                Setting {
                    path: "input.leftHanded"
                    ctl: "sw"
                    label: I18n.tr("Left-handed buttons")
                    desc: I18n.tr("Swap the left and right mouse buttons.")
                }
                Setting {
                    path: "input.accelProfile"
                    ctl: "seg"
                    opts: [{ "key": "", "label": I18n.tr("Default") }, { "key": "flat", "label": I18n.tr("Flat") }, { "key": "adaptive", "label": I18n.tr("Adaptive") }]
                    label: I18n.tr("Acceleration")
                    desc: I18n.tr("Flat ties travel to the hand; Adaptive speeds quick moves.")
                }
                Setting {
                    path: "input.mouseNaturalScroll"
                    ctl: "sw"
                    label: I18n.tr("Natural scroll")
                    desc: I18n.tr("Roll the wheel up and the page moves up.")
                }
                Setting {
                    path: "input.middleClickPaste"
                    ctl: "sw"
                    label: I18n.tr("Middle-click pastes")
                    desc: I18n.tr("Press the wheel to insert the last highlighted text.")
                }
            }

            SettingCard {
                width: body.width
                title: I18n.tr("TOUCHPAD")

                Setting {
                    divider: false
                    path: "input.naturalScroll"
                    ctl: "sw"
                    label: I18n.tr("Natural scroll")
                    desc: I18n.tr("Two fingers drag the content like a touchscreen.")
                }
                Setting {
                    path: "input.tapToClick"
                    ctl: "sw"
                    label: I18n.tr("Tap to click")
                    desc: I18n.tr("A tap counts as a click; two fingers right, three middle.")
                }
                Setting {
                    path: "input.tapAndDrag"
                    ctl: "sw"
                    label: I18n.tr("Tap and drag")
                    desc: I18n.tr("Tap, then hold the finger down to drag what you tapped.")
                }
                Setting {
                    path: "input.disableWhileTyping"
                    ctl: "sw"
                    label: I18n.tr("Disable while typing")
                    desc: I18n.tr("Ignore the touchpad while you type so a palm cannot nudge it.")
                }
                Setting {
                    path: "input.clickfinger"
                    ctl: "sw"
                    label: I18n.tr("Click by finger count")
                    desc: I18n.tr("One finger clicks left, two right, three middle.")
                }
                Setting {
                    path: "input.middleEmulation"
                    ctl: "sw"
                    label: I18n.tr("Emulate middle click")
                    desc: I18n.tr("Press left and right together for a middle click.")
                }
                Setting {
                    path: "input.touchScrollFactor"
                    ctl: "slid"; lo: 0.2; hi: 3; sc: 10; dec: 1; unit: "×"
                    label: I18n.tr("Scroll speed")
                    desc: I18n.tr("Multiplier on two-finger scroll distance.")
                }
                Setting {
                    path: "input.workspaceSwipe"
                    ctl: "sw"
                    label: I18n.tr("Swipe between workspaces")
                    desc: I18n.tr("A horizontal swipe slides to the next workspace.")
                }
                Setting {
                    path: "input.swipeFingers"
                    ctl: "seg"; asInt: true; gate: pg.swipeOn
                    opts: [{ "key": 3, "label": "3" }, { "key": 4, "label": "4" }]
                    label: I18n.tr("Swipe fingers")
                    desc: I18n.tr("How many fingers count as a workspace swipe.")
                }
                Setting {
                    path: "input.swipeInvert"
                    ctl: "sw"; gate: pg.swipeOn
                    label: I18n.tr("Natural swipe direction")
                    desc: I18n.tr("The workspace row follows your fingers.")
                }
                Setting {
                    path: "input.swipeCreateNew"
                    ctl: "sw"; gate: pg.swipeOn
                    label: I18n.tr("Swipe past the last workspace")
                    desc: I18n.tr("Swiping past the end opens a fresh workspace instead of stopping.")
                }
                Setting {
                    path: "input.swipeDistance"
                    ctl: "slid"; lo: 100; hi: 600; sc: 1; dec: 0; unit: "px"; gate: pg.swipeOn
                    label: I18n.tr("Swipe distance")
                    desc: I18n.tr("Finger travel for a full switch; lower flips sooner.")
                }
            }

            SettingCard {
                width: body.width
                title: I18n.tr("KEY REPEAT")

                Setting {
                    divider: false
                    path: "input.repeatRate"
                    ctl: "step"; lo: 1; hi: 100; stepBy: 1; unit: "/s"
                    label: I18n.tr("Repeat rate")
                    desc: I18n.tr("Characters per second while a key is held.")
                }
                Setting {
                    path: "input.repeatDelay"
                    ctl: "step"; lo: 100; hi: 2000; stepBy: 50; unit: "ms"
                    label: I18n.tr("Repeat delay")
                    desc: I18n.tr("Pause before a held key starts repeating.")
                }
            }
        }
    }

    // ── the catalogue overlay: paperLift + lineStrong, one z-plane above ──────
    Item {
        anchors.fill: parent
        visible: pg.catList !== null
        z: 900

        Rectangle {
            anchors.fill: parent
            color: Tokens.paper
            opacity: 0.55
            TapHandler { onTapped: pg.closeCat() }
        }
        Picker {
            id: catPicker
            anchors.centerIn: parent
            title: pg.catTitle
            options: pg.catNames
            current: pg.catCurrentName
            onChose: (name) => pg.chooseCat(name)
            onDismissed: pg.closeCat()
        }
    }
}
