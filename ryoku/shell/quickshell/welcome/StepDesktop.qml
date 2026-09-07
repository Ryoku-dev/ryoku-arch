pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// Step 3 body: where the desktop's surfaces live and how to reach them. Four
// flat plates -- a hairline on the paper scrim, near-square, no shadow (print
// does not cast) -- each naming a surface, how to summon it, and what it holds.
Grid {
    id: step
    columns: 2
    columnSpacing: 14
    rowSpacing: 14

    readonly property real cardW: (width - columnSpacing) / 2

    Repeater {
        model: [
            { "name": I18n.tr("The bar"),       "reach": I18n.tr("Screen edges"), "desc": I18n.tr("Frame bars carry the launcher, workspaces, clock, tray and status.") },
            { "name": I18n.tr("The launcher"),  "reach": "Super + Space", "desc": I18n.tr("Search apps, run commands, or ask a quick question.") },
            { "name": I18n.tr("The frame"),     "reach": I18n.tr("Screen edge"),   "desc": I18n.tr("The rounded border holds the power and service surfaces.") },
            { "name": I18n.tr("Ryoku Settings"),"reach": "Super + ,",     "desc": I18n.tr("Displays, appearance, keybinds, the shell - every knob in one place.") }
        ]

        delegate: Rectangle {
            id: card
            required property var modelData
            width: step.cardW
            height: 132
            color: Theme.panel
            radius: Tokens.radius
            border.width: Tokens.border
            border.color: hov.hovered ? Tokens.lineStrong : Tokens.line
            Behavior on border.color { ColorAnimation { duration: Motion.snap } }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: card.modelData.name
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }

                // the summon combo is literal input, so it keeps the mono voice.
                Row {
                    spacing: 8
                    Rectangle { width: 14; height: 1; color: Tokens.lineStrong; anchors.verticalCenter: reach.verticalCenter }
                    Text {
                        id: reach
                        text: card.modelData.reach
                        color: Tokens.inkDim
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        font.letterSpacing: Tokens.trackLabel
                        font.capitalization: Font.AllUppercase
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: card.modelData.desc
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    lineHeight: 1.25
                }
            }

            HoverHandler { id: hov }
        }
    }
}
