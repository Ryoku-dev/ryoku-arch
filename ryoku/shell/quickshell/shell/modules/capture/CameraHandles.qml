pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../components"
import Ryoku.Ui.Singletons

// Visual edit-handle indicators for the camera bubble. The drag logic lives in
// CameraOverlay's single DragHandler, which moves / resizes / rounds by press
// zone -- so these are pure visuals (no competing handlers) plus one flip tap.
// A roundness dot (top-left, at `rad` along the diagonal), a resize grip
// (bottom-right, kept inside the input mask), a flip toggle (top-right), and
// readouts driven by the current drag `mode`. Revealed on hover, hidden while
// recording so they are never in the shot.
Item {
    id: handles

    // "" | "move" | "resize" | "round" -- set by the overlay, drives the readouts.
    property string mode: ""

    // Per-monitor UI scale, threaded from the CameraOverlay (default 1 = no-op).
    property real us: 1

    readonly property real maxRad: Math.min(width, height) / 2
    readonly property real rad: Camera.roundness * handles.maxRad

    // roundness dot (top-left, sits `rad` in along the diagonal)
    Rectangle {
        width: 14 * handles.us
        height: 14 * handles.us
        radius: width / 2
        x: handles.rad - width / 2
        y: handles.rad - height / 2
        color: Theme.onSurface
        border.width: 2 * handles.us
        border.color: Theme.primary
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
    }
    Rectangle { // "Radius N" readout
        visible: handles.mode === "round"
        x: handles.rad + 12 * handles.us
        y: handles.rad - height / 2
        width: rL.implicitWidth + 12 * handles.us
        height: rL.implicitHeight + 8 * handles.us
        radius: 5 * handles.us
        color: Qt.rgba(0, 0, 0, 0.72)
        Text {
            id: rL
            anchors.centerIn: parent
            text: I18n.tr("Radius %1").arg(Math.round(handles.rad))
            color: Theme.onSurface
            font.family: Theme.mono
            font.pixelSize: 11 * handles.us
            font.weight: Font.DemiBold
        }
    }

    // resize grip (bottom-right, inset so it stays inside the bubble input mask)
    Rectangle {
        width: 16 * handles.us
        height: 16 * handles.us
        radius: 3 * handles.us
        x: handles.width - width - 5 * handles.us
        y: handles.height - height - 5 * handles.us
        color: Theme.onSurface
        border.width: 2 * handles.us
        border.color: Theme.primary
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
    }
    Rectangle { // "W x H" readout
        visible: handles.mode === "resize"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 28 * handles.us
        anchors.bottomMargin: 6 * handles.us
        width: sL.implicitWidth + 12 * handles.us
        height: sL.implicitHeight + 8 * handles.us
        radius: 5 * handles.us
        color: Qt.rgba(0, 0, 0, 0.72)
        Text {
            id: sL
            anchors.centerIn: parent
            text: Math.round(Camera.bw) + " x " + Math.round(Camera.bh)
            color: Theme.onSurface
            font.family: Theme.mono
            font.pixelSize: 11 * handles.us
            font.weight: Font.DemiBold
        }
    }

    // flip toggle (top-right) -- a tap target; taps do not compete with the drag.
    Rectangle {
        id: flipBtn
        width: 26 * handles.us
        height: 26 * handles.us
        radius: width / 2
        x: handles.width - width - 6 * handles.us
        y: 6 * handles.us
        color: Qt.rgba(0, 0, 0, flipHov.hovered ? 0.72 : 0.5)
        border.width: 1 * handles.us
        border.color: Qt.rgba(1, 1, 1, 0.12)
        GlyphIcon {
            anchors.centerIn: parent
            width: 15 * handles.us
            height: 15 * handles.us
            name: "flip"
            color: Camera.flipped ? Theme.primary : Theme.onSurface
            stroke: 1.7
        }
        HoverHandler { id: flipHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Camera.flipped = !Camera.flipped }
    }
}
