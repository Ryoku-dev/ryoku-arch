pragma ComponentBehavior: Bound

import QtQuick
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// System monitor popout: a frame-edge card (shared PopoutCard, so it opens and
// melts like the bluetooth/battery/network cards) with CPU / memory / (when a
// sensor is found) temperature ring gauges, a CPU-history sparkline, and an
// uptime + memory readout. Reuses the SysMonitor card; claims polling only while
// open. Never grabs the keyboard; dismisses on an outside click.
Item {
    id: root

    property real s: 1
    property bool open: false

    readonly property real pad: 13 * root.s
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)

    implicitWidth: 260 * root.s
    implicitHeight: content.implicitHeight + root.pad * 2

    PopoutCard { anchors.fill: parent }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: 12 * root.s

        Text {
            text: I18n.tr("SYSTEM")
            color: root.inkDim
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.letterSpacing: 1.6
            font.weight: Font.Medium
        }

        SysMonitor {
            width: parent.width
            s: root.s
            active: root.open
        }
    }
}
