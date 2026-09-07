pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Environment (DESIGN.md section 11, ADVANCED). Custom NAME=value pairs layered
// over the base Hyprland session. This is not a settings sheet: the one "key"
// (env) is an array of entries, so it is built bespoke as a list editor -- a
// section head, a scrolling column of Field/Field/remove rows, and an add
// affordance -- wired straight to the hub's hypr store. A session reads its env
// only at startup, so edits take full effect at next login; the head carries
// that caveat. The shell owns the rail, the side panel and the Save/Revert
// action bar; nothing here writes to disk. Every value is a Token.
Item {
    id: pg

    property var hub

    // the live env array from the draft: a list of { key, value } entries.
    readonly property var envRows: pg.hub ? (pg.hub.hyprVal("env") || []) : []
    // gated so the empty state does not flash before `hypr get` returns.
    readonly property bool ready: pg.hub ? pg.hub.hyprLoaded === true : false

    // hyprEdit swaps the whole array, so the Repeater rebinds and rebuilds the
    // delegate owning a focused field. rows therefore commit on editing-finished
    // only, and every helper hands hyprEdit a fresh slice rather than mutating
    // the live list.
    function patch(i, key, val) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("env") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i][key] = val;
        pg.hub.hyprEdit("env", a);
    }
    function removeRow(i) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("env") || []).slice();
        a.splice(i, 1);
        pg.hub.hyprEdit("env", a);
    }
    function addRow() {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("env") || []).slice();
        a.push({ "key": "", "value": "" });
        pg.hub.hyprEdit("env", a);
    }
    function clearAll() {
        if (pg.hub)
            pg.hub.hyprEdit("env", []);
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
                text: I18n.tr("SYSTEM"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Environment"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Environment variables for the Hyprland session, layered over the base. Add a NAME and value (e.g. MOZ_ENABLE_WAYLAND = 1); they take full effect at next login.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── section head: dot + VARIABLES + leader + count + clear all + add ──
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
                text: I18n.tr("VARIABLES"); color: Tokens.ink; font.family: Tokens.ui
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
                text: pg.envRows.length === 1 ? I18n.tr("%1 ENTRY").arg(pg.envRows.length) : I18n.tr("%1 ENTRIES").arg(pg.envRows.length)
                color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("CLEAR ALL")
                armed: pg.envRows.length > 0
                onAct: pg.clearAll()
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "+"
                onAct: pg.addRow()
            }
        }

        Rectangle {
            anchors.left: sectLabel.right; anchors.right: sectActions.left
            anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            height: 1; color: Tokens.lineSoft
        }
    }

    // ── the scrolling row list ──
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
                model: pg.envRows

                delegate: Item {
                    id: rowRect
                    required property int index
                    required property var modelData

                    readonly property real removeW: 26
                    readonly property real gap: Tokens.s2
                    readonly property real fieldsW: width - removeW - gap * 2
                    readonly property real keyW: Math.round(fieldsW * 0.42)

                    width: col.width
                    height: Tokens.rowH

                    // key: a config variable name, so mono (file-truth boundary).
                    Field {
                        id: keyField
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: rowRect.keyW
                        tabular: true
                        placeholder: I18n.tr("NAME (e.g. MOZ_ENABLE_WAYLAND)")
                        text: rowRect.modelData.key
                        onCommitted: (v) => {
                            if (v !== rowRect.modelData.key)
                                pg.patch(rowRect.index, "key", v);
                        }
                    }
                    Field {
                        id: valField
                        anchors.left: keyField.right
                        anchors.leftMargin: rowRect.gap
                        anchors.right: removeBtn.left
                        anchors.rightMargin: rowRect.gap
                        anchors.verticalCenter: parent.verticalCenter
                        tabular: true
                        placeholder: I18n.tr("value (e.g. 1)")
                        text: rowRect.modelData.value
                        onCommitted: (v) => {
                            if (v !== rowRect.modelData.value)
                                pg.patch(rowRect.index, "value", v);
                        }
                    }
                    IconBtn {
                        id: removeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        // a paired minus, not a trash icon: remove is not danger
                        // and there is no red on the sheet to carry one.
                        glyph: "\u2212"
                        onAct: pg.removeRow(rowRect.index)
                    }
                }
            }
        }
    }

    // ── empty state, gated on load so it does not flash before data arrives ──
    Empty {
        anchors.centerIn: flick
        visible: pg.ready && pg.envRows.length === 0
        caption: I18n.tr("No custom variables yet. Add one to get started.")
    }
}
