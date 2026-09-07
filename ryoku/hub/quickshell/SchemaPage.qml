pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "ReloadCoverModel.js" as ReloadCoverModel

// Every settings page, once. A page supplies its schema, its draft and its
// defaults; this draws the tabs its schema declares and hands the rows to a
// SettingsSheet. There is no per-page layout to write, which is the point:
// 30 pages that differ only in data should not be 30 files that differ in
// code.
//
// Surfaces that are not settings (a preview, a console, a drag-arrange) do not
// belong in a cell and are not forced into one: a page passes them in as
// `extras` and they sit full width inside the sheet's grid.
Item {
    id: page

    property var schema: []
    property var draft: null
    property var defaults: ({})
    property string title: ""
    property string eyebrow: I18n.tr("DESKTOP")
    property string blurb: ""
    property string query: ""
    property alias tab: sheet.tab
    property alias advanced: sheet.advanced
    default property alias extras: extraSlot.data
    property var pendingImageRow: null
    property string externalReloadCoverError: ""
    property string importReloadCoverError: ""
    property var pendingReloadCoverRow: null
    property bool reloadCoverImportBusy: false
    property int reloadCoverImportGeneration: 0

    signal edited(string key, var value)
    signal pickRequested(var row)

    function invalidateReloadCoverImport() {
        reloadCoverImportGeneration++;
        pendingReloadCoverRow = null;
    }
    signal timezonePickRequested(var row)

    // a search jump forwards here; the sheet switches tab, scrolls, and flashes.
    function focusKey(k) { sheet.focusKey(k) }

    readonly property var tabs: {
        var t = [];
        for (var i = 0; i < schema.length; i++) {
            var x = schema[i].tab;
            if (x && t.indexOf(x) < 0) t.push(x);
        }
        return t;
    }

    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Tokens.s2

        Item {
            width: parent.width
            height: 14
            Row {
                id: ebrow
                spacing: Tokens.s2
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { width: 16; height: 1; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "力"; color: Tokens.ink; font.family: Tokens.jp
                    font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: I18n.tr(page.eyebrow); color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            // the band runs to the page edge and closes with the sheet's marks:
            // a register cross and the /// cluster, per the reference poster.
            Rectangle {
                anchors { left: ebrow.right; right: crossMark.left; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
                height: 1; color: Tokens.lineSoft
            }
            Text {
                visible: Tokens.showGrid
                id: crossMark
                anchors { right: slashMark.left; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                text: "+"; color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: 10
            }
            Text {
                visible: Tokens.showGrid
                id: slashMark
                // clear the shared top-right FILES/UPDATES chips so the register
                // marks never ride under them.
                anchors { right: parent.right; rightMargin: 150; verticalCenter: parent.verticalCenter }
                text: "///"; color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: 10
            }
        }
        Text {
            text: page.title
            color: Tokens.ink
            font.family: Tokens.display
            font.pixelSize: Tokens.fTitle
        }
        Text {
            visible: page.blurb !== ""
            width: Math.min(parent.width, 720)
            text: I18n.tr(page.blurb)
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fBody
            wrapMode: Text.WordWrap
        }
        Item { width: 1; height: Tokens.s1 }

        // a page with one tab does not need a tab bar
        Tabs {
            visible: page.tabs.length > 1
            options: page.tabs
            current: sheet.tab
            onChose: (label) => sheet.tab = label
        }
    }

    Item {
        id: extraSlot
        anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: childrenRect.height > 0 ? Tokens.s4 : 0 }
        height: childrenRect.height
        visible: children.length > 0
    }

    SettingsSheet {
        id: sheet
        anchors {
            left: parent.left; right: parent.right
            top: extraSlot.visible ? extraSlot.bottom : head.bottom
            bottom: parent.bottom
            topMargin: Tokens.s5
        }
        schema: page.schema
        draft: page.draft
        defaults: page.defaults
        query: page.query
        tab: page.tabs.length ? page.tabs[0] : ""
        onEdited: (k, v) => page.edited(k, v)
        onPickRequested: (r) => page.pickRequested(r)
        reloadCoverError: page.importReloadCoverError || page.externalReloadCoverError
        reloadCoverImportBusy: page.reloadCoverImportBusy
        onReloadCoverPickRequested: (r) => {
            if (page.reloadCoverImportBusy) return;
            page.importReloadCoverError = "";
            page.pendingReloadCoverRow = r;
            reloadCoverPick.open();
        }
        onReloadCoverDefaultRequested: (r) => {
            page.invalidateReloadCoverImport();
            page.importReloadCoverError = "";
            page.edited(r.key, ReloadCoverModel.empty());
        }
        onImagePickRequested: (r) => { page.pendingImageRow = r; imgPick.open(); }
        onTimezonePickRequested: (r) => page.timezonePickRequested(r)
    }

    // the image-mark picker: an `image` control asks for it (SettingsSheet emits
    // imagePickRequested); the chosen path lands on the row's key like any edit.
    // full-page overlay so it covers the tabs, not just the sheet.
    PickFile {
        id: imgPick
        title: I18n.tr("Choose an image")
        onPicked: (p) => {
            if (page.pendingImageRow) page.edited(page.pendingImageRow.key, ("" + p).replace("file://", ""));
            imgPick.active = false;
        }
        onCanceled: imgPick.active = false
    }

    PickFile {
        id: reloadCoverPick
        title: I18n.tr("Add reload-cover asset")
        emptyText: I18n.tr("No supported media or folders here")
        fileFilters: ReloadCoverModel.filters()
        onPicked: (p) => {
            reloadCoverPick.active = false;
            if (page.reloadCoverImportBusy || !page.pendingReloadCoverRow) return;
            page.reloadCoverImportGeneration++;
            reloadCoverImport.requestGeneration = page.reloadCoverImportGeneration;
            reloadCoverImport.command = ["ryoku-hub", "reload-cover", "import", "" + p];
            page.reloadCoverImportBusy = true;
            reloadCoverImport.running = true;
        }
        onCanceled: {
            reloadCoverPick.active = false;
            if (!page.reloadCoverImportBusy)
                page.pendingReloadCoverRow = null;
        }
    }

    Process {
        id: reloadCoverImport
        property int requestGeneration: 0
        running: false
        stdout: StdioCollector { id: reloadCoverImportOut }
        stderr: StdioCollector { id: reloadCoverImportErr }
        onExited: function(code) {
            var isCurrent = requestGeneration === page.reloadCoverImportGeneration;
            page.reloadCoverImportBusy = false;
            if (!isCurrent) return;

            var row = page.pendingReloadCoverRow;
            if (code === 0) {
                try {
                    var descriptor = ReloadCoverModel.normalize(JSON.parse(reloadCoverImportOut.text.trim()));
                    if (descriptor.path === "")
                        throw new Error("missing managed path");
                    if (row)
                        page.edited(row.key, descriptor);
                    page.importReloadCoverError = "";
                } catch (e) {
                    page.importReloadCoverError = I18n.tr("Couldn't import this asset. Choose a supported local file under 64 MiB.");
                }
            } else {
                page.importReloadCoverError = reloadCoverImportErr.text.trim()
                    || I18n.tr("Couldn't import this asset. Choose a supported local file under 64 MiB.");
            }
            page.pendingReloadCoverRow = null;
        }
    }
}
