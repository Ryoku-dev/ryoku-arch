pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

// A plain-QML preview of the notes scratch pad for the Desktop Widgets section:
// a faint plate with a few sample lines of jotted text. Static -- no FileView,
// no editing -- and drawn at the pad's native 260x180 so the page scales it to
// fit the card.
Item {
    id: root

    implicitWidth: 260
    implicitHeight: 180

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b, 0.06)
        border.width: 1
        border.color: Tokens.lineSoft
    }

    Column {
        anchors { fill: parent; margins: 16 }
        spacing: 8

        Text {
            text: I18n.tr("Groceries: oat milk, chili oil")
            color: Tokens.ink
            font.family: Tokens.ui; font.pixelSize: 13
        }
        Text {
            text: I18n.tr("Call the framer back")
            color: Tokens.ink
            font.family: Tokens.ui; font.pixelSize: 13
        }
        Text {
            text: I18n.tr("Ryoku wallpaper ideas \u2014 dusk")
            color: Tokens.inkMuted
            font.family: Tokens.ui; font.pixelSize: 13
        }
        Text {
            text: "\u2026"
            color: Tokens.inkFaint
            font.family: Tokens.ui; font.pixelSize: 13
        }
    }
}
