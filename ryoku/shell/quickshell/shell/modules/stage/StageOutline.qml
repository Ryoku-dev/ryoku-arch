pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// One thing's on-desktop selection affordance (docs/stage.md): a faint outline
// on hover, a solid accent outline when selected, and a small label chip naming
// it (and its state, e.g. "Clock · locked"). While the engine cuts the subject,
// a progress ring rides the outline. No controls live here; the selection's
// actions are in the island's second row and its panels.
//
// Selection rides a TapHandler with the default DragThreshold policy: it takes
// only a passive grab, so a tap selects while a drag still falls through to the
// thing's own move handler underneath.
Item {
    id: outline
    anchors.fill: parent

    property rect box: Qt.rect(0, 0, 0, 0)
    property string title: ""
    property bool selected: false
    property bool clickable: false
    // Cut progress 0..100 while > -1; draws a ring centred on the box.
    property int ringPercent: -1

    signal picked()

    visible: outline.box.width > 1 && outline.box.height > 1

    Rectangle {
        id: frame
        x: outline.box.x
        y: outline.box.y
        width: outline.box.width
        height: outline.box.height
        radius: Theme.radiusWidget
        color: outline.ringPercent >= 0 ? Qt.rgba(0, 0, 0, 0.28) : "transparent"
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

        // The cut progress ring, centred on the box.
        Canvas {
            id: ring
            anchors.centerIn: parent
            width: 54
            height: 54
            visible: outline.ringPercent >= 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2, r = width / 2 - 3;
                ctx.lineWidth = 3;
                ctx.strokeStyle = Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.25);
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.stroke();
                const frac = Math.max(0.04, Math.min(1, outline.ringPercent / 100));
                ctx.strokeStyle = Theme.primary;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
                ctx.stroke();
            }
            Connections {
                target: outline
                function onRingPercentChanged() { ring.requestPaint(); }
            }
            Component.onCompleted: ring.requestPaint()
        }
    }

    // The label chip, only while selected (or cutting): the name and its state.
    Rectangle {
        id: chip
        visible: (outline.selected || outline.ringPercent >= 0) && outline.title.length > 0
        x: Math.round(Math.max(8, Math.min(outline.width - width - 8,
            outline.box.x + outline.box.width / 2 - width / 2)))
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
