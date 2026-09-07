pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// A remote host at a glance: a state dot and word (never colour), the address,
// the round-trip, and three ink meters (load / memory / disk) drawn from the last
// probe. Tap opens the berth; CONNECT drops into a terminal. Warn and down are
// carried by the word and a hollow dot, so state reads without a hue.
Item {
    id: tile

    property var host: null
    signal tapped()
    signal connect()

    readonly property string alias: host ? (host.alias || "") : ""
    readonly property string state: tile.alias.length > 0 ? Remotes.stateOf(tile.alias) : "unknown"
    readonly property var reach: tile.alias.length > 0 ? Remotes.reachOf(tile.alias) : null
    readonly property var health: tile.alias.length > 0 ? Remotes.healthOf(tile.alias) : null
    readonly property bool live: state === "up" || state === "warn"
    readonly property bool selected: tile.alias.length > 0 && Remotes.selectedAlias === tile.alias

    readonly property real loadFrac: (health && health.ok && health.cpus > 0) ? Math.min(1, health.load1 / health.cpus) : -1
    readonly property real memFrac: (health && health.ok && health.memTotalKb > 0) ? (health.memTotalKb - health.memAvailKb) / health.memTotalKb : -1
    readonly property real diskFrac: (health && health.ok && health.diskPct >= 0) ? health.diskPct / 100 : -1

    implicitHeight: 104

    // a compact ink meter: label + five cells filled by a 0..1 fraction; unknown
    // (< 0) reads as a faint empty rail, never a false zero.
    component Meter: Row {
        id: mtr
        property string label: ""
        property real frac: -1
        readonly property bool known: frac >= 0
        readonly property int filled: known ? Math.max(0, Math.min(5, Math.round(frac * 5))) : 0
        readonly property bool hot: frac >= 0.9
        spacing: Tokens.s2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            text: I18n.tr(mtr.label)
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: 8; font.letterSpacing: 0.8
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    width: 8; height: 4
                    radius: 1
                    antialiasing: false
                    color: !mtr.known ? Tokens.lineSoft
                        : (index < mtr.filled ? (mtr.hot ? Tokens.ink : Tokens.inkDim) : Tokens.lineSoft)
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: tile.selected ? Tokens.tint10 : (ma.containsMouse ? Tokens.tint5 : "transparent")
        border.width: Tokens.border
        border.color: tile.selected ? Tokens.ink : (ma.containsMouse ? Tokens.lineStrong : Tokens.line)
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

        // header: dot + alias + state word
        Item {
            id: hdr
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: Tokens.s3
            height: 20
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.s2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7; radius: 3.5
                    antialiasing: true
                    color: tile.live ? Tokens.ink : "transparent"
                    border.width: tile.live ? 0 : Tokens.border
                    border.color: Tokens.inkFaint
                    // a warn host pulses; up and down are steady.
                    SequentialAnimation on opacity {
                        running: tile.state === "warn"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.alias
                    color: tile.live ? Tokens.ink : Tokens.inkDim
                    font.family: Tokens.ui; font.pixelSize: 14; font.weight: Font.DemiBold
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ({ "up": I18n.tr("UP"), "warn": I18n.tr("WARN"), "down": I18n.tr("DOWN"), "unknown": "-" })[tile.state] || "-"
                color: tile.state === "warn" || tile.state === "down" ? Tokens.ink : Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: 9; font.letterSpacing: 1.4
            }
        }

        // address + round trip
        Item {
            id: addr
            anchors { left: parent.left; right: parent.right; top: hdr.bottom }
            anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
            anchors.topMargin: 2
            height: 16
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 70
                elide: Text.ElideRight
                text: (tile.host ? (tile.host.user || "") : "") + (tile.host && tile.host.user ? "@" : "")
                    + (tile.host ? (tile.host.hostName || tile.alias) : "")
                color: Tokens.inkMuted
                font.family: Tokens.mono; font.pixelSize: 10
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: tile.reach && tile.reach.up === true
                text: tile.reach ? (tile.reach.rttMs + " ms") : ""
                color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: 10
            }
        }

        // meters + connect
        Item {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.margins: Tokens.s3
            height: 26
            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Meter { label: I18n.tr("LOAD"); frac: tile.loadFrac }
                Meter { label: I18n.tr("DISK"); frac: tile.diskFrac }
            }
            Btn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                text: I18n.tr("CONNECT")
                onAct: tile.connect()
            }
        }
    }
}
