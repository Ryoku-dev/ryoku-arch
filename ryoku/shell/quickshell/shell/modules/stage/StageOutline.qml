pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// One element's on-desktop selection affordance (docs/stage.md): a faint outline
// on hover, a solid outline when selected, and -- only when selected -- one small
// label chip carrying the element's name. No controls live here; the selected
// element's actions are in its inspector tab. A full-screen overlay positioned
// from the element's on-screen `box`, so the chip is placed even past a small
// element's edge.
//
// Selection rides a TapHandler with the default DragThreshold policy: it only
// takes a passive grab, so a tap selects the element while a drag still falls
// through to the widget's own move handler underneath -- and a layer under the
// subject never blocks the widget it overlaps.
Item {
    id: outline
    anchors.fill: parent

    property rect box: Qt.rect(0, 0, 0, 0)
    property string title: ""
    property bool selected: false
    property bool clickable: false

    signal picked()

    visible: outline.box.width > 1 && outline.box.height > 1

    // The outline itself, sized to the element's box; carries hover + selection.
    Rectangle {
        id: frame
        x: outline.box.x
        y: outline.box.y
        width: outline.box.width
        height: outline.box.height
        radius: Theme.radiusWidget
        color: "transparent"
        border.width: outline.selected ? 2 : 1
        border.color: outline.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
            : hover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.0)
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        HoverHandler { id: hover; enabled: outline.clickable }
        TapHandler {
            enabled: outline.clickable
            onTapped: outline.picked()
        }
    }

    // The one label chip, only while selected.
    Rectangle {
        id: chip
        visible: outline.selected && outline.title.length > 0
        x: Math.round(Math.max(8, Math.min(outline.width - width - 8, outline.box.x + outline.box.width / 2 - width / 2)))
        y: Math.round(outline.box.y > 40 ? outline.box.y - height - 6 : outline.box.y + outline.box.height + 6)
        width: label.implicitWidth + 22
        height: 28
        radius: 14
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.92)
        Text {
            id: label
            anchors.centerIn: parent
            text: outline.title
            color: Theme.inkOn(Theme.primary, Theme.onPrimary)
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
    }
}
