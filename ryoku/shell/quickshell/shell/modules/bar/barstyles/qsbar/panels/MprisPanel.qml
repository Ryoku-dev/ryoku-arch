import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import shell.services
import "../modules"
import Ryoku.Ui.Singletons

// The now-playing card: the record on the left, the track and its transport on
// the right, and the desktop's 10-band equalizer underneath.
//
// It is the mpris widget's popup, so it opens where the widget is and closes on
// a click outside or Escape, like every other qsbar panel. The spectrum ringing
// the record is the shell's one cava feed (AudioBars), not a private analyser,
// and the equalizer is the Equalizer service: bands are live, and the filter only
// exists in the audio graph while the equalizer is on.
PanelWindow {
    id: mprisPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-mpris"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    // ── the player ──────────────────────────────────────────────────────────
    // Selection (incl. ghost-filtering) lives in MprisSelect so the bar widget
    // and this panel always agree on the active player.
    MprisSelect { id: sel }
    readonly property var  player:  sel.player
    readonly property bool active:  sel.active
    readonly property bool playing: sel.playing
    MprisArtwork { id: artwork; player: mprisPanel.player }

    readonly property string playerName: {
        if (!player) return ""
        var n = player.identity || player.dbusName || ""
        return n.replace(/^org\.mpris\.MediaPlayer2\./, "")
    }

    // ── live position ───────────────────────────────────────────────────────
    // Quickshell only refreshes `position` sporadically, so we extrapolate
    // locally while playing and resync whenever the player reports a fresh value.
    property real curPos: 0
    property real curLen: 0
    property real _lastRead: -1
    Timer {
        interval: 500; repeat: true
        running: mprisPanel.visible && mprisPanel.active
        triggeredOnStart: true
        onTriggered: {
            if (!mprisPanel.player) return
            var p = mprisPanel.player.position || 0
            mprisPanel.curLen = mprisPanel.player.length || 0
            if (Math.abs(p - mprisPanel._lastRead) > 0.05) {
                mprisPanel.curPos = p            // player gave a fresh value
                mprisPanel._lastRead = p
            } else if (mprisPanel.playing) {
                var cap = mprisPanel.curLen > 0 ? mprisPanel.curLen : p + 1e9
                mprisPanel.curPos = Math.min(cap, mprisPanel.curPos + 0.5)
            }
        }
    }
    onPlayingChanged: { _lastRead = -1 }   // force a resync on play/pause
    function fmtTime(s) {
        if (!s || s < 0) return "0:00"
        var m = Math.floor(s / 60)
        var sec = Math.floor(s % 60)
        return m + ":" + (sec < 10 ? "0" + sec : "" + sec)
    }

    // Some players keep reporting a position past the end of the track (seen on
    // Sonora), which reads as 4:25 of a 3:42 song. The bar already clamps; so
    // does the readout beside it.
    readonly property real shownPos: mprisPanel.curLen > 0
        ? Math.min(mprisPanel.curPos, mprisPanel.curLen)
        : mprisPanel.curPos

    function seekTo(fraction) {
        if (!mprisPanel.player || !mprisPanel.player.canSeek || mprisPanel.curLen <= 0) return
        var target = Math.max(0, Math.min(1, fraction)) * mprisPanel.curLen
        mprisPanel.curPos = target
        mprisPanel._lastRead = -1
        mprisPanel.player.position = target
    }

    // ── spectrum ────────────────────────────────────────────────────────────
    // One analyser serves every music surface; claim it only while the card is up.
    readonly property var levels: AudioBars.levels
    readonly property int bands: AudioBars.bars
    onVisibleChanged: {
        AudioBars.setActive(mprisPanel, mprisPanel.visible)
        // Ask the script what the graph actually looks like. The state file is
        // watched, but it is replaced by a rename, and a card that opens showing
        // last week's curve is worse than one that costs a process to be right.
        if (mprisPanel.visible)
            Equalizer.refresh()
    }
    Component.onDestruction: AudioBars.setActive(mprisPanel, false)

    property real reveal: root.mprisVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.mprisVisible ? 160 : 120
            easing.type: root.mprisVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.mprisVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── entry stagger ───────────────────────────────────────────────────────
    // The card assembles rather than appearing: the record swings in, then the
    // track, the transport, the equalizer and finally its presets. Each value is
    // an opacity AND the amount of travel left, so one number drives both.
    property real inCover: 0
    property real inText: 0
    property real inControls: 0
    property real inEq: 0
    property real inPresets: 0

    ParallelAnimation {
        id: intro
        NumberAnimation { target: mprisPanel; property: "inCover"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: mprisPanel; property: "inText"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 110 }
            NumberAnimation { target: mprisPanel; property: "inControls"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 160 }
            NumberAnimation { target: mprisPanel; property: "inEq"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 220 }
            NumberAnimation { target: mprisPanel; property: "inPresets"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
        }
    }

    Connections {
        target: mprisPanel.root
        function onMprisVisibleChanged() {
            if (!mprisPanel.root.mprisVisible) return
            mprisPanel.inCover = 0; mprisPanel.inText = 0; mprisPanel.inControls = 0
            mprisPanel.inEq = 0; mprisPanel.inPresets = 0
            intro.restart()
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.mprisVisible = false }

    Rectangle {
        id: card
        // Wide enough for the record beside a full track block, and for ten band
        // sliders that still read as sliders rather than hairlines.
        width: 560
        height: col.implicitHeight + 28
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: mprisPanel.root
            ownerActive: mprisPanel.root.mprisVisible
            targetX: mprisPanel.root.mprisBarX
            reveal: mprisPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.mprisBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - mprisPanel.reveal)
            : (barBottom + gap) - 2 * (1 - mprisPanel.reveal)
        opacity: mprisPanel.reveal
        focus: root.mprisVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.mprisVisible = false; event.accepted = true }
            else if (event.key === Qt.Key_Space && mprisPanel.player) {
                mprisPanel.player.togglePlaying(); event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── header ──
            Item {
                width: parent.width
                height: 20
                UiText {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("NOW PLAYING")
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: mprisPanel.active && mprisPanel.playerName !== ""
                        text: mprisPanel.playerName
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mprisVisible = false }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── record + track ──
            Row {
                width: parent.width
                height: 168
                spacing: 16

                // ── the record: art under the rings, spectrum around it ──
                Item {
                    id: coverHost
                    width: 168
                    height: 168
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: mprisPanel.inCover
                    transform: Translate { x: -26 * (1 - mprisPanel.inCover) }

                    readonly property real artRadius: width * 0.41
                    readonly property real barRoom: width / 2 - artRadius
                    readonly property real barWidth: Math.max(2, (2 * Math.PI * artRadius) / mprisPanel.bands * 0.55)

                    // Breathe with the music: the whole record leans on the mean
                    // energy of the spectrum rather than on any single band.
                    readonly property real pulse: mprisPanel.playing ? AudioBars.energy : 0

                    Item {
                        id: discGroup
                        anchors.centerIn: parent
                        width: coverHost.artRadius * 2
                        height: width
                        scale: 1 + coverHost.pulse * 0.05
                        Behavior on scale { SpringAnimation { spring: 4.6; damping: 0.36; mass: 0.8 } }

                        // spectrum ring
                        Repeater {
                            model: mprisPanel.bands
                            delegate: Item {
                                required property int index
                                anchors.centerIn: parent
                                width: 0; height: 0
                                rotation: index * (360 / mprisPanel.bands)
                                readonly property real level: {
                                    var lv = mprisPanel.levels
                                    return (lv && lv[index] !== undefined) ? lv[index] : 0
                                }
                                Rectangle {
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: coverHost.artRadius + 3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: coverHost.barWidth
                                    height: Math.max(2, parent.level * (coverHost.barRoom - 4))
                                    radius: width / 2
                                    antialiasing: true
                                    color: root.seal
                                    opacity: 0.35 + parent.level * 0.65
                                    Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // the disc itself: art, grooves, spindle
                        Item {
                            id: disc
                            anchors.fill: parent
                            rotation: 0
                            NumberAnimation on rotation {
                                id: spin
                                from: 0; to: 360; duration: 24000
                                loops: Animation.Infinite
                                running: mprisPanel.visible
                                // Pausing keeps the needle where it stopped, but
                                // Qt refuses the call on a stopped animation, so
                                // the state only exists while it runs.
                                paused: spin.running && !mprisPanel.playing
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: root.fillIdle
                                border.width: 1
                                border.color: mprisPanel.playing ? root.seal : root.sep
                                Behavior on border.color { ColorAnimation { duration: 400 } }
                            }

                            // circular crop for the artwork: QML `clip` is a
                            // rectangle, so the round edge is a mask.
                            Rectangle {
                                id: artMask
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                visible: false
                                layer.enabled: true
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: 1
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: artMask
                                }
                                Image {
                                    id: discArt
                                    anchors.fill: parent
                                    source: artwork.source
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    visible: status === Image.Ready
                                }
                            }

                            IconText {
                                anchors.centerIn: parent
                                visible: discArt.status !== Image.Ready
                                text: "music_note"
                                font.pixelSize: 46
                                color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.5)
                            }

                            // grooves
                            Repeater {
                                model: [0.88, 0.74, 0.60, 0.46]
                                delegate: Rectangle {
                                    required property real modelData
                                    anchors.centerIn: parent
                                    width: parent.width * modelData
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.22)
                                    antialiasing: true
                                }
                            }

                            // spindle
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.24
                                height: width
                                radius: width / 2
                                color: root.paper
                                border.width: 1
                                border.color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.55)
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.3
                                    height: width
                                    radius: width / 2
                                    color: root.sep
                                }
                            }
                        }
                    }
                }

                // ── track, source, progress, transport ──
                Column {
                    id: infoCol
                    width: parent.width - coverHost.width - 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Column {
                        width: parent.width
                        spacing: 4
                        opacity: mprisPanel.inText
                        transform: Translate { x: 20 * (1 - mprisPanel.inText) }

                        UiText {
                            width: parent.width
                            text: mprisPanel.active
                                ? (mprisPanel.player.trackTitle || I18n.tr("Unknown"))
                                : I18n.tr("No song playing")
                            color: root.ink
                            font.family: root.mono; font.pixelSize: 15; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        UiText {
                            width: parent.width
                            text: mprisPanel.active
                                ? (mprisPanel.player.trackArtist || I18n.tr("Unknown artist"))
                                : I18n.tr("no active player")
                            color: root.sumiHi
                            font.family: root.mono; font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        UiText {
                            width: parent.width
                            visible: mprisPanel.active && text !== ""
                            text: mprisPanel.player ? (mprisPanel.player.trackAlbum || "") : ""
                            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // ── where the sound is going, and what is making it ──
                    Row {
                        spacing: 6
                        opacity: mprisPanel.inText
                        transform: Translate { x: 20 * (1 - mprisPanel.inText) }

                        component Chip : Rectangle {
                            id: chip
                            property string glyph: ""
                            property string label: ""
                            // A device name runs as long as its driver feels like
                            // ("Ryzen HD Audio Controller Analog Stereo"), and a Row
                            // neither clips nor elides, so the label carries the cap
                            // and the chip simply wraps whatever it settles on.
                            property real maxWidth: 1000
                            height: 20
                            width: chipRow.implicitWidth + 16
                            radius: root.panelButtonRadius
                            color: root.fillIdle
                            border.width: 1
                            border.color: root.sep
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 4
                                IconText {
                                    id: chipGlyph
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.glyph
                                    font.pixelSize: 12
                                    color: root.sumiHi
                                }
                                UiText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.label
                                    color: root.ink
                                    font.family: root.mono; font.pixelSize: 10
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth,
                                        chip.maxWidth - 20 - chipGlyph.implicitWidth)
                                }
                            }
                        }

                        Chip {
                            id: deviceChip
                            glyph: Audio.nodeIcon(Audio.sink) === "headphones" ? "headphones" : "speaker"
                            label: Audio.nodeLabel(Audio.sink)
                            // Whatever the source chip leaves behind.
                            maxWidth: infoCol.width - 6 - sourceChip.width
                        }
                        Chip {
                            id: sourceChip
                            visible: mprisPanel.active
                            glyph: "graphic_eq"
                            label: I18n.tr("via %1").arg(mprisPanel.playerName || I18n.tr("Media"))
                            maxWidth: infoCol.width * 0.45
                        }
                    }

                    // ── progress ──
                    Item {
                        width: parent.width
                        height: 26
                        visible: mprisPanel.active
                        opacity: mprisPanel.inControls
                        transform: Translate { y: 8 * (1 - mprisPanel.inControls) }

                        Rectangle {
                            id: track
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.topMargin: 4
                            height: 5; radius: 2.5
                            color: root.fillActive
                            Rectangle {
                                id: played
                                height: parent.height; radius: parent.radius
                                color: root.seal
                                width: parent.width * (mprisPanel.curLen > 0
                                    ? Math.min(1, mprisPanel.curPos / mprisPanel.curLen) : 0)
                                Behavior on width { NumberAnimation { duration: seekMa.pressed ? 0 : 450 } }
                            }
                            Rectangle {
                                x: played.width - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: seekMa.containsMouse || seekMa.pressed ? 11 : 0
                                height: width
                                radius: width / 2
                                color: root.seal
                                visible: mprisPanel.curLen > 0
                                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: seekMa
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top
                            height: 14
                            hoverEnabled: true
                            enabled: mprisPanel.player ? mprisPanel.player.canSeek : false
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: (m) => mprisPanel.seekTo(m.x / width)
                            onPositionChanged: (m) => { if (pressed) mprisPanel.seekTo(m.x / width) }
                        }
                        UiText {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            text: mprisPanel.fmtTime(mprisPanel.shownPos)
                            color: root.sumiHi; font.family: root.mono; font.pixelSize: 10
                        }
                        UiText {
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            text: mprisPanel.fmtTime(mprisPanel.curLen)
                            color: root.sumiHi; font.family: root.mono; font.pixelSize: 10
                        }
                    }

                    // ── transport ──
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        visible: mprisPanel.active
                        opacity: mprisPanel.inControls
                        transform: Translate { y: 12 * (1 - mprisPanel.inControls) }

                        component TransportButton : Rectangle {
                            id: tb
                            property string glyph: ""
                            property bool enabled: true
                            property bool primary: false
                            signal activated()
                            width: primary ? 38 : 30
                            height: width
                            radius: root.panelButtonRadius
                            color: !tb.enabled ? root.fillIdle
                                 : (tbMa.containsMouse ? root.fillHover : root.fillIdle)
                            border.width: 1
                            border.color: tbMa.containsMouse && tb.enabled ? root.seal : root.sep
                            Behavior on color { ColorAnimation { duration: 120 } }
                            IconText {
                                anchors.centerIn: parent
                                text: tb.glyph
                                font.pixelSize: tb.primary ? 22 : 18
                                fill: 1
                                color: !tb.enabled ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                                     : (tb.primary ? root.seal : root.ink)
                            }
                            MouseArea {
                                id: tbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: tb.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tb.activated()
                            }
                        }

                        TransportButton {
                            glyph: "skip_previous"
                            enabled: mprisPanel.player ? mprisPanel.player.canGoPrevious : false
                            onActivated: if (mprisPanel.player) mprisPanel.player.previous()
                        }
                        TransportButton {
                            glyph: mprisPanel.playing ? "pause" : "play_arrow"
                            primary: true
                            enabled: mprisPanel.player ? mprisPanel.player.canTogglePlaying : false
                            onActivated: if (mprisPanel.player) mprisPanel.player.togglePlaying()
                        }
                        TransportButton {
                            glyph: "skip_next"
                            enabled: mprisPanel.player ? mprisPanel.player.canGoNext : false
                            onActivated: if (mprisPanel.player) mprisPanel.player.next()
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── equalizer ───────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 20
                opacity: mprisPanel.inEq
                transform: Translate { y: 8 * (1 - mprisPanel.inEq) }

                UiText {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("EQUALIZER")
                    color: root.ink; font.family: root.mono; font.pixelSize: 11
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    // The state, in the user's words: which curve is loaded, and
                    // whether the filter is actually in the audio graph.
                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Equalizer.presetLabel(Equalizer.preset)
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                    Rectangle {
                        id: eqToggle
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 20
                        radius: root.panelButtonRadius
                        color: Equalizer.on ? root.fillActive
                             : (eqToggleMa.containsMouse ? root.fillHover : root.fillIdle)
                        border.width: 1
                        border.color: (Equalizer.on || eqToggleMa.containsMouse) ? root.seal : root.sep
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: Equalizer.on ? I18n.tr("ON") : I18n.tr("OFF")
                            color: Equalizer.on ? root.seal : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.45)
                            font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                        }
                        MouseArea {
                            id: eqToggleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Equalizer.setOn(!Equalizer.on)
                        }
                    }
                }
            }

            // ── the ten bands ──
            Row {
                id: bandRow
                width: parent.width
                height: 132
                opacity: mprisPanel.inEq
                transform: Translate { y: 14 * (1 - mprisPanel.inEq) }

                Repeater {
                    model: Equalizer.bandCount
                    delegate: Item {
                        id: band
                        required property int index
                        width: bandRow.width / Equalizer.bandCount
                        height: bandRow.height

                        // While the finger is down the slider owns its value, so
                        // the service's answer (which arrives a few ms later, and
                        // once more after the debounce) can never yank it back.
                        property bool dragging: false
                        property int dragDb: 0
                        readonly property int db: dragging ? dragDb : Equalizer.gainAt(index)
                        readonly property real frac: (db + Equalizer.range) / (2 * Equalizer.range)

                        readonly property int trackHeight: band.height - 34
                        readonly property real handleSize: 13

                        function dbAt(y) {
                            var usable = band.trackHeight - band.handleSize
                            var t = 1 - Math.max(0, Math.min(1, (y - band.handleSize / 2) / usable))
                            return Math.round(t * 2 * Equalizer.range - Equalizer.range)
                        }

                        Timer {
                            id: livePush
                            interval: 110
                            onTriggered: Equalizer.setBand(band.index, band.dragDb)
                        }

                        Rectangle {
                            id: bandTrack
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: 10
                            height: band.trackHeight
                            radius: 5
                            color: root.fillIdle
                            border.width: 1
                            border.color: bandMa.containsMouse || band.dragging ? root.seal : root.sep
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            // filled from the floor, the way a graphic EQ reads
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 1
                                height: Math.max(0, (parent.height - 2) * band.frac)
                                radius: 4
                                color: Equalizer.on ? root.seal
                                     : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.35)
                                Behavior on height { NumberAnimation { duration: band.dragging ? 0 : 220; easing.type: Easing.OutCubic } }
                            }

                            // 0 dB, so a boost reads apart from a cut
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: (parent.height - 2) * 0.5
                                width: parent.width + 6
                                height: 1
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
                            }
                        }

                        Rectangle {
                            id: handle
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: band.handleSize
                            height: width
                            radius: width / 2
                            y: (band.trackHeight - band.handleSize) * (1 - band.frac)
                            color: root.paper
                            border.width: 2
                            border.color: Equalizer.on ? root.seal
                                : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.45)
                            scale: band.dragging ? 1.18 : 1
                            Behavior on y { NumberAnimation { duration: band.dragging ? 0 : 220; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: bandMa
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: 22
                            height: band.trackHeight
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (m) => {
                                band.dragDb = band.dbAt(m.y)
                                band.dragging = true
                                livePush.restart()
                            }
                            onPositionChanged: (m) => {
                                if (!band.dragging) return
                                var next = band.dbAt(m.y)
                                if (next === band.dragDb) return
                                band.dragDb = next
                                if (!livePush.running) livePush.restart()
                            }
                            onReleased: {
                                livePush.stop()
                                Equalizer.setBand(band.index, band.dragDb)
                                band.dragging = false
                            }
                            onCanceled: {
                                livePush.stop()
                                band.dragging = false
                            }
                            onWheel: (w) => {
                                var step = w.angleDelta.y > 0 ? 1 : -1
                                Equalizer.setBand(band.index, Equalizer.gainAt(band.index) + step)
                            }
                        }

                        UiText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: bandTrack.bottom
                            anchors.topMargin: 4
                            text: bandMa.containsMouse || band.dragging
                                ? (band.db > 0 ? "+" + band.db : "" + band.db)
                                : Equalizer.bandLabels[band.index]
                            color: bandMa.containsMouse || band.dragging ? root.seal : root.sumi
                            font.family: root.mono; font.pixelSize: 9
                        }
                    }
                }
            }

            // ── presets ──
            Grid {
                width: parent.width
                columns: 4
                rows: 2
                columnSpacing: 6
                rowSpacing: 6
                opacity: mprisPanel.inPresets
                transform: Translate { y: 12 * (1 - mprisPanel.inPresets) }

                Repeater {
                    model: Equalizer.presets
                    delegate: Rectangle {
                        id: presetTile
                        required property string modelData
                        readonly property bool on: Equalizer.preset === modelData
                        width: (parent.width - 3 * 6) / 4
                        height: 24
                        radius: root.panelButtonRadius
                        color: presetTile.on ? root.fillActive
                             : (presetMa.containsMouse ? root.fillHover : root.fillIdle)
                        border.width: 1
                        border.color: (presetTile.on || presetMa.containsMouse) ? root.seal : root.sep
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: Equalizer.presetLabel(presetTile.modelData)
                            color: presetTile.on ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                        }
                        MouseArea {
                            id: presetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Equalizer.applyPreset(presetTile.modelData)
                        }
                    }
                }
            }
        }
    }
}
