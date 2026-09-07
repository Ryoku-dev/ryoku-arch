pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../Singletons"
import Ryoku.Ui.Singletons

// The lyric sheet: the song's words scrolling under the line being sung. The
// timing comes from the daemon (Music), so this only places lines and follows the
// index: the sung line is lit in the sleeve's colour and set larger, its
// neighbours fade out with distance, and the column glides so that line stays on
// the middle rule.
//
// The active line grows by font size, never by Item.scale, which would blur the
// text (modules/desktop/README.md).
Item {
    id: sheet

    property real s: 1
    property color ink: Theme.ink
    property color dim: Theme.faint
    property color accent: Theme.accent
    property int base: 15
    property int lift: 2
    property int falloff: 4

    readonly property var lines: Music.lines
    readonly property int index: Music.index
    readonly property bool synced: Music.synced
    readonly property bool unsynced: Music.unsynced
    readonly property bool empty: !sheet.synced && !sheet.unsynced

    clip: true

    // Nothing to follow: say which of the three cases it is, so a missing sheet
    // reads as an answer rather than a blank panel.
    Text {
        anchors.centerIn: parent
        width: parent.width
        visible: sheet.empty
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Music.searching ? I18n.tr("Looking for lyrics")
            : Music.status === "error" ? I18n.tr("Lyrics unavailable")
            : I18n.tr("No lyrics for this track")
        color: sheet.dim
        font.family: Theme.font
        font.pixelSize: sheet.base * sheet.s
    }

    // Synced: the following column.
    Item {
        id: viewport
        anchors.fill: parent
        visible: sheet.synced

        Column {
            id: column
            width: viewport.width
            spacing: 6 * sheet.s

            // the sung line's centre, pulled onto the viewport's middle rule.
            readonly property real target: {
                const count = rows.count;
                if (count === 0)
                    return 0;
                const row = rows.itemAt(Math.max(0, Math.min(sheet.index, count - 1)));
                if (!row)
                    return 0;
                return Math.round(viewport.height / 2 - (row.y + row.height / 2));
            }
            y: column.target

            Behavior on y {
                NumberAnimation { duration: Theme.slow; easing.type: Theme.ease }
            }

            Repeater {
                id: rows
                model: sheet.lines

                delegate: Text {
                    id: line
                    required property int index
                    required property var modelData

                    readonly property int distance: Math.abs(line.index - sheet.index)
                    readonly property bool sung: line.index === sheet.index

                    width: column.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    // an instrumental break keeps its slot, so the sheet holds
                    // the pause instead of jumping over it.
                    text: (line.modelData.text && line.modelData.text.length > 0)
                        ? line.modelData.text : "\u266a"
                    color: line.sung ? sheet.accent : sheet.ink
                    font.family: Theme.font
                    font.pixelSize: (sheet.base + (line.sung ? sheet.lift : 0)) * sheet.s
                    font.weight: line.sung ? Font.DemiBold : Font.Medium
                    opacity: line.distance === 0 ? 1
                        : line.distance > sheet.falloff ? 0
                        : Math.max(0.10, 0.52 - (line.distance - 1) * 0.14)

                    Behavior on opacity { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
                    Behavior on color { ColorAnimation { duration: Theme.medium } }
                }
            }
        }
    }

    // Unsynced: the words exist but carry no timestamps, so they are shown as a
    // still sheet rather than pretending to follow.
    Column {
        anchors.fill: parent
        visible: sheet.unsynced
        spacing: 4 * sheet.s

        Repeater {
            model: sheet.unsynced ? Music.plain : []
            delegate: Text {
                required property var modelData
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                text: modelData
                color: sheet.ink
                opacity: 0.62
                font.family: Theme.font
                font.pixelSize: sheet.base * sheet.s
            }
        }
    }
}
