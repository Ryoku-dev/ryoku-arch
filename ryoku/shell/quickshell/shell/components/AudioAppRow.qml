pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import shell.services
import Ryoku.Ui.Singletons

// One per-app mixer row, shared by the audio menu and the audio popout: the app
// icon doubles as a mute toggle and the app name sits above its own live VU
// fader. A capture row (an app recording the mic) carries a small vermilion mic
// tag so a streamer can see who is on the input at a glance. Reads live from the
// stream node via Audio.
Row {
    id: root

    property real s: 1
    property var stream: null
    property bool open: false
    property bool capture: false

    readonly property var appAudio: root.stream ? root.stream.audio : null
    readonly property bool appMuted: root.appAudio ? root.appAudio.muted : false

    spacing: 8 * root.s

    // the app icon doubles as its mute toggle.
    Item {
        width: 20 * root.s
        height: 20 * root.s
        anchors.verticalCenter: parent.verticalCenter

        IconImage {
            anchors.fill: parent
            source: Audio.streamIcon(root.stream)
            opacity: root.appMuted ? 0.4 : 1
        }
        GlyphIcon {
            visible: root.capture
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 10 * root.s
            height: width
            name: "mic"
            color: Theme.primary
            stroke: 2
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.appAudio) root.appAudio.muted = !root.appAudio.muted
        }
    }

    Column {
        width: root.width - (20 + 8) * root.s
        spacing: 1 * root.s

        Text {
            width: parent.width
            text: Audio.streamName(root.stream)
            elide: Text.ElideRight
            color: Theme.inkOn(Theme.effectiveSurface, root.appMuted ? Theme.onSurfaceVariant : Theme.onSurface, 3.0)
            font.family: Theme.fontPrimary
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }
        HFader {
            width: parent.width
            s: root.s
            showIcon: false
            lit: root.open
            value: root.appAudio ? root.appAudio.volume : 0
            muted: root.appMuted
            valueLabel: root.appAudio ? (root.appMuted ? I18n.tr("off") : Math.round(root.appAudio.volume * 100) + "%") : ""
            peakNode: root.stream
            peakEnabled: root.open
            onMoved: v => { if (root.appAudio) root.appAudio.volume = v; }
        }
    }
}
