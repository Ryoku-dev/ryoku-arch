pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

// The cheatsheet card. Editorial masthead (ink rule, kanji seal, Fraunces title,
// marginalia), a quiet search field, then a two-pane body: a category rail on
// the left and, on the right, one category at a time laid out with air. Showing
// a single group at rest keeps the sheet calm; search spans every bind and shows
// the matches grouped. Monochrome -- emphasis is type and space, never accent.
// Read-only.
Item {
    id: sheet

    property var categories: []
    property bool loaded: false
    property real appear: 1
    signal requestClose()

    property string query: ""
    property int selected: 0

    function countBinds(cats) {
        var n = 0;
        for (var i = 0; i < cats.length; i++)
            n += cats[i].binds.length;
        return n;
    }
    readonly property int total: sheet.countBinds(sheet.categories)

    function matchBind(b, q) {
        if (b.desc && b.desc.toLowerCase().indexOf(q) >= 0)
            return true;
        var ks = b.keys ? b.keys.join(" ").toLowerCase() : "";
        return ks.indexOf(q) >= 0;
    }
    function catMatches(c, q) {
        if (!q || c.name.toLowerCase().indexOf(q) >= 0)
            return c.binds.length;
        var n = 0;
        for (var j = 0; j < c.binds.length; j++)
            if (sheet.matchBind(c.binds[j], q))
                n++;
        return n;
    }

    // Search results: every category with at least one match, a category-name
    // hit keeping the whole group.
    readonly property var filtered: {
        var q = sheet.query.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < sheet.categories.length; i++) {
            var c = sheet.categories[i];
            var binds = c.binds || [];
            if (!q || c.name.toLowerCase().indexOf(q) >= 0) {
                out.push(c);
                continue;
            }
            var keep = [];
            for (var j = 0; j < binds.length; j++)
                if (sheet.matchBind(binds[j], q))
                    keep.push(binds[j]);
            if (keep.length)
                out.push({ name: c.name, binds: keep });
        }
        return out;
    }

    readonly property bool searching: sheet.query.trim().length > 0

    // What the right pane shows: the search results while searching, else just
    // the selected category.
    readonly property var shownCats: {
        if (sheet.searching)
            return sheet.filtered;
        if (sheet.categories.length === 0)
            return [];
        var i = Math.max(0, Math.min(sheet.selected, sheet.categories.length - 1));
        return [sheet.categories[i]];
    }
    onShownCatsChanged: body.contentY = 0

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1040, parent.width - 2 * Tokens.s7)
        height: Math.min(parent.height - 2 * Tokens.s6, 760)
        radius: Tokens.radius * 1.5
        color: Tokens.paperLift
        border.width: Tokens.border
        border.color: Tokens.line
        opacity: sheet.appear
        scale: 0.98 + 0.02 * sheet.appear

        readonly property int pad: Tokens.s6

        MouseArea { anchors.fill: parent }

        // ── masthead ──
        Column {
            id: head
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: card.pad
            anchors.leftMargin: card.pad
            spacing: Tokens.s2

            Row {
                spacing: Tokens.s2
                Rectangle {
                    width: 16; height: 1; color: Tokens.ink
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "\u529b"; color: Tokens.ink
                    font.family: Tokens.jp; font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: I18n.tr("CHEATSHEET"); color: Tokens.inkMuted
                    font.family: Tokens.ui; font.pixelSize: 9
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: I18n.tr("Keyboard shortcuts"); color: Tokens.ink
                font.family: Tokens.display; font.pixelSize: Tokens.fTitle
            }
        }

        Marginalia {
            // sit just left of the close control, vertically centred on it, so the
            // trailing torii + chevrons never ride under the X (Marginalia dresses a
            // margin "without crowding a control").
            anchors.right: closeBtn.left
            anchors.rightMargin: Tokens.s3
            anchors.verticalCenter: closeBtn.verticalCenter
            kana: "\u8fd1\u9053"
            index: sheet.total > 0 ? ("" + sheet.total) : ""
            label: I18n.tr("SHORTCUTS")
            glyph: "meander"
            glyph2: "torii"
        }

        Rectangle {
            id: closeBtn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: card.pad
            anchors.rightMargin: card.pad
            width: 30; height: 30
            radius: Tokens.radius
            color: closeHover.hovered ? Tokens.tint10 : "transparent"
            border.width: Tokens.border
            border.color: closeHover.hovered ? Tokens.lineStrong : Tokens.line
            Behavior on color { ColorAnimation { duration: Tokens.snap } }
            Text {
                anchors.centerIn: parent; text: "\u2715"; color: Tokens.inkDim
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
            }
            HoverHandler { id: closeHover }
            TapHandler { onTapped: sheet.requestClose() }
        }

        // ── search ──
        Rectangle {
            id: search
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Tokens.s5
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            height: 44
            radius: Tokens.radius
            color: Tokens.paper
            border.width: Tokens.border
            border.color: input.activeFocus ? Tokens.lineStrong : Tokens.line
            Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

            Text {
                id: glyph
                anchors.left: parent.left
                anchors.leftMargin: Tokens.s4
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: input.activeFocus ? Tokens.inkDim : Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: Tokens.fSmall
                Behavior on color { ColorAnimation { duration: Tokens.snap } }
            }
            TextInput {
                id: input
                anchors.left: glyph.right
                anchors.leftMargin: Tokens.s3
                anchors.right: parent.right
                anchors.rightMargin: Tokens.s4
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Tokens.ink
                font.family: Tokens.ui; font.pixelSize: Tokens.fBody
                selectionColor: Tokens.lineStrong
                selectedTextColor: Tokens.ink
                onTextChanged: sheet.query = text
                Keys.onEscapePressed: {
                    if (text.length)
                        text = "";
                    else
                        sheet.requestClose();
                }
                Component.onCompleted: input.forceActiveFocus()
            }
            Text {
                anchors.left: input.left
                anchors.verticalCenter: input.verticalCenter
                visible: input.text.length === 0
                text: I18n.tr("Search every shortcut")
                color: Tokens.inkFaint
                font: input.font
            }
        }

        // ── body: category rail | single-category pane ──
        Item {
            id: bodyRow
            anchors.top: search.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.topMargin: Tokens.s5
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            anchors.bottomMargin: Tokens.s3

            readonly property int railW: 232

            // rail
            Column {
                id: rail
                width: bodyRow.railW
                anchors.top: parent.top
                anchors.left: parent.left
                spacing: 2

                Repeater {
                    model: sheet.categories
                    delegate: Rectangle {
                        id: railItem
                        required property var modelData
                        required property int index
                        width: rail.width
                        height: 34
                        radius: Tokens.radius
                        readonly property bool active: !sheet.searching && sheet.selected === index
                        readonly property int mc: sheet.catMatches(modelData, sheet.query.trim().toLowerCase())
                        readonly property bool dimmed: sheet.searching && mc === 0
                        color: railItem.active ? Tokens.tint10
                             : (railHover.hovered ? Tokens.tint5 : "transparent")
                        Behavior on color { ColorAnimation { duration: Tokens.snap } }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2; height: parent.height - Tokens.s4
                            radius: 1
                            color: Tokens.ink
                            visible: railItem.active
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Tokens.s4
                            anchors.right: cnt.left
                            anchors.rightMargin: Tokens.s2
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr(railItem.modelData.name)
                            color: railItem.active ? Tokens.ink
                                 : (railItem.dimmed ? Tokens.inkFaint : Tokens.inkDim)
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            elide: Text.ElideRight
                        }
                        Text {
                            id: cnt
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            text: sheet.searching ? ("" + railItem.mc) : ("" + railItem.modelData.binds.length)
                            color: Tokens.inkFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fMicro
                        }
                        HoverHandler { id: railHover }
                        TapHandler {
                            onTapped: {
                                input.text = "";
                                sheet.selected = railItem.index;
                            }
                        }
                    }
                }
            }

            // divider
            Rectangle {
                anchors.left: rail.right
                anchors.leftMargin: Tokens.s5
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Tokens.lineSoft
            }

            // pane
            Flickable {
                id: body
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: rail.right
                anchors.right: parent.right
                anchors.leftMargin: Tokens.s5 + Tokens.s6
                clip: true
                contentHeight: paneCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: paneCol
                    width: body.width
                    spacing: Tokens.s6

                    Repeater {
                        model: sheet.shownCats
                        delegate: CategoryBlock {
                            required property var modelData
                            width: paneCol.width
                            name: modelData.name
                            binds: modelData.binds
                        }
                    }
                }
            }

            // empty state
            Text {
                anchors.centerIn: body
                visible: sheet.loaded && sheet.shownCats.length === 0
                text: I18n.tr("No shortcuts match \u201c%1\u201d").arg(sheet.query.trim())
                color: Tokens.inkFaint
                font.family: Tokens.ui; font.pixelSize: Tokens.fBody
            }
        }

        // ── footer ──
        Text {
            id: footer
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Tokens.s4
            text: I18n.tr("Type to search") + "   \u00b7   " + I18n.tr("Esc to close")
            color: Tokens.inkFaint
            font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackLabel
        }
    }
}
