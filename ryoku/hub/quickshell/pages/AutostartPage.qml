pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Autostart (DESIGN.md section 11, ADVANCED). Commands Hyprland runs once at
// login, layered over the fixed Ryoku autostart. Like Environment, the one
// "key" (autostart) is an array of entries, so it is a bespoke list editor --
// a section head, a scrolling column of Field/remove rows and an add
// affordance -- not a settings sheet. Each element is an object { command }.
// The shell owns the rail, the side panel and the Save/Revert/Reset action bar;
// this list lands only via Save (settings.lua regen + reload), it is never
// previewed live, and a session reads its autostart only at login, so new
// commands take effect at the next login; the head carries that caveat. Every
// value is a Token.
Item {
    id: pg

    property var hub

    // the live autostart array from the draft: a list of { command } entries.
    readonly property var cmdRows: pg.hub ? (pg.hub.hyprVal("autostart") || []) : []
    // gated so the empty state does not flash before `hypr get` returns.
    readonly property bool ready: pg.hub ? pg.hub.hyprLoaded === true : false

    // hyprEdit swaps the whole array, so the Repeater rebinds and rebuilds the
    // delegate owning a focused field. rows therefore commit on editing-finished
    // only, and every helper hands hyprEdit a fresh slice rather than mutating
    // the live list.
    function patch(i, val) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("autostart") || []).slice();
        a[i] = Object.assign({}, a[i]);
        a[i].command = val;
        pg.hub.hyprEdit("autostart", a);
    }
    function removeRow(i) {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("autostart") || []).slice();
        a.splice(i, 1);
        pg.hub.hyprEdit("autostart", a);
    }
    function addRow() {
        if (!pg.hub)
            return;
        var a = (pg.hub.hyprVal("autostart") || []).slice();
        a.push({ "command": "" });
        pg.hub.hyprEdit("autostart", a);
    }
    function clearAll() {
        if (pg.hub)
            pg.hub.hyprEdit("autostart", []);
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
            text: I18n.tr("Autostart"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Commands Hyprland runs once at login, after the base Ryoku autostart (e.g. a tray applet or a sync client). Saved to your config; new commands start at your next login.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── section head: dot + COMMANDS + leader + count + clear all + add ──
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
                text: I18n.tr("COMMANDS"); color: Tokens.ink; font.family: Tokens.ui
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
                text: pg.cmdRows.length === 1 ? I18n.tr("%1 ENTRY").arg(pg.cmdRows.length) : I18n.tr("%1 ENTRIES").arg(pg.cmdRows.length)
                color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("CLEAR ALL")
                armed: pg.cmdRows.length > 0
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
                model: pg.cmdRows

                delegate: Item {
                    id: rowRect
                    required property int index
                    required property var modelData

                    readonly property real removeW: 26
                    readonly property real gap: Tokens.s2

                    width: col.width
                    height: Tokens.rowH

                    // a command is a config literal run by the shell, so mono
                    // (the file-truth boundary, DESIGN.md section 2).
                    Field {
                        id: cmdField
                        anchors.left: parent.left
                        anchors.right: removeBtn.left
                        anchors.rightMargin: rowRect.gap
                        anchors.verticalCenter: parent.verticalCenter
                        tabular: true
                        placeholder: I18n.tr("command to run (e.g. nm-applet)")
                        text: rowRect.modelData.command
                        onCommitted: (v) => {
                            if (v !== rowRect.modelData.command)
                                pg.patch(rowRect.index, v);
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
        visible: pg.ready && pg.cmdRows.length === 0
        caption: I18n.tr("No autostart commands yet. Add one to get started.")
    }
}
