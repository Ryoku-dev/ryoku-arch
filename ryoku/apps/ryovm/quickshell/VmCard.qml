import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"

// One machine in the yard: a 64-tall row, hairline frame, transparent fill:
// the departure-board row for this machine. The OS mark, the name (ink when
// running, inkDim when stopped), a compact mono spec line, and the state on its
// own split-flap drum, registered like a board column. Selected wears the
// gallery grammar: tint10 fill, 1px ink border, corner dot. No signal rail, no
// border colour; running just brightens the name and flips the flap to RUN.
Item {
    id: card

    property var item
    property bool active: false
    signal picked()

    readonly property bool running: card.item ? card.item.running === true : false

    height: 64

    function specLine(it) {
        var c = it.cores === "auto" ? I18n.tr("auto") : it.cores + "c";
        var m = ({ "gtk": I18n.tr("window"), "spice": I18n.tr("spice"), "none": I18n.tr("headless") })[it.display] || it.display;
        var d = it.diskUsed > 0 ? Vm.human(it.diskUsed) : "-";
        return c + " · " + it.ram + " · " + m + " · " + d;
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Tokens.radius
        color: card.active ? Tokens.tint10 : (ma.containsMouse ? Tokens.tint5 : "transparent")
        border.width: Tokens.border
        border.color: card.active ? Tokens.ink : (ma.containsMouse ? Tokens.lineStrong : Tokens.line)
        antialiasing: false
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

        // OS mark on a hairline tile (keeps its chroma: it is data).
        Item {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 40
            OsIcon {
                anchors.centerIn: parent
                width: 26; height: 26; size: 26
                slug: card.item ? (card.item.os || "") : ""
                label: card.item ? (card.item.name || card.item.os || "") : ""
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 13
            anchors.right: stateFlap.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: card.item ? card.item.name : ""
                color: card.running ? Tokens.ink : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: 14
                font.weight: card.running ? Font.DemiBold : Font.Medium
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: card.item ? card.specLine(card.item) : ""
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: 11
            }
        }

        // the state on its own split-flap drum, registered like a board column.
        FlapWord {
            id: stateFlap
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: card.running ? I18n.tr("RUN") : I18n.tr("OFF")
            pad: 3
            cellW: 13; cellH: 20; fontPx: 11
            ink: card.running ? Tokens.sun : Tokens.inkDim
        }

        // the gallery grammar's corner dot on the selected row.
        Rectangle {
            visible: card.active
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            width: 5; height: 5
            radius: 2.5
            color: Tokens.ink
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.picked()
        }
    }
}
