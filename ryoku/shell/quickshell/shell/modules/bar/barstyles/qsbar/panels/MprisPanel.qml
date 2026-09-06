import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../modules"
import Ryoku.Ui.Singletons

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

    // ── pick a REAL active player ───────────────────────────────────
    // Selection (incl. ghost-filtering) lives in MprisSelect so the bar
    // widget and this panel always agree on the active player.
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

    // ── live position polling (for the progress bar) ────────────────
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

    // ── visualizer state ────────────────────────────────────────────
    readonly property int bands: 12
    property var levels:  []     // smoothed, what we draw
    property var targets: []     // raw cava input
    property real phase: 0       // drives the synthetic idle wave
    // A named theme may ship a hand-picked spectrum gradient; null otherwise.
    property var cavaTheme: null

    // A static named theme keeps its own gradient; otherwise the live wallpaper
    // palette drives it as a binding, so a wallpaper change retints the spectrum
    // instead of freezing it on the panel's load-time colours.
    readonly property var cavaPalette: (root._namedPalette && cavaTheme && cavaTheme.length >= 2)
        ? cavaTheme
        : [root.color06, root.color04, root.color05,
           root.color07, root.color03, root.color01]

    function parseCavaTheme(raw) {
        var text = String(raw || "")
        var colors = []
        for (var i = 1; i <= 16; i++) {
            var re = new RegExp("^\\s*gradient_color_" + i
                + "\\s*=\\s*['\\\"]?\\s*(#[0-9a-fA-F]{6,8})", "m")
            var match = text.match(re)
            if (match) colors.push(match[1])
        }
        cavaTheme = colors.length >= 2 ? colors : null
    }

    Component.onCompleted: {
        var a = [], b = []
        for (var i = 0; i < bands; i++) { a.push(0.06); b.push(0.0) }
        levels = a; targets = b
    }

    FileView {
        id: cavaThemeFile
        path: root.omarchyCurrentRoot + "/theme/cava_theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: mprisPanel.parseCavaTheme(cavaThemeFile.text())
        onLoadFailed: mprisPanel.cavaTheme = null
    }

    property real reveal: root.mprisVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.mprisVisible ? 160 : 120
            easing.type: root.mprisVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.mprisVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── cava: real system-audio spectrum (runs only while playing) ──
    // Native PipeWire capture avoids the Pulse compatibility buffer. CAVA's
    // default noise reduction is intentionally very slow (77); a lower value
    // plus direct samples keeps the panel visually close to the audible beat.
    Process {
        id: cava
        running: mprisPanel.visible && mprisPanel.playing
        command: ["bash", "-c",
            "command -v cava >/dev/null 2>&1 || exit 0; " +
            "exec cava -p <(printf '%s\\n' " +
            "'[general]' 'bars = 12' 'framerate = 30' 'autosens = 1' 'sleep_timer = 0' " +
            "'[input]' 'method = pipewire' 'source = auto' " +
            "'[output]' 'method = raw' 'raw_target = /dev/stdout' " +
            "'data_format = ascii' 'ascii_max_range = 100' " +
            "'[smoothing]' 'monstercat = 0' 'waves = 0' 'noise_reduction = 20')"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            // Drive the bars directly from CAVA; no extra QML smoothing or lag.
            onRead: function(line) {
                if (!mprisPanel.playing) return
                var parts = line.split(";")
                var previous = mprisPanel.levels
                var out = []
                for (var i = 0; i < mprisPanel.bands; i++) {
                    var v = parseInt(parts[i]); v = isNaN(v) ? 0 : Math.min(1, v / 100)
                    var current = previous[i] === undefined ? 0 : previous[i]
                    // Fast attack keeps the beat punctual; a gentler release
                    // removes the nervous sample-to-sample flicker.
                    var response = v >= current ? 0.72 : 0.24
                    out.push(current + (v - current) * response)
                }
                mprisPanel.levels = out
            }
        }
    }

    // ── idle wave: only when active+paused (cava drives the bars while playing) ─
    Timer {
        interval: 33; repeat: true
        running: mprisPanel.visible && mprisPanel.active && !mprisPanel.playing
        onTriggered: {
            mprisPanel.phase += 0.12
            var out = []
            var lv = mprisPanel.levels
            for (var i = 0; i < mprisPanel.bands; i++) {
                var goal
                if (mprisPanel.active) {
                    goal = 0.05                 // paused → flat rest
                } else {
                    // no song: gentle symmetric idle wave
                    var d = Math.abs(i - (mprisPanel.bands - 1) / 2)
                    goal = 0.10 + 0.09 * (0.5 + 0.5 * Math.sin(mprisPanel.phase - i * 0.55))
                                * (1 - d / mprisPanel.bands)
                }
                var cur = lv[i] === undefined ? 0.06 : lv[i]
                out.push(cur + (goal - cur) * 0.25)   // gentle ease for the idle state
            }
            mprisPanel.levels = out
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.mprisVisible = false }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
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
            anchors.margins: 12
            spacing: 8

            // ── header ──
            Item {
                width: parent.width
                height: 24
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

            // ── ACTIVE: art + track info ──
            Row {
                width: parent.width
                spacing: 10
                visible: mprisPanel.active

                // album art (falls back to a music glyph)
                Rectangle {
                    width: 52; height: 52; radius: 5
                    color: root.fillActive
                    clip: true
                    Image {
                        id: panelCoverArt
                        anchors.fill: parent
                        source: artwork.source
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    IconText {
                        anchors.centerIn: parent
                        visible: panelCoverArt.status !== Image.Ready
                        text: ""   // music_note
                        font.pixelSize: 26
                        color: root.seal
                    }
                }

                Column {
                    width: parent.width - 62
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    UiText {
                        width: parent.width
                        text: mprisPanel.player ? (mprisPanel.player.trackTitle || "Unknown") : ""
                        color: root.ink; font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    UiText {
                        width: parent.width
                        text: mprisPanel.player ? (mprisPanel.player.trackArtist || "") : ""
                        color: root.sumiHi; font.family: root.mono; font.pixelSize: 11
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                    UiText {
                        width: parent.width
                        text: mprisPanel.player ? (mprisPanel.player.trackAlbum || "") : ""
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
                        font.family: root.mono; font.pixelSize: 10
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
            }

            // ── progress bar (only when the player reports a length) ──
            Item {
                width: parent.width
                height: 14
                visible: mprisPanel.active && mprisPanel.curLen > 0
                Rectangle {
                    id: track
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    height: 4; radius: 2
                    color: root.fillActive
                    Rectangle {
                        height: parent.height; radius: 2
                        color: root.seal
                        width: parent.width * (mprisPanel.curLen > 0
                            ? Math.min(1, mprisPanel.curPos / mprisPanel.curLen) : 0)
                        Behavior on width { NumberAnimation { duration: 450 } }
                    }
                }
                UiText {
                    anchors.left: parent.left; anchors.top: track.bottom; anchors.topMargin: 2
                    text: mprisPanel.fmtTime(mprisPanel.curPos)
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 9
                }
                UiText {
                    anchors.right: parent.right; anchors.top: track.bottom; anchors.topMargin: 2
                    text: mprisPanel.fmtTime(mprisPanel.curLen)
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 9
                }
            }

            // ── visualizer + no-song message (shared canvas) ──
            Item {
                width: parent.width
                height: 40

                Canvas {
                    id: viz
                    anchors.fill: parent
                    visible: mprisPanel.active
                    opacity: mprisPanel.playing ? 1.0 : 0.5
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var lv = mprisPanel.levels
                        if (!lv || lv.length === 0) return
                        var n = lv.length
                        var bw = 5
                        var totalGap = width - n * bw
                        var gap = totalGap / (n + 1)
                        var maxH = height - 2
                        var r = bw / 2
                        var palette = mprisPanel.cavaPalette
                        var gradient = ctx.createLinearGradient(0, height, 0, 0)
                        if (palette && palette.length > 1) {
                            for (var stop = 0; stop < palette.length; stop++)
                                gradient.addColorStop(stop / (palette.length - 1), palette[stop])
                            ctx.fillStyle = gradient
                        } else {
                            ctx.fillStyle = root.seal
                        }
                        for (var i = 0; i < n; i++) {
                            var bh = Math.max(bw, lv[i] * maxH)
                            var x = gap + i * (bw + gap)
                            var y = height - bh
                            ctx.beginPath()
                            ctx.moveTo(x + r, y)
                            ctx.lineTo(x + bw - r, y)
                            ctx.arcTo(x + bw, y, x + bw, y + r, r)
                            ctx.lineTo(x + bw, y + bh)
                            ctx.lineTo(x, y + bh)
                            ctx.lineTo(x, y + r)
                            ctx.arcTo(x, y, x + r, y, r)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                    Connections {
                        target: mprisPanel
                        function onLevelsChanged() { viz.requestPaint() }
                        function onCavaPaletteChanged() { viz.requestPaint() }
                    }
                }

                // no-song label rides on top of the idle wave
                Column {
                    anchors.centerIn: parent
                    spacing: 1
                    visible: !mprisPanel.active
                    UiText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("No song playing")
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    UiText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("no active player")
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
            }

            // ── controls ──
            Row {
                visible: mprisPanel.active
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                IconText {
                    text: ""
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                    color: (mprisPanel.player && mprisPanel.player.canGoPrevious) ? root.ink : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.previous() }
                }
                IconText {
                    text: mprisPanel.playing ? "" : ""
                    font.pixelSize: 24
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.seal
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.togglePlaying() }
                }
                IconText {
                    text: ""
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                    color: (mprisPanel.player && mprisPanel.player.canGoNext) ? root.ink : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.next() }
                }
            }
        }
    }
}
