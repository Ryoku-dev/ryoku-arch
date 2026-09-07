import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "ReloadCoverModel.js" as ReloadCoverModel

// Renders a page from its schema as grouped, compact rows. A setting is a row
// of data; which card it lands in comes from its group and what draws it from
// its kind, so adding one is an edit to the schema and nothing else.
//
// Each group is a SettingCard (a bordered, collapsible sheet); each setting is a
// SettingRow inside it (label + description on the left, control on the right,
// or a band beneath for a control that needs room). This replaced the bento
// grid of value-hero cards, which read as scattered tiles; rows in a card read
// as one instrument sheet.
//
// The draft object holds live values and is the page's own; this only reads it
// and reports edits back. The one file it writes is the weather resolver cache
// (the picked place's coords the weather widgets read), on a location pick.
Item {
    id: sheet

    property var schema: []          // [{ tab, group, key, label, desc, ctl, src, opts, lo, hi, unit, pct }]
    property var draft: null         // the page's live values
    property var defaults: ({})      // factory values, for the struck default
    property string tab: ""
    property string query: ""
    // progressive disclosure: rows tagged `adv: true` are the deep knobs, hidden
    // until Advanced is on. search still reaches them (the query branch ignores
    // this), so nothing is ever truly buried.
    property bool advanced: false
    // the row a search jump lands on: switched to, scrolled into view, and
    // flashed. Cleared shortly after so the wash is a pulse, not a highlight.
    property string spotlightKey: ""
    property string reloadCoverError: ""
    property bool reloadCoverImportBusy: false

    signal edited(string key, var value)

    // key -> the live SettingRow, so a search jump can find and scroll to it.
    property var rowItems: ({})

    // A row can gate itself on OTHER settings through `when`: { key: [values] }.
    // Without it the visualiser page shows knobs that do nothing for the chosen
    // look (segment count on plain bars, reflection on an orb), the confusion
    // this removes. Every named key's live draft value must sit in its list; a
    // missing value fails the gate, so a knob for a look you are not on stays
    // hidden — except before the draft has loaded, where the row shows rather
    // than blank the page. Read straight from the draft, since `when` names
    // keys other than this row's own.
    function passes(r) {
        if (!r.when) return true;
        if (!draft || Object.keys(draft).length === 0) return true;
        for (var k in r.when)
            if (r.when[k].indexOf(draft[k]) < 0) return false;
        return true;
    }

    readonly property var rows: {
        var q = query.toLowerCase();
        return schema.filter(function (r) {
            if (!sheet.passes(r)) return false;
            if (r.adv && !sheet.advanced && query === "") return false;
            if (r.tab !== sheet.tab && query === "") return false;
            if (query === "") return true;
            return (r.label + " " + (r.desc || "") + " " + r.key).toLowerCase().indexOf(q) >= 0;
        });
    }
    readonly property var groups: {
        var g = [];
        for (var i = 0; i < rows.length; i++)
            if (g.indexOf(rows[i].group) < 0) g.push(rows[i].group);
        return g;
    }

    function val(r) {
        if (!draft) return "";
        var v = draft[r.key];
        return v === undefined ? "" : v;
    }
    function shown(r) {
        var v = val(r);
        if (r.ctl === "sw") return v ? "ON" : "OFF";
        if (r.ctl === "slid" && r.pct) return String(Math.round(v * 100));
        if (r.ctl === "multi") return String((v || []).length);
        if (r.ctl === "color") return String(v).toUpperCase();
        return String(v);
    }
    function shownDef(r) {
        if (r.ctl === "reload-cover") return I18n.tr("DEFAULT");
        var d = defaults[r.key];
        if (d === undefined) return "";
        if (r.ctl === "sw") return d ? "ON" : "OFF";
        if (r.ctl === "slid" && r.pct) return String(Math.round(d * 100));
        if (r.ctl === "multi") return String((d || []).length);
        return String(d);
    }
    function isChanged(r) {
        var v = val(r), d = defaults[r.key];
        if (r.ctl === "reload-cover")
            return JSON.stringify(ReloadCoverModel.normalize(v)) !== JSON.stringify(ReloadCoverModel.normalize(d));
        if (d === undefined) return false;
        if (r.ctl === "multi") return JSON.stringify(v || []) !== JSON.stringify(d || []);
        return v !== d;
    }
    function resetRow(r) {
        if (r.ctl === "reload-cover") {
            sheet.edited(r.key, ReloadCoverModel.empty());
            return;
        }
        var d = defaults[r.key];
        if (d !== undefined) sheet.edited(r.key, d);
    }

    // A row's option list. Most rows write theirs in the schema; a row whose
    // list is really a system table (`set`) reads it from the singleton that
    // owns it, so the table lives in exactly one place. Every consumer of
    // `opts` goes through here.
    function optsFor(r) {
        if (r.set === "languages") return I18n.pickerOptions;
        if (r.set === "locales") return I18n.localeOptions;
        return r.opts || [];
    }
    function labelsFor(r) {
        if (r.set === "languages") return I18n.pickerLabels;
        return ({});
    }

    // inline vs band, and how wide, decided once from the control kind. A
    // control that needs room (chips, a gallery, a segmented bar of 3+, a demo)
    // gets a band whose height is its own; a picker or field gets a fixed foot
    // band; everything else sits inline at the row's right.
    function ctlBlock(r) {
        var c = r.ctl, n = sheet.optsFor(r).length;
        if (c === "chips" || c === "multi" || c === "gallery" || c === "layoutdemo" || c === "reload-cover") return true;
        if (c === "seg" && n >= 3) return true;
        return false;
    }
    function ctlFoot(r) {
        var c = r.ctl;
        if (c === "pick" || c === "text" || c === "color" || c === "location" || c === "image" || c === "action" || c === "app" || c === "timezone") return 32;
        return 0;
    }
    function ctlWidth(r, w) {
        var c = r.ctl, n = sheet.optsFor(r).length;
        if (c === "sw") return 54;
        if (c === "step") return 58;
        if (c === "slid") return Math.min(240, Math.max(160, Math.round(w * 0.34)));
        if (c === "seg") return Math.max(120, 62 * Math.max(2, n));
        return 54;
    }
    // the compact readout: a number for a stepper or slider; nothing for a
    // toggle (the switch is the state) or a control that shows its own value.
    function rowValue(r) {
        if (r.ctl === "step" || r.ctl === "slid") return sheet.shown(r);
        return "";
    }
    function rowUnit(r) {
        if (r.ctl === "step" || r.ctl === "slid") return r.pct ? "%" : (r.unit || "");
        return "";
    }

    // search jump: switch to the row's tab, then scroll it to centre and flash.
    function focusKey(key) {
        var r = null;
        for (var i = 0; i < schema.length; i++) if (schema[i].key === key) { r = schema[i]; break; }
        if (!r) return;
        if (r.tab && r.tab !== sheet.tab) sheet.tab = r.tab;
        sheet.spotlightKey = "";
        scrollPending.key = key;
        scrollPending.tries = 0;
        scrollTimer.restart();
    }
    QtObject { id: scrollPending; property string key: ""; property int tries: 0 }
    Timer {
        id: scrollTimer
        interval: 40
        repeat: false
        onTriggered: {
            var it = sheet.rowItems[scrollPending.key];
            if (!it && scrollPending.tries < 12) { scrollPending.tries++; scrollTimer.restart(); return; }
            if (!it) return;
            var y = it.mapToItem(col, 0, 0).y;
            var target = Math.max(0, Math.min(y - flick.height / 2 + it.height / 2, Math.max(0, col.height - flick.height)));
            scrollAnim.to = target;
            scrollAnim.restart();
            sheet.spotlightKey = scrollPending.key;
            clearSpot.restart();
        }
    }
    NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: Tokens.move; easing.type: Tokens.ease }
    Timer { id: clearSpot; interval: 1600; onTriggered: sheet.spotlightKey = "" }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + Tokens.s5
        clip: true
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            // a settings sheet reads better bounded than sprawled edge to edge:
            // cap the column so rows do not run a label metres from its control.
            width: Math.min(flick.width - 14, 1000)
            spacing: Tokens.s4

            Repeater {
                model: sheet.groups
                SettingCard {
                    id: card
                    required property string modelData
                    width: col.width
                    title: I18n.tr(modelData === "" ? "OTHER" : modelData)

                    readonly property var groupRows: sheet.rows.filter(function (r) { return r.group === card.modelData })

                    Repeater {
                        model: card.groupRows
                        SettingRow {
                            id: srow
                            required property var modelData
                            required property int index
                            readonly property var r: modelData

                            anchors.left: parent.left
                            anchors.right: parent.right
                            divider: index > 0

                            label: I18n.tr(r.label)
                            desc: I18n.tr(r.desc || "")
                            eg: I18n.tr(r.eg || "")
                            value: sheet.rowValue(r)
                            unit: sheet.rowUnit(r)
                            def: sheet.shownDef(r)
                            changed: sheet.isChanged(r)
                            source: r.src ? r.src + ".json" : ""
                            block: sheet.ctlBlock(r)
                            footH: sheet.ctlBlock(r) ? 0 : sheet.ctlFoot(r)
                            controlWidth: sheet.ctlWidth(r, card.width)
                            spotlight: sheet.spotlightKey !== "" && sheet.spotlightKey === r.key
                            onResetRequested: sheet.resetRow(r)

                            Component.onCompleted: { var m = sheet.rowItems; m[r.key] = srow; sheet.rowItems = m; }
                            Component.onDestruction: { if (sheet.rowItems[r.key] === srow) delete sheet.rowItems[r.key]; }

                            Loader {
                                anchors.fill: parent
                                sourceComponent: {
                                    switch (srow.r.ctl) {
                                    case "sw": return swC;
                                    case "step": return stepC;
                                    case "slid": return slidC;
                                    case "seg": return segC;
                                    case "chips": return chipsC;
                                    case "multi": return multiC;
                                    case "pick": return pickC;
                                    case "gallery": return galleryC;
                                    case "reload-cover": return reloadCoverC;
                                    case "image": return imageC;
                                    case "app": return appC;
                                    case "location": return locationC;
                                    case "color": return colorC;
                                    case "action": return actionC;
                                    case "layoutdemo": return layoutDemoC;
                                    case "timezone": return timezoneC;
                                    default: return textC;
                                    }
                                }
                            }

                            Component {
                                id: actionC
                                Btn {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    text: I18n.tr(srow.r.actionLabel || "Generate")
                                    onAct: {
                                        if (srow.r.key === "i18nGenerate")
                                            Spawn.run(["kitty", "--class", "ryoku-i18n", "-e", "sh", "-c",
                                                "ryoku-i18n llm " + I18n.lang + "; echo; read -n1 -rsp 'Done. Press any key to close…'; echo"]);
                                        // hands the shell its placement mode: the look becomes draggable
                                        // on the desktop, which no slider in here can be.
                                        else if (srow.r.key === "vizPlace")
                                            Spawn.run(["qs", "-c", "shell", "ipc", "call", "visualizer", "place"]);
                                    }
                                }
                            }
                            Component {
                                id: timezoneC
                                Row {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    spacing: Tokens.s3
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (srow.r.tzCurrent && ("" + srow.r.tzCurrent).length) ? ("" + srow.r.tzCurrent).replace(/_/g, " ") : "\u2014"
                                        color: Tokens.ink
                                        font.family: Tokens.mono
                                        font.pixelSize: Tokens.fSmall
                                    }
                                    Btn {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("CHANGE ON MAP")
                                        onAct: sheet.timezonePick(srow.r)
                                    }
                                }
                            }
                            Component {
                                id: layoutDemoC
                                Item {
                                    id: demo
                                    anchors.fill: parent
                                    implicitHeight: 168
                                    readonly property string layout: {
                                        var v = sheet.draft ? sheet.draft["appearance.layout"] : "";
                                        return (v === "master" || v === "scrolling") ? v : "dwindle";
                                    }
                                    readonly property var blurbs: ({
                                        "dwindle": "Each new window splits the focused frame in two, so the layout spirals into smaller and smaller frames.",
                                        "master": "One big master frame keeps the focus; every other window stacks down the side beside it.",
                                        "scrolling": "Windows line up in one endless horizontal row; the strip pans sideways to keep the focused column in view."
                                    })
                                    Rectangle {
                                        id: demoScreen
                                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                        width: Math.min(360, demo.width * 0.5)
                                        color: "transparent"
                                        radius: Tokens.radius
                                        border.width: Tokens.border
                                        border.color: Tokens.line
                                        AnimatedImage {
                                            anchors.fill: parent
                                            anchors.margins: Tokens.s3
                                            source: Qt.resolvedUrl("art/tiling-" + demo.layout + ".gif")
                                            fillMode: Image.PreserveAspectFit
                                            playing: true
                                            cache: false
                                            asynchronous: true
                                            onStatusChanged: if (status === Image.Ready) playing = true
                                        }
                                    }
                                    Column {
                                        anchors { left: demoScreen.right; leftMargin: Tokens.s5; right: parent.right; verticalCenter: demoScreen.verticalCenter }
                                        spacing: Tokens.s2
                                        Text {
                                            text: demo.layout.toUpperCase()
                                            color: Tokens.ink
                                            font.family: Tokens.ui
                                            font.pixelSize: Tokens.fValue
                                            font.weight: Font.Light
                                        }
                                        Text {
                                            width: parent.width
                                            text: demo.blurbs[demo.layout]
                                            color: Tokens.inkMuted
                                            font.family: Tokens.ui
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                            Component {
                                id: swC
                                Sw {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: !!sheet.val(srow.r)
                                    onToggled: (v) => sheet.edited(srow.r.key, v)
                                }
                            }
                            Component {
                                id: stepC
                                Step {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: Number(sheet.val(srow.r)) || 0
                                    from: Number(srow.r.lo) || 0
                                    to: Number(srow.r.hi) || 100
                                    onModified: (v) => sheet.edited(srow.r.key, v)
                                }
                            }
                            Component {
                                id: slidC
                                Slid {
                                    anchors.fill: parent
                                    value: Number(sheet.val(srow.r)) || 0
                                    from: Number(srow.r.lo) || 0
                                    to: Number(srow.r.hi) || 1
                                    onModified: (v) => sheet.edited(srow.r.key, v)
                                }
                            }
                            Component {
                                id: segC
                                Seg {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    options: sheet.optsFor(srow.r)
                                    current: String(sheet.val(srow.r))
                                    onChose: (k) => sheet.edited(srow.r.key, k)
                                }
                            }
                            Component {
                                id: chipsC
                                Chips {
                                    anchors.fill: parent
                                    options: sheet.optsFor(srow.r)
                                    current: String(sheet.val(srow.r))
                                    onChose: (k) => sheet.edited(srow.r.key, k)
                                }
                            }
                            Component {
                                id: multiC
                                Multi {
                                    anchors.fill: parent
                                    options: sheet.optsFor(srow.r)
                                    chosen: sheet.val(srow.r) || []
                                    onToggled: (k) => {
                                        var l = (sheet.val(srow.r) || []).slice();
                                        var i = l.indexOf(k);
                                        if (i >= 0) l.splice(i, 1); else l.push(k);
                                        sheet.edited(srow.r.key, l);
                                    }
                                }
                            }
                            Component {
                                id: galleryC
                                Gallery {
                                    // `set: "viz"` draws from the visualiser
                                    // look catalogue, which paints its own tiles;
                                    // an unset row keeps the bar-skin gallery.
                                    readonly property bool viz: srow.r.set === "viz"
                                    anchors.fill: parent
                                    painter: viz ? VizStyles : null
                                    options: viz
                                        ? VizStyles.styles.map((s) => ({ key: s.key, origin: s.kind, draw: s.key }))
                                        : Silhouette.skins.filter((skin) => !srow.r.opts || srow.r.opts.indexOf(skin.key) >= 0)
                                    current: String(sheet.val(srow.r))
                                    onChose: (k) => sheet.edited(srow.r.key, k)
                                }
                            }
                            Component {
                                id: reloadCoverC
                                ReloadCoverControl {
                                    anchors.fill: parent
                                    descriptor: ReloadCoverModel.normalize(sheet.val(srow.r))
                                    errorText: sheet.reloadCoverError
                                    busy: sheet.reloadCoverImportBusy
                                    onAddRequested: sheet.reloadCoverPick(srow.r)
                                    onDefaultRequested: sheet.reloadCoverDefault(srow.r)
                                    onEnabledToggled: (enabled) => {
                                        var descriptor = Object.assign({}, ReloadCoverModel.normalize(sheet.val(srow.r)));
                                        descriptor.enabled = enabled;
                                        sheet.edited(srow.r.key, descriptor);
                                    }
                                }
                            }
                            Component {
                                id: pickC
                                PickBar {
                                    anchors.fill: parent
                                    value: String(sheet.val(srow.r))
                                    count: sheet.optsFor(srow.r).length
                                    labels: sheet.labelsFor(srow.r)
                                    onOpened: sheet.openPick(srow.r)
                                }
                            }
                            Component {
                                id: textC
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: Tokens.radius
                                    border.width: ti.activeFocus ? 2 : Tokens.border
                                    border.color: ti.activeFocus ? Tokens.ink : Tokens.line
                                    TextInput {
                                        id: ti
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: Text.AlignVCenter
                                        clip: true
                                        autoScroll: activeFocus
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: 12
                                        selectByMouse: true
                                        text: String(sheet.val(srow.r))
                                        onEditingFinished: sheet.edited(srow.r.key, text)
                                        onTextEdited: sheet.edited(srow.r.key, text)
                                    }
                                }
                            }
                            Component {
                                id: colorC
                                ColorField {
                                    anchors.fill: parent
                                    value: String(sheet.val(srow.r))
                                    onChosen: (v) => sheet.edited(srow.r.key, v)
                                }
                            }
                            Component {
                                id: imageC
                                Row {
                                    anchors.fill: parent
                                    spacing: Tokens.s2
                                    Rectangle {
                                        id: imgThumb
                                        width: 46; height: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: Tokens.radius
                                        color: "transparent"
                                        border.width: Tokens.border
                                        border.color: Tokens.line
                                        clip: true
                                        readonly property string src: String(sheet.val(srow.r))
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            visible: imgThumb.src !== ""
                                            source: imgThumb.src === "" ? "" : (imgThumb.src.indexOf("://") >= 0 ? imgThumb.src : "file://" + imgThumb.src)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 140
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: imgThumb.src === ""
                                            text: "力"
                                            color: Tokens.inkFaint
                                            font.family: Tokens.jp
                                            font.pixelSize: 13
                                        }
                                    }
                                    Btn {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("CHOOSE…")
                                        onAct: sheet.imagePick(srow.r)
                                    }
                                    Btn {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: String(sheet.val(srow.r)) !== ""
                                        text: I18n.tr("CLEAR")
                                        onAct: sheet.edited(srow.r.key, "")
                                    }
                                }
                            }
                            Component {
                                id: appC
                                Item {
                                    anchors.fill: parent
                                    Btn {
                                        id: defBtn
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: String(sheet.val(srow.r)) !== ""
                                        text: I18n.tr("DEFAULT")
                                        onAct: sheet.edited(srow.r.key, "")
                                    }
                                    Btn {
                                        id: chooseBtn
                                        anchors.right: defBtn.visible ? defBtn.left : parent.right
                                        anchors.rightMargin: defBtn.visible ? Tokens.s2 : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("CHOOSE…")
                                        onAct: sheet.appPick(srow.r)
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: chooseBtn.left
                                        anchors.rightMargin: Tokens.s2
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        readonly property string cmd: String(sheet.val(srow.r))
                                        text: cmd.length ? cmd : I18n.tr("ryotunes (YouTube Music)")
                                        color: cmd.length ? Tokens.ink : Tokens.inkMuted
                                        font.family: Tokens.ui
                                        font.pixelSize: 12
                                    }
                                }
                            }
                            Component {
                                id: locationC
                                Item {
                                    id: locRoot
                                    anchors.fill: parent
                                    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"

                                    Rectangle {
                                        id: locField
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                        height: 30
                                        color: "transparent"
                                        radius: Tokens.radius
                                        border.width: lti.activeFocus ? 2 : Tokens.border
                                        border.color: lti.activeFocus ? Tokens.ink : Tokens.line
                                        TextInput {
                                            id: lti
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            verticalAlignment: Text.AlignVCenter
                                            clip: true
                                            autoScroll: activeFocus
                                            color: Tokens.ink
                                            font.family: Tokens.ui
                                            font.pixelSize: 12
                                            selectByMouse: true
                                            text: String(sheet.val(srow.r))
                                            onTextEdited: debounce.restart()
                                            onEditingFinished: sheet.edited(srow.r.key, text)
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            visible: lti.text === "" && !lti.activeFocus
                                            text: I18n.tr("Empty locates by IP")
                                            color: Tokens.inkFaint
                                            font.family: Tokens.ui
                                            font.pixelSize: 12
                                        }
                                    }

                                    Timer {
                                        id: debounce
                                        interval: 300
                                        onTriggered: {
                                            var q = lti.text.trim();
                                            if (q.length < 2) { locPop.close(); return; }
                                            geo.command = ["curl", "-s", "--max-time", "6",
                                                "https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&format=json&name=" + encodeURIComponent(q)];
                                            geo.running = false;
                                            geo.running = true;
                                        }
                                    }

                                    Process {
                                        id: geo
                                        stdout: StdioCollector {
                                            onStreamFinished: {
                                                var out = [];
                                                try {
                                                    var j = JSON.parse(this.text);
                                                    if (j && Array.isArray(j.results)) {
                                                        for (var i = 0; i < j.results.length; i++) {
                                                            var rr = j.results[i];
                                                            if (typeof rr.latitude === "number" && typeof rr.longitude === "number")
                                                                out.push({ name: rr.name || "", admin1: rr.admin1 || "", country: rr.country || "", lat: rr.latitude, lon: rr.longitude });
                                                        }
                                                    }
                                                } catch (e) {}
                                                locList.model = out;
                                                if (out.length > 0 && lti.activeFocus) locPop.open(); else locPop.close();
                                            }
                                        }
                                    }

                                    FileView {
                                        id: locCache
                                        path: locRoot.stateDir + "/weather-loc.json"
                                        blockLoading: true
                                        printErrors: false
                                    }

                                    Popup {
                                        id: locPop
                                        parent: locField
                                        y: -locPop.height - 2
                                        width: locField.width
                                        padding: 1
                                        focus: false
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                        implicitHeight: Math.min(locList.count, 6) * 28 + 2
                                        background: Rectangle {
                                            color: Tokens.paperLift
                                            radius: Tokens.radius
                                            border.width: Tokens.border
                                            border.color: Tokens.lineStrong
                                        }
                                        contentItem: ListView {
                                            id: locList
                                            clip: true
                                            model: []
                                            delegate: Rectangle {
                                                id: lrow
                                                required property var modelData
                                                width: ListView.view.width
                                                height: 28
                                                color: lhov.hovered ? Tokens.tint10 : "transparent"
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    elide: Text.ElideRight
                                                    text: lrow.modelData.name + (lrow.modelData.admin1 ? "  ·  " + lrow.modelData.admin1 : "") + (lrow.modelData.country ? "  ·  " + lrow.modelData.country : "")
                                                    color: Tokens.ink
                                                    font.family: Tokens.ui
                                                    font.pixelSize: 12
                                                }
                                                HoverHandler { id: lhov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        lti.text = lrow.modelData.name;
                                                        sheet.edited(srow.r.key, lrow.modelData.name);
                                                        locCache.setText(JSON.stringify({ query: lrow.modelData.name, city: lrow.modelData.name, lat: lrow.modelData.lat, lon: lrow.modelData.lon }));
                                                        locPop.close();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    signal pickRequested(var row)
    function openPick(r) { pickRequested(r) }

    signal imagePickRequested(var row)
    function imagePick(r) { imagePickRequested(r) }

    signal appPickRequested(var row)
    function appPick(r) { appPickRequested(r) }

    signal timezonePickRequested(var row)
    function timezonePick(r) { timezonePickRequested(r) }

    signal reloadCoverPickRequested(var row)
    function reloadCoverPick(r) { reloadCoverPickRequested(r) }

    signal reloadCoverDefaultRequested(var row)
    function reloadCoverDefault(r) { reloadCoverDefaultRequested(r) }

    Column {
        anchors.centerIn: parent
        visible: sheet.rows.length === 0
        spacing: Tokens.s2
        Text {
            text: I18n.tr("NO MATCH")
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fRow
            font.letterSpacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: I18n.tr("nothing here matches “%1”").arg(sheet.query)
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
