import QtQuick
import shell.services

// One labelled group in the ribbon's control row (docs/stage.md): its controls
// on top, a small sentence-case caption under them, and a thin divider on its
// right so the groups read as a run of tools, MS Paint style. No ALL-CAPS
// eyebrow, no middle dot; the caption names the group and nothing shouts.
Item {
    id: g
    property string caption: ""
    property bool last: false
    readonly property real gap: 24

    // Controls drop straight into the group; the caller anchors them in the row.
    default property alias content: row.data

    implicitWidth: Math.max(row.implicitWidth, cap.implicitWidth) + (g.last ? 0 : g.gap)
    implicitHeight: 66

    Column {
        id: col
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 6

        Item {
            id: ctrlHost
            width: row.implicitWidth
            height: 46
            Row {
                id: row
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
            }
        }
        Text {
            id: cap
            text: g.caption
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 3
            font.weight: Font.Medium
        }
    }

    Rectangle {
        visible: !g.last
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 3
        width: 1
        height: 40
        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)
    }
}
