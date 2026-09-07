pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Window Rules (DESIGN.md section 11, ADVANCED). Custom Hyprland window rules
// layered over the ones Ryoku ships: each entry matches a window by class
// and/or title and applies ONE action, a few of which carry a typed value.
// This is not a settings sheet -- windowRules is an array of rule records, so
// it is a bespoke list editor: a section head, a scrolling column of rule
// cells (two match Fields + an action Picker + a conditional value control +
// remove), wired to the hub's hypr store. List edits aren't previewed live;
// they apply on Save, which is the shell's action bar, not this page's. Every
// value is a Token.
Item {
    id: pg

    property var hub

    // the live rule array from the draft: a list of { class, title, action, value }.
    readonly property var ruleRows: pg.hub ? (pg.hub.hyprVal("windowRules") || []) : []
    // gated so the empty state does not flash before `hypr get` returns.
    readonly property bool ready: pg.hub ? pg.hub.hyprLoaded === true : false

    // the 25 rule keywords, key -> visible label. carried verbatim from the old
    // page: the keys are the exact strings the Go backend's genWindowRule
    // switches on, so a rename here silently breaks settings.lua.
    readonly property var actionOptions: [
        { "key": "float", "label": I18n.tr("Float") },
        { "key": "tile", "label": I18n.tr("Tile") },
        { "key": "pin", "label": I18n.tr("Pin") },
        { "key": "fullscreen", "label": I18n.tr("Fullscreen") },
        { "key": "maximize", "label": I18n.tr("Maximize") },
        { "key": "center", "label": I18n.tr("Centre") },
        { "key": "size", "label": I18n.tr("Size (WxH)") },
        { "key": "move", "label": I18n.tr("Move (X,Y)") },
        { "key": "workspace", "label": I18n.tr("Workspace") },
        { "key": "opacity", "label": I18n.tr("Opacity") },
        { "key": "noblur", "label": I18n.tr("No blur") },
        { "key": "noborder", "label": I18n.tr("No border") },
        { "key": "noshadow", "label": I18n.tr("No shadow") },
        { "key": "norounding", "label": I18n.tr("Square corners") },
        { "key": "nodim", "label": I18n.tr("Never dim") },
        { "key": "noanim", "label": I18n.tr("No animations") },
        { "key": "opaque", "label": I18n.tr("Force opaque") },
        { "key": "xray", "label": I18n.tr("Blur X-ray") },
        { "key": "nofocus", "label": I18n.tr("Never take focus") },
        { "key": "stayfocused", "label": I18n.tr("Hold focus (dialogs)") },
        { "key": "keepaspectratio", "label": I18n.tr("Keep aspect ratio") },
        { "key": "pseudo", "label": I18n.tr("Pseudo-tile") },
        { "key": "immediate", "label": I18n.tr("Immediate (tearing)") },
        { "key": "idleinhibit", "label": I18n.tr("Block idle/sleep") },
        { "key": "suppressevent", "label": I18n.tr("Ignore app request") }
    ]
    // actions carrying a value: the text ones are free-form, idleinhibit and
    // suppressevent pick from a fixed enumerated set (rendered as a Seg below).
    readonly property var valueActions: ["opacity", "size", "move", "workspace", "idleinhibit", "suppressevent"]
    readonly property var textValueActions: ["opacity", "size", "move", "workspace"]
    readonly property var idleInhibitOptions: [
        { "key": "always", "label": I18n.tr("Always") },
        { "key": "focus", "label": I18n.tr("Focus") },
        { "key": "fullscreen", "label": I18n.tr("Fullscreen") }
    ]
    readonly property var suppressEventOptions: [
        { "key": "maximize", "label": I18n.tr("Maximize") },
        { "key": "fullscreen", "label": I18n.tr("Fullscreen") },
        { "key": "activate", "label": I18n.tr("Activate") },
        { "key": "activatefocus", "label": I18n.tr("Activate focus") }
    ]
    function actionValueDefault(k) {
        return k === "idleinhibit" ? "always"
            : k === "suppressevent" ? "maximize" : "";
    }

    // key <-> label mapping over an option set; missing keys fall through to the
    // raw key so a legacy orphan action (e.g. "noshadow") still reads as itself
    // rather than vanishing.
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
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("windowRules") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = val;
        pg.hub.hyprEdit("windowRules", a);
    }
    // switching action resets the value to that action's default: the two
    // enumerated actions seed their first choice, everything else clears it.
    function setAction(i, key) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("windowRules") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i].action = key;
        a[i].value = pg.actionValueDefault(key);
        pg.hub.hyprEdit("windowRules", a);
    }
    function addRule() {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("windowRules") || []).slice();
        a.push({ "class": "", "title": "", "action": "float", "value": "" });
        pg.hub.hyprEdit("windowRules", a);
    }
    function removeRule(i) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("windowRules") || []).slice();
        a.splice(i, 1);
        pg.hub.hyprEdit("windowRules", a);
    }
    function clearAll() {
        if (pg.hub)
            pg.hub.hyprEdit("windowRules", []);
    }

    // which row's action Picker is open; -1 = closed.
    property int pickerRow: -1
    function openPicker(i) {
        pg.pickerRow = i;
        picker.open();
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
                text: I18n.tr("APPS & KEYS"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Window Rules"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Custom rules layered over the ones Ryoku ships. Match a window by its class and/or title, then pick what to do: float a dialog, pin a video, force it opaque, and more. Changes apply when you save.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── section head: dot + RULES + leader + count + clear all + add ──
    Item {
        id: sect
        anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: Tokens.s5 }
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
                text: I18n.tr("RULES"); color: Tokens.ink; font.family: Tokens.ui
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
                // an entry count is file-truth chrome, so mono (DESIGN.md section 2).
                text: pg.ruleRows.length === 1 ? I18n.tr("%1 RULE").arg(pg.ruleRows.length) : I18n.tr("%1 RULES").arg(pg.ruleRows.length)
                color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("CLEAR ALL")
                armed: pg.ruleRows.length > 0
                onAct: pg.clearAll()
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "+"
                onAct: pg.addRule()
            }
        }

        Rectangle {
            anchors.left: sectLabel.right; anchors.right: sectActions.left
            anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            height: 1; color: Tokens.lineSoft
        }
    }

    // ── the scrolling rule list ──
    Flickable {
        id: flick
        anchors {
            left: parent.left; right: parent.right
            top: sect.bottom; bottom: parent.bottom
            topMargin: Tokens.s4
        }
        contentWidth: width
        contentHeight: Math.max(col.height, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            width: flick.width - Tokens.s3   // reserve a lane for the scroll rail
            spacing: Tokens.s2

            Repeater {
                model: pg.ruleRows

                delegate: Rectangle {
                    id: rowRect
                    required property int index
                    required property var modelData

                    // sheet control height: Fields, the Picker foot bar and the
                    // value Seg all sit centred in a row this tall.
                    readonly property int lineH: 30
                    readonly property real gap: Tokens.s2
                    readonly property real removeW: 26

                    readonly property string act: rowRect.modelData.action || ""
                    readonly property bool textValue: pg.textValueActions.indexOf(act) >= 0
                    readonly property bool idle: act === "idleinhibit"
                    readonly property bool suppress: act === "suppressevent"
                    readonly property bool hasValue: pg.valueActions.indexOf(act) >= 0
                    // free-form value guidance -- the only hint the user gets.
                    readonly property string valueHint: act === "opacity" ? "0.0 - 1.0"
                        : act === "size" ? "1200x800"
                        : act === "move" ? "100,60"
                        : act === "workspace" ? "2" : ""

                    width: col.width
                    // s3 pad + match row + s2 gap + action row + s3 pad
                    height: Tokens.s3 * 2 + lineH * 2 + Tokens.s2
                    radius: Tokens.radius
                    color: rh.hovered ? Tokens.tint5 : "transparent"
                    border.width: Tokens.border
                    border.color: rh.hovered ? Tokens.lineStrong : Tokens.line
                    Behavior on color { ColorAnimation { duration: Tokens.snap } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                    HoverHandler { id: rh }

                    // ── match row: class field, title field, remove ──
                    Item {
                        id: matchRow
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            leftMargin: Tokens.s3; rightMargin: Tokens.s3; topMargin: Tokens.s3
                        }
                        height: rowRect.lineH

                        readonly property real fieldsW: width - rowRect.removeW - rowRect.gap * 2
                        readonly property real classW: Math.round(fieldsW * 0.42)

                        // class: a config match string, so mono (file-truth boundary).
                        Field {
                            id: classF
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: matchRow.classW
                            tabular: true
                            placeholder: I18n.tr("Match class (e.g. firefox)")
                            text: rowRect.modelData["class"] || ""
                            onCommitted: (v) => {
                                if (v !== (rowRect.modelData["class"] || ""))
                                    pg.patch(rowRect.index, "class", v);
                            }
                        }
                        // title: free-form window text, so grotesk.
                        Field {
                            id: titleF
                            anchors.left: classF.right
                            anchors.leftMargin: rowRect.gap
                            anchors.right: removeBtn.left
                            anchors.rightMargin: rowRect.gap
                            anchors.verticalCenter: parent.verticalCenter
                            placeholder: I18n.tr("Match title (e.g. Picture-in-Picture)")
                            text: rowRect.modelData.title || ""
                            onCommitted: (v) => {
                                if (v !== (rowRect.modelData.title || ""))
                                    pg.patch(rowRect.index, "title", v);
                            }
                        }
                        IconBtn {
                            id: removeBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            // a paired minus, not a trash icon: remove is not
                            // danger and there is no red on the sheet to carry one.
                            glyph: "\u2212"
                            onAct: pg.removeRule(rowRect.index)
                        }
                    }

                    // ── action row: the action catalogue + its optional value ──
                    Item {
                        id: actionRow
                        anchors {
                            left: parent.left; right: parent.right; top: matchRow.bottom
                            leftMargin: Tokens.s3; rightMargin: Tokens.s3; topMargin: Tokens.s2
                        }
                        height: rowRect.lineH

                        // the value control (one of three), pinned right. its
                        // width is whichever child is showing; the foot bar fills
                        // whatever is left.
                        Item {
                            id: valueBox
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: rowRect.lineH
                            visible: rowRect.hasValue
                            width: rowRect.textValue ? valField.width
                                : rowRect.idle ? segIdle.width
                                : rowRect.suppress ? segSup.width : 0

                            // free-form typed value (opacity/size/move/workspace),
                            // stored as a string exactly like the old page: no
                            // client-side clamp, the backend coerces on save.
                            Field {
                                id: valField
                                visible: rowRect.textValue
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 132
                                tabular: true
                                placeholder: rowRect.valueHint
                                text: rowRect.modelData.value || ""
                                onCommitted: (v) => {
                                    if (v !== (rowRect.modelData.value || ""))
                                        pg.patch(rowRect.index, "value", v);
                                }
                            }
                            // idleinhibit: 3 enumerated modes -> Seg.
                            Seg {
                                id: segIdle
                                visible: rowRect.idle
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                options: pg.labelsOf(pg.idleInhibitOptions)
                                current: pg.labelIn(pg.idleInhibitOptions,
                                    rowRect.modelData.value || pg.actionValueDefault("idleinhibit"))
                                onChose: (label) => pg.patch(rowRect.index, "value",
                                    pg.keyIn(pg.idleInhibitOptions, label))
                            }
                            // suppressevent: 4 enumerated modes -> Seg.
                            Seg {
                                id: segSup
                                visible: rowRect.suppress
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                options: pg.labelsOf(pg.suppressEventOptions)
                                current: pg.labelIn(pg.suppressEventOptions,
                                    rowRect.modelData.value || pg.actionValueDefault("suppressevent"))
                                onChose: (label) => pg.patch(rowRect.index, "value",
                                    pg.keyIn(pg.suppressEventOptions, label))
                            }
                        }

                        // 25 actions is a catalogue, never inline: the foot bar
                        // opens the shared Picker overlay.
                        PickBar {
                            id: actionBar
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: rowRect.hasValue ? valueBox.left : parent.right
                            anchors.rightMargin: rowRect.hasValue ? rowRect.gap : 0
                            value: pg.labelIn(pg.actionOptions, rowRect.act)
                            count: pg.actionOptions.length
                            onOpened: pg.openPicker(rowRect.index)
                        }
                    }
                }
            }
        }
    }

    // ── empty state, gated on load so it does not flash before data arrives ──
    Empty {
        anchors.centerIn: flick
        visible: pg.ready && pg.ruleRows.length === 0
        caption: I18n.tr("No custom rules yet. Add one to override how a specific window opens.")
    }

    // ── the action catalogue overlay (Picker), shared across rows ──
    MouseArea {
        id: scrim
        anchors.fill: parent
        visible: pg.pickerRow >= 0
        z: 100
        // a bare click-catcher: dismiss when the pointer lands outside the card.
        // no fill -- translucency is banned on app surfaces (DESIGN.md section 6).
        onClicked: pg.pickerRow = -1

        Picker {
            id: picker
            anchors.centerIn: parent
            title: I18n.tr("Action")
            options: pg.labelsOf(pg.actionOptions)
            current: {
                if (pg.pickerRow < 0)
                    return "";
                var r = (pg.ruleRows[pg.pickerRow] || ({})).action || "";
                return pg.labelIn(pg.actionOptions, r);
            }
            onChose: (label) => {
                pg.setAction(pg.pickerRow, pg.keyIn(pg.actionOptions, label));
                pg.pickerRow = -1;
            }
            onDismissed: pg.pickerRow = -1

            // absorb clicks inside the card so the scrim underneath does not
            // treat a header/padding tap as an outside dismiss.
            MouseArea { anchors.fill: parent; z: -1 }
        }
    }
}
