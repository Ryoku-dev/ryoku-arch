// Kairos: the island bar style. The clock is the centre island -- it rests as a
// small pill on the screen's centre line and expands there, symmetric, into the
// clock over the rolling date wheel. The music island is a bubble to its left
// that peeks open to the transport on hover and opens into the full now-playing
// panel on a click; the expanding clock pushes the bubble aside, and moving the
// pointer off the open panel closes it.

import QtQuick
import QtQuick.Effects
import shell.services
import "../IslandMetrics.js" as Island
import "." as C

Item {
    id: island

    // True while the launcher owns the island; both then rest, and the launcher's
    // own pill (which starts at the clock's exact size) covers the clock.
    property bool suspended: false

    readonly property var player: Media.player
    readonly property bool hasTrack: Media.present
    readonly property real topGap: Island.topGap
    readonly property real restHeight: Island.restHeight
    readonly property real restFontSize: Island.restFontSize
    readonly property real band: topGap + restHeight
    readonly property real reach: topGap + Math.max(Island.hoverHeight, Island.musicHeight)
        + Island.shadowBleed

    // ── the music island ─────────────────────────────────────────────────────
    // Rests as a bubble beside the clock. A hover peeks the transport open; a
    // click opens the full now-playing panel. Moving the pointer off the island
    // closes it again -- no click needed -- and a track never opens it by itself.
    property bool pinnedFull: false
    onHasTrackChanged: if (!island.hasTrack) island.pinnedFull = false
    // Leaving the island (hover lost through the grace timer) closes the panel,
    // unless a progress-bar scrub is in flight -- a drag may stray off the panel.
    readonly property bool musicScrubbing: music.scrubbing
    onMusicHoveredChanged: if (!island.musicHovered && !island.musicScrubbing) island.pinnedFull = false
    onMusicScrubbingChanged: if (!island.musicScrubbing && !island.musicHovered) island.pinnedFull = false

    function toggleFull() { island.pinnedFull = !island.pinnedFull; }

    readonly property bool full: island.pinnedFull && !island.suspended
    property real fullProgress: island.full ? 1 : 0
    property real peekProgress:
        (island.musicHovered && island.hasTrack && !island.full && !island.suspended) ? 1 : 0
    property real trackPresence: island.hasTrack ? 1 : 0

    Behavior on fullProgress {
        enabled: !Motion.reduce
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
    }
    Behavior on peekProgress {
        enabled: !Motion.reduce
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
    }
    Behavior on trackPresence {
        enabled: !Motion.reduce
        NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
    }

    // ── the clock island ─────────────────────────────────────────────────────
    property real clockProgress: (island.clockHovered && !island.suspended) ? 1 : 0
    Behavior on clockProgress {
        enabled: !Motion.reduce && !island.suspended
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
    }

    // Hover intent, one timer each: a pointer crossing the gap between the two
    // islands must not collapse the one it left mid-reach, and leaving one must
    // not cancel the other's hover.
    property bool musicHovered: false
    property bool clockHovered: false
    Timer {
        id: clockGrace
        interval: 320
        onTriggered: island.clockHovered = false
    }
    Timer {
        id: musicGrace
        interval: 320
        onTriggered: island.musicHovered = false
    }

    // ── geometry ─────────────────────────────────────────────────────────────
    // Measured at a fixed size, so the growing clock cannot feed back into the
    // width it is growing inside.
    readonly property real restWidth: Math.round(metrics.implicitWidth + 2 * Island.restPadX)
    readonly property real clockWidth: Math.round(island.restWidth
        + (Island.hoverWidth - island.restWidth) * island.clockProgress)
    readonly property real clockHeight: Math.round(island.restHeight
        + (Island.hoverHeight - island.restHeight) * island.clockProgress)
    readonly property real clockRadius: Island.restHeight / 2
        + (Island.hoverRadius - Island.restHeight / 2) * island.clockProgress

    // How far to the left of the clock the music reaches (0 with no track).
    readonly property real musicExtent: (music.width + Island.bubbleGap) * island.trackPresence
    // The clock rests centred and expands symmetric, so it reaches this far left
    // of its resting edge; reserve that (or the music's extent) so it has room to
    // grow left without leaving the item.
    readonly property real clockGrowMax: (Island.hoverWidth - island.restWidth) / 2
    readonly property real clockRestLeft: Math.max(island.clockGrowMax, island.musicExtent)
    // The clock's resting centre, fixed in item coordinates: the scene lands it on
    // the screen's centre line, so the clock never drifts as the music opens and
    // it always expands around that line.
    readonly property real clockRestCentre: island.clockRestLeft + island.restWidth / 2

    width: Math.round(island.clockRestCentre + island.clockWidth / 2)
    height: Math.round(Math.max(island.hasTrack ? music.height : 0, island.clockHeight))

    readonly property color fill: Theme.shadow
    readonly property color ink: Theme.ink(fill, 7)

    C.MusicSurface {
        id: music
        // Pinned just left of the clock's live left edge, so the expanding clock
        // pushes the bubble aside instead of covering it; grows leftward.
        x: island.clockRestCentre - island.clockWidth / 2 - Island.bubbleGap - width
        z: 0
        player: island.player
        peek: island.peekProgress
        full: island.fullProgress
        ink: island.ink
        accent: Theme.primary
        opacity: island.trackPresence
        onActivated: island.toggleFull()

        HoverHandler {
            id: musicHover
            onHoveredChanged: {
                if (hovered) {
                    musicGrace.stop();
                    island.musicHovered = true;
                } else {
                    musicGrace.restart();
                }
            }
        }
    }

    Rectangle {
        id: clockPill
        // Grows symmetric around its fixed resting centre, over the music.
        x: island.clockRestCentre - island.clockWidth / 2
        y: 0
        z: 2
        width: island.clockWidth
        height: island.clockHeight
        radius: island.clockRadius
        color: island.fill
        // A hairline rim so the pill's rounded shape reads on any wallpaper --
        // its pure-black fill would otherwise vanish into a dark desktop.
        border.width: 1
        border.color: Qt.rgba(island.ink.r, island.ink.g, island.ink.b, 0.16)
        clip: true

        HoverHandler {
            id: clockHover
            onHoveredChanged: {
                if (hovered) {
                    clockGrace.stop();
                    island.clockHovered = true;
                } else {
                    clockGrace.restart();
                }
            }
        }

        C.Clock { id: clock }

        Text {
            id: metrics
            visible: false
            text: clock.time
            font.family: Theme.mono
            font.pixelSize: Island.restFontSize
        }

        // One Text at native size per step, never two copies crossfading: a
        // whole-pixel step keeps the growth crisp and cannot ghost.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(Island.restHeight / 2
                + (Island.hoverClockCentreY - Island.restHeight / 2) * island.clockProgress
                - height / 2)
            text: clock.time
            color: island.ink
            font.family: Theme.mono
            font.pixelSize: Math.round(Island.restFontSize
                + (Island.hoverFontSize - Island.restFontSize) * island.clockProgress)
            font.letterSpacing: 0.5 + 0.5 * island.clockProgress
        }

        C.DateWheel {
            id: wheel
            visible: island.clockProgress > 0.01
            anchors.horizontalCenter: parent.horizontalCenter
            y: Island.wheelTop
            width: parent.width
            height: Island.wheelHeight
            ink: island.ink
            accent: Theme.primary
            locale: Config.formatLoc
            reveal: Math.max(0, Math.min(1, (island.clockProgress - 0.3) / 0.55))
            opacity: wheel.reveal
        }
    }

    // One shadow per island: a single shadow around the root would smear the
    // empty space between them. The clock's rides above the music so the
    // expanding pill still reads as floating over it.
    RectangularShadow {
        anchors.fill: music
        radius: music.radius
        blur: 30
        spread: 2
        offset: Qt.vector2d(0, 6)
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: island.trackPresence
        z: -1
    }
    RectangularShadow {
        anchors.fill: clockPill
        radius: clockPill.radius
        blur: 24
        spread: 2
        offset: Qt.vector2d(0, 4)
        color: Qt.rgba(0, 0, 0, 0.6)
        z: 1
    }
}
