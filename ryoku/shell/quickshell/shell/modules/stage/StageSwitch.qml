import QtQuick
import shell.services

// A labelled on/off switch in Ryoku's grammar (docs/stage.md): the name, then a
// track that fills with the accent when on. Used for Depth and Parallax, in both
// the island's second row and the sidebar card, so the same idea reads the same
// everywhere. Dims, not hides, when it cannot be toggled yet.
Item {
    id: sw
    property string label: ""
    property bool checked: false
    property bool switchEnabled: true
    signal toggled()

    implicitWidth: row.implicitWidth
    implicitHeight: 38
    width: implicitWidth
    opacity: sw.switchEnabled ? 1 : 0.45

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sw.label
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 24
            radius: 12
            color: sw.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
            border.width: 1
            border.color: sw.checked ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Rectangle {
                width: 18
                height: 18
                radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? parent.width - width - 3 : 3
                color: sw.checked ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: sw.switchEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (sw.switchEnabled) sw.toggled()
    }
}
