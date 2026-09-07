pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../../components"

// A widget's edit frame (docs/stage.md, "Edit widgets"): a 1 px outline that
// follows the widget's live rect, the widget's name at its top-left, and two
// small buttons at its top-right (Settings and Remove). Selecting draws the
// frame stronger.
//
// The body is input-transparent: the outline Rectangle takes no mouse, and a
// TapHandler with the default DragThreshold policy takes only a passive grab,
// so a tap selects while a press or drag still falls through to the widget's
// own move grip underneath. Only the two buttons consume their presses.
Item {
    id: outline
    anchors.fill: parent

    property rect box: Qt.rect(0, 0, 0, 0)
    property string title: ""
    property bool selected: false
    property real radius: Theme.radiusWidget

    signal picked()
    signal settings()
    signal remove()

    visible: outline.box.width > 1 && outline.box.height > 1

    // The header (name + buttons) floats just above the frame's top edge, or
    // drops inside when the widget hugs the top of the screen.
    readonly property real headerY: outline.box.y > 40 ? outline.box.y - 34 : outline.box.y + 6

    // The 1 px frame following the widget's rect.
    Rectangle {
        id: frame
        x: outline.box.x
        y: outline.box.y
        width: outline.box.width
        height: outline.box.height
        radius: outline.radius
        color: "transparent"
        border.width: outline.selected ? 2 : 1
        border.color: outline.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.95)
            : hover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.55)
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        // Hover lights the border, and must reach the slot underneath too so its
        // resize bracket reveals: a HoverHandler monitors without consuming, and
        // the MouseArea below is press-only (hoverEnabled false) so hover falls
        // through to the slot.
        HoverHandler { id: hover }
        // Left-press selects, then forwards the press (accepted = false) so the
        // widget's own grip and resize bracket beneath the overlay still get it;
        // the right button is left untouched so the per-widget menu still opens.
        // A pointer handler that grabbed here would starve the grip of the drag,
        // which is the "can't move it" bug.
        MouseArea {
            id: bodyMa
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: false
            onPressed: mouse => { outline.picked(); mouse.accepted = false; }
        }
    }

    // Name chip, top-left.
    Rectangle {
        id: nameChip
        visible: outline.title.length > 0
        x: Math.round(outline.box.x)
        y: Math.round(outline.headerY)
        width: nameText.implicitWidth + 20
        height: 28
        radius: 8
        color: outline.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.95)
            : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.width: 1
        border.color: outline.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Text {
            id: nameText
            anchors.centerIn: parent
            text: outline.title
            color: outline.selected ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
    }

    // Settings + Remove, top-right, right-aligned to the frame.
    Row {
        id: buttons
        spacing: 6
        x: Math.round(outline.box.x + outline.box.width - width)
        y: Math.round(outline.headerY)
        FrameBtn { icon: "tune"; onAct: outline.settings() }
        FrameBtn { icon: "delete"; danger: true; onAct: outline.remove() }
    }

    // A small, quiet icon button with a legibility plate over the wallpaper.
    component FrameBtn: Rectangle {
        id: fb
        property string icon: ""
        property bool danger: false
        signal act()
        width: 28
        height: 28
        radius: 8
        color: fbMa.containsMouse
            ? (fb.danger ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.9)
                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.16))
            : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        MaterialIcon {
            anchors.centerIn: parent
            text: fb.icon
            font.pixelSize: 16
            color: (fb.danger && fbMa.containsMouse) ? Theme.onError : Theme.onSurface
        }
        MouseArea {
            id: fbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fb.act()
        }
    }
}
