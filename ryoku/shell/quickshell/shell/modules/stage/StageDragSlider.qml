import QtQuick
import shell.services

// Drag-only slider: no wheel handler, so scrolling never changes a value
// (docs/stage.md). Emits `changed` on press and drag.
Item {
    id: ds
    property string title: ""
    property real value: 0
    property real min: 0
    property real max: 1
    property int decimals: 2
    property string unit: ""
    signal changed(real v)
    width: parent ? parent.width : 0
    height: 46
    function valueAt(mx) {
        const t = track.width - 14;
        const frac = Math.max(0, Math.min(1, (mx - 7) / Math.max(1, t)));
        return ds.min + frac * (ds.max - ds.min);
    }
    Text {
        id: dsLabel
        anchors.left: parent.left
        anchors.top: parent.top
        text: ds.title
        color: Theme.onSurface
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 1
        font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        text: ds.value.toFixed(ds.decimals) + ds.unit
        color: Theme.onSurfaceVariant
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 2
    }
    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 6
        radius: 3
        color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: 3
            color: Theme.primary
            width: 7 + (track.width - 14) * ((ds.value - ds.min) / Math.max(0.0001, ds.max - ds.min))
        }
        Rectangle {
            id: thumb
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(track.width - 14, 7 + (track.width - 14) * ((ds.value - ds.min) / Math.max(0.0001, ds.max - ds.min)) - 7))
            color: Theme.surface
            border.width: 2
            border.color: Theme.primary
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -12
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            onPositionChanged: mouse => {
                if (mouse.buttons & Qt.LeftButton)
                    ds.changed(ds.valueAt(mouse.x));
            }
            onPressed: mouse => ds.changed(ds.valueAt(mouse.x))
        }
    }
}
