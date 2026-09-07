pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// A machine at a glance on the harbour plate: the OS mark, its name and a compact
// spec, a live state flap, and one or two verbs. Running brightens the name and
// lights the flap; the whole tile taps through to the yard.
Item {
    id: tile

    property string title: ""
    property string sub: ""
    property bool on: false
    property string slug: ""
    property string primaryLabel: ""
    property string secondaryLabel: ""
    signal tapped()
    signal primary()
    signal secondary()

    implicitHeight: 84

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: ma.containsMouse ? Tokens.tint5 : "transparent"
        border.width: Tokens.border
        border.color: ma.containsMouse ? Tokens.lineStrong : Tokens.line
        antialiasing: false
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.tapped()
        }

        // header: mark + name/sub + state flap
        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: Tokens.s3
            anchors.bottomMargin: 0
            height: 40

            OsIcon {
                id: mark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; size: 30
                slug: tile.slug
                label: tile.title
            }
            Column {
                anchors.left: mark.right
                anchors.leftMargin: Tokens.s3
                anchors.right: flap.left
                anchors.rightMargin: Tokens.s2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.title
                    color: tile.on ? Tokens.ink : Tokens.inkDim
                    font.family: Tokens.ui; font.pixelSize: 14
                    font.weight: tile.on ? Font.DemiBold : Font.Medium
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.sub
                    color: Tokens.inkFaint
                    font.family: Tokens.mono; font.pixelSize: 10
                }
            }
            FlapWord {
                id: flap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: tile.on ? I18n.tr("RUN") : I18n.tr("OFF")
                pad: 3
                cellW: 12; cellH: 18; fontPx: 10
                ink: tile.on ? Tokens.sun : Tokens.inkDim
            }
        }

        // verbs: reveal on hover so the resting tile stays quiet.
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.margins: Tokens.s3
            anchors.topMargin: 0
            height: 26
            spacing: Tokens.s2
            opacity: ma.containsMouse ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: Tokens.snap } }

            Btn {
                visible: tile.primaryLabel.length > 0
                compact: true
                text: tile.primaryLabel
                primary: tile.on === false
                onAct: tile.primary()
            }
            Btn {
                visible: tile.secondaryLabel.length > 0
                compact: true
                text: tile.secondaryLabel
                onAct: tile.secondary()
            }
        }
    }
}
