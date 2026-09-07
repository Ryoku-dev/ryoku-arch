pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// Step 1 body: the warm opening. A short editorial paragraph, then three value
// ticks -- hairline ink marks, no accent; the sun stays with the mark and the
// art. The header (eyebrow + title + subtitle) is drawn by Welcome.qml; this is
// only the body.
Column {
    id: step
    spacing: 22

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: I18n.tr("You've arrived. %1 is a single, hand-built desktop - one bar, one launcher, one control plane - carved on Arch and Hyprland. This is a two-minute tour of where things live and how to make it yours.").arg(Theme.brandName)
        color: Tokens.inkDim
        font.family: Tokens.ui
        font.pixelSize: Tokens.fRow
        lineHeight: 1.35
    }

    Column {
        width: parent.width
        spacing: 13

        Repeater {
            model: [
                I18n.tr("One shell, one look - the bar, panels, and launcher all speak the same language."),
                I18n.tr("Your colours follow your wallpaper, automatically."),
                I18n.tr("Every choice lives in Ryoku Settings, a keystroke away.")
            ]

            delegate: Row {
                id: tick
                required property string modelData
                width: step.width
                spacing: 12

                Rectangle {
                    width: 16
                    height: 1
                    color: Tokens.lineStrong
                    anchors.verticalCenter: label.verticalCenter
                }

                Text {
                    id: label
                    width: tick.width - 28
                    wrapMode: Text.WordWrap
                    text: tick.modelData
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    lineHeight: 1.3
                }
            }
        }
    }
}
