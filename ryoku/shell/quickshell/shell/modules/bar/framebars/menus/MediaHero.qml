pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../.." as Pill
import shell.services
import "../../../../components"
import Ryoku.Ui.Singletons

// Media hero card: the showpiece on the Home tab. Full-width card visible only
// while a player exists. Art wash background, 84x84 thumbnail, marquee title,
// artist, seekable 2px progress line, transport row. Cava spectrum accent
// appears behind the transport; HARD GATED: process runs only while the
// sidebar is open, hero is visible, and a player is actively playing.
Item {
    id: root

    // Active = sidebar open AND on Home tab AND not on a detail page.
    // Gates both the position timer and the cava process.
    property bool active: false

    readonly property var players: Mpris.players.values.filter(p => p && !Media.isWallpaper(p))
    property var picked: null
    readonly property var player: (root.picked && root.players.indexOf(root.picked) !== -1)
        ? root.picked : Media.player

    visible: root.players.length > 0
    implicitHeight: root.players.length > 0 ? heroCard.implicitHeight : 0

    function fmtTime(sec) {
        sec = Math.max(0, Math.floor(sec));
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const r = sec % 60;
        const ss = (r < 10 ? "0" : "") + r;
        if (h >= 1) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss;
        return m + ":" + ss;
    }

    // ---- cava spectrum (playback bars behind transport) --------------------
    // Gate: only spawns while sidebar open AND hero visible AND player playing.
    readonly property bool cavaActive: root.active && root.player !== null
        && root.player !== undefined && root.player.isPlaying
    readonly property int cavaBars: 20
    property var cavaLevels: { var a = []; for (var i = 0; i < root.cavaBars; i++) a.push(0); return a; }
    property real cavaLastReadMs: 0

    onCavaActiveChanged: {
        if (!root.cavaActive) {
            var a = [];
            for (var i = 0; i < root.cavaBars; i++) a.push(0);
            root.cavaLevels = a;
        }
        root.cavaLastReadMs = 0;
    }

    Process {
        id: heroCava
        // Playback monitor via pulse; exec so SIGTERM reaches cava directly.
        command: ["sh", "-c",
            "command -v cava >/dev/null 2>&1 || exit 0; " +
            "mon=$(pactl get-default-sink 2>/dev/null).monitor; " +
            "cfg=\"${XDG_RUNTIME_DIR:-/tmp}/ryoku-cava-hero.conf\"; " +
            "printf '%s\\n' '[general]' 'framerate = 25' 'bars = 20' " +
            "'' '[input]' 'method = pulse' \"source = $mon\" " +
            "'' '[output]' 'method = raw' 'raw_target = /dev/stdout' " +
            "'data_format = ascii' 'ascii_max_range = 100' " +
            "'channels = mono' 'mono_option = average' " +
            "'' '[smoothing]' 'noise_reduction = 50' > \"$cfg\"; " +
            "exec cava -p \"$cfg\""]
        running: root.cavaActive
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var parts = line.trim().split(/[;\s]+/);
                if (parts.length < root.cavaBars) return;
                var out = [];
                for (var i = 0; i < root.cavaBars; i++)
                    out.push(Math.max(0, Math.min(1, (parseInt(parts[i]) || 0) / 100)));
                root.cavaLevels = out;
                root.cavaLastReadMs = Date.now();
            }
        }
        onExited: (code, status) => { if (root.cavaActive && code !== 0) cavaRestart.restart(); }
    }
    Timer { id: cavaRestart; interval: 1200; onTriggered: if (root.cavaActive && !heroCava.running) heroCava.running = true }
    // Settle to flat when no frame arrives (silence / restart gap).
    Timer {
        interval: 150; running: root.cavaActive; repeat: true
        onTriggered: if (Date.now() - root.cavaLastReadMs > 300) {
            var a = []; for (var i = 0; i < root.cavaBars; i++) a.push(0); root.cavaLevels = a;
        }
    }

    // ---- seek state --------------------------------------------------------
    readonly property real posn: root.player ? root.player.position : 0
    readonly property real len: (root.player && root.player.length > 0) ? root.player.length : 0
    readonly property real liveFrac: root.len > 0 ? Math.max(0, Math.min(1, root.posn / root.len)) : 0
    property bool seekArmed: false
    property bool seekSent: false
    property real seekFrac: 0
    readonly property real shownFrac: root.seekArmed ? root.seekFrac : root.liveFrac

    onPlayerChanged: {
        seekDebounce.stop(); seekIgnore.stop();
        root.seekArmed = false; root.seekSent = false;
    }

    function onScrub(frac) {
        root.seekFrac = Math.max(0, Math.min(1, frac));
        root.seekArmed = true; root.seekSent = false;
        seekDebounce.restart();
    }

    Timer {
        interval: 500; repeat: true
        running: root.active && root.player !== null && root.player !== undefined && root.player.isPlaying
        onTriggered: {
            root.player.positionChanged();
            if (root.seekSent && Math.abs(root.posn - root.seekFrac * root.len) < 1.5) {
                root.seekArmed = false; root.seekSent = false; seekIgnore.stop();
            }
        }
    }
    Timer { id: seekDebounce; interval: 300; onTriggered: {
        if (root.player && root.len > 0) {
            root.player.position = root.seekFrac * root.len;
            root.seekSent = true; seekIgnore.restart();
        } else { root.seekArmed = false; }
    }}
    Timer { id: seekIgnore; interval: 3000; onTriggered: { root.seekArmed = false; root.seekSent = false; } }

    function iconShuffle() { return (root.player && root.player.shuffle) ? "shuffle_on" : "shuffle"; }
    function iconLoop() {
        if (root.player) {
            if (root.player.loopState === MprisLoopState.Track) return "repeat_one_on";
            if (root.player.loopState === MprisLoopState.Playlist) return "repeat_on";
        }
        return "repeat";
    }
    function cycleLoop() {
        if (!root.player) return;
        if (root.player.loopState === MprisLoopState.None) root.player.loopState = MprisLoopState.Playlist;
        else if (root.player.loopState === MprisLoopState.Playlist) root.player.loopState = MprisLoopState.Track;
        else root.player.loopState = MprisLoopState.None;
    }

    // ---- small transport button --------------------------------------------
    component TransportBtn: Item {
        id: tbtn
        property string icon: ""
        property string tip: ""
        property bool lit: false
        property bool enabled: true
        signal clicked()

        width: 30; height: 30

        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: tba.pressed ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
                : tba.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.07)
                : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        scale: tba.pressed ? 0.88 : 1.0
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

        MaterialIcon {
            anchors.centerIn: parent
            font.pixelSize: 17
            text: tbtn.icon
            fill: tbtn.lit ? 1 : 0
            color: !tbtn.enabled
                ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.28)
                : tbtn.lit
                    ? Theme.inkOn(Theme.effectiveSurface, Theme.primary)
                    : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        MouseArea {
            id: tba; anchors.fill: parent; hoverEnabled: true
            cursorShape: tbtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: tbtn.enabled; onClicked: tbtn.clicked()
        }
        QsTip { text: tbtn.tip; hovered: tba.containsMouse && !tba.pressed }
    }

    // ---- hero card ---------------------------------------------------------
    Rectangle {
        id: heroCard
        width: root.width; radius: Theme.radiusWidget; color: Theme.surface
        border.width: Theme.borderWidth; border.color: Theme.outline
        clip: true
        implicitHeight: cardBody.implicitHeight + 24

        // Art wash: PreserveAspectCrop at ~0.15 opacity under a surface tint
        Image {
            anchors.fill: parent
            source: root.player ? (root.player.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            opacity: 0; asynchronous: true
            sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)), Math.max(1, Math.ceil(height * 2)))
            onStatusChanged: if (status === Image.Ready) opacity = 0.14
            Behavior on opacity { NumberAnimation { duration: Motion.rowFade } }
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.64)
        }

        SumiEdge {}

        Column {
            id: cardBody
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.margins: 12
            spacing: 8

            // Player chips (multi-player only)
            Flow {
                width: parent.width; spacing: 5
                visible: root.players.length > 1
                height: visible ? implicitHeight : 0

                Repeater {
                    model: root.players
                    delegate: Rectangle {
                        id: chip
                        required property var modelData; required property int index
                        readonly property bool isActive: root.player === chip.modelData
                        height: 22; width: chipLabel.implicitWidth + 14; radius: 11
                        color: chip.isActive ? Theme.primary
                            : chipA.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
                        border.width: 1
                        border.color: chip.isActive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                            : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Text {
                            id: chipLabel; anchors.centerIn: parent
                            text: chip.modelData.identity.length > 0 ? chip.modelData.identity : chip.modelData.dbusName
                            color: chip.isActive ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                            font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 2
                            font.weight: chip.isActive ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: chipA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: root.picked = chip.modelData
                        }
                    }
                }
            }

            // Art + info row
            Row {
                id: artInfoRow; width: parent.width; spacing: 12

                // 84x84 art thumbnail
                Rectangle {
                    id: artFrame; width: 84; height: 84
                    radius: Theme.radiusWidget
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                    clip: true

                    Image {
                        id: artImg; anchors.fill: parent
                        source: root.player ? (root.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                        sourceSize: Qt.size(168, 168)
                    }
                    MaterialIcon {
                        anchors.centerIn: parent; font.pixelSize: 28; fill: 0; text: "music_note"
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        visible: artImg.status !== Image.Ready || artImg.source === ""
                    }
                    SumiEdge { radius: Theme.radiusWidget }
                }

                // Right column
                Column {
                    id: infoCol
                    width: artInfoRow.width - artFrame.width - artInfoRow.spacing
                    anchors.verticalCenter: artFrame.verticalCenter
                    spacing: 3

                    // Marquee title (pauses on hover)
                    Item {
                        id: titleWrap; width: parent.width; height: titleM.implicitHeight
                        HoverHandler { id: titleHov }
                        Marquee {
                            id: titleM; width: parent.width
                            text: root.player ? (root.player.trackTitle || "") : ""
                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                            pixelSize: Theme.fontMd; weight: Font.DemiBold
                            active: root.active && !titleHov.hovered
                        }
                    }

                    // Artist
                    Text {
                        width: parent.width
                        text: root.player ? Theme.joinArtists(root.player.trackArtists, root.player.trackArtist) : ""
                        color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm; elide: Text.ElideRight
                    }

                    // Progress: elapsed | --2px track-- | total
                    Item {
                        id: progressRow; width: parent.width; height: 18
                        Text {
                            id: elapsedLbl
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtTime(root.shownFrac * root.len)
                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                            font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 2
                        }
                        Text {
                            id: totalLbl
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtTime(root.len)
                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                            font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 2
                        }
                        Rectangle {
                            id: progressTrack
                            anchors.left: elapsedLbl.right; anchors.leftMargin: 5
                            anchors.right: totalLbl.left; anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            height: 2; radius: 1
                            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
                            Rectangle {
                                width: parent.width * root.shownFrac
                                height: parent.height; radius: parent.radius; color: Theme.primary
                            }
                        }
                        MouseArea {
                            anchors.left: progressTrack.left; anchors.right: progressTrack.right
                            anchors.verticalCenter: progressTrack.verticalCenter; height: 18
                            enabled: root.player ? root.player.canSeek : false
                            cursorShape: Qt.SizeHorCursor
                            onPressed: mouse => root.onScrub(mouse.x / width)
                            onPositionChanged: mouse => { if (pressed) root.onScrub(Math.max(0, Math.min(1, mouse.x / width))) }
                        }
                    }

                    // Transport row + cava spectrum behind it
                    Item {
                        id: transportArea
                        width: parent.width; height: 34

                        // Cava bars (behind transport, z not needed since rendered first)
                        Row {
                            id: barsRow
                            anchors.fill: parent
                            readonly property real barW: Math.max(2, width / 32)
                            spacing: Math.max(1, (width - root.cavaBars * barW) / Math.max(1, root.cavaBars - 1))

                            Repeater {
                                model: root.cavaBars
                                delegate: Rectangle {
                                    id: spectrumBar
                                    required property int index
                                    readonly property real level: root.cavaLevels[index] || 0
                                    width: barsRow.barW
                                    height: transportArea.height * 0.88
                                    anchors.bottom: parent.bottom
                                    radius: 1
                                    color: Theme.primary
                                    opacity: spectrumBar.level > 0.01 ? 0.18 : 0
                                    transform: Scale {
                                        origin.y: spectrumBar.height
                                        yScale: spectrumBar.level
                                    }
                                }
                            }
                        }

                        // Transport buttons (on top of bars)
                        Row {
                            id: transportRow
                            anchors.centerIn: parent
                            spacing: 2

                            TransportBtn {
                                icon: root.iconShuffle(); tip: I18n.tr("Shuffle")
                                lit: root.player ? root.player.shuffle : false
                                enabled: root.player ? root.player.shuffleSupported : false
                                onClicked: if (root.player) root.player.shuffle = !root.player.shuffle
                            }
                            TransportBtn {
                                icon: "skip_previous"; tip: I18n.tr("Previous")
                                enabled: root.player ? root.player.canGoPrevious : false
                                onClicked: if (root.player) root.player.previous()
                            }

                            // Play/pause: 36px primary disc while playing, outline while paused
                            Item {
                                width: 36; height: 36; anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    id: playDisc; anchors.fill: parent; radius: width / 2
                                    readonly property bool playing: root.player ? root.player.isPlaying : false
                                    color: playing ? Theme.primary : "transparent"
                                    border.width: playing ? 0 : 2; border.color: Theme.primary
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    scale: playTap.pressed ? 0.88 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

                                    MaterialIcon {
                                        anchors.centerIn: parent; font.pixelSize: 20
                                        text: playDisc.playing ? "pause" : "play_arrow"
                                        fill: playDisc.playing ? 1 : 0
                                        color: playDisc.playing
                                            ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                                            : Theme.inkOn(Theme.effectiveSurface, Theme.primary)
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }
                                    MouseArea {
                                        id: playTap; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: root.player ? root.player.canTogglePlaying : false
                                        onClicked: if (root.player) root.player.togglePlaying()
                                    }
                                    QsTip {
                                        text: playDisc.playing ? I18n.tr("Pause") : I18n.tr("Play")
                                        hovered: playTap.containsMouse && !playTap.pressed
                                    }
                                }
                            }

                            TransportBtn {
                                icon: "skip_next"; tip: I18n.tr("Next")
                                enabled: root.player ? root.player.canGoNext : false
                                onClicked: if (root.player) root.player.next()
                            }
                            TransportBtn {
                                icon: root.iconLoop(); tip: I18n.tr("Repeat")
                                lit: root.player ? (root.player.loopState !== MprisLoopState.None) : false
                                enabled: root.player ? root.player.loopSupported : false
                                onClicked: root.cycleLoop()
                            }
                        }
                    }
                }
            }
        }
    }
}
