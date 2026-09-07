pragma ComponentBehavior: Bound

import QtQuick
import ".."
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// Dictation card: grown from the bottom-centre edge on Super+`, framed like the
// music card. Voxtype records and types into the focused app; this card only
// visualises it -- a big mirrored waveform driven by VoiceBars (cava on the live
// mic), so it lies flat in silence and swells, glowing in the frame accent, as
// you speak. It grabs NOTHING (no keyboard, no focus) so the keystrokes land in
// your app, not here; the daemon shows and hides it. When dictation is off it
// flashes a quiet note and auto-dismisses.
Item {
    id: root

    property real s: 1
    property bool open: false
    property bool off: false
    property bool capture: false
    signal closeRequested()

    readonly property real pad: 15 * root.s
    readonly property color ink: Theme.ink(Theme.effectiveSurface)
    readonly property color inkDim: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)

    // cava runs only while genuinely open and dictation active (the capture gate
    // keeps it silent when opened in the off state and stops it as the close
    // begins, never during the melt).
    onCaptureChanged: VoiceBars.active = root.capture
    Component.onCompleted: VoiceBars.active = root.capture
    Component.onDestruction: VoiceBars.active = false

    // mic energy 0..1 from the live spectrum: the mic glyph and the wave brighten
    // as the user speaks and rest dim.
    readonly property real energy: {
        const l = VoiceBars.levels;
        if (!l || l.length === 0)
            return 0;
        let sum = 0;
        for (let i = 0; i < l.length; i++)
            sum += l[i];
        return Math.min(1, (sum / l.length) * 2.6);
    }

    implicitWidth: 380 * root.s
    implicitHeight: (root.off ? offCol.implicitHeight : liveCol.implicitHeight) + root.pad * 2

    PopoutCard { anchors.fill: parent }

    // ── live dictation ────────────────────────────────────────────────────────
    Column {
        id: liveCol
        visible: !root.off
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: 11 * root.s

        // header: mic (energy-reactive), status, a pulsing record dot.
        Item {
            width: parent.width
            height: 20 * root.s

            GlyphIcon {
                id: micIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 17 * root.s
                height: width
                name: "mic"
                stroke: 1.8
                color: Qt.tint(root.inkDim, Qt.alpha(Theme.primary, root.energy))
                scale: 1 + 0.12 * root.energy
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.left: micIcon.right
                anchors.leftMargin: 9 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Listening…")
                color: root.ink
                font.family: Theme.fontPrimary
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6 * root.s
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.s
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    SequentialAnimation on opacity {
                        running: root.open && !root.off
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.3; to: 1; duration: 700; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1; to: 0.3; duration: 700; easing.type: Easing.InOutQuad }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("REC")
                    color: root.inkDim
                    font.family: Theme.mono
                    font.pixelSize: 9 * root.s
                    font.letterSpacing: 1.5
                }
            }
        }

        // the hero: a big mirrored waveform of the live mic, glowing in accent.
        Canvas {
            id: wave
            width: parent.width
            height: 58 * root.s
            property real phase: 0

            function level(t) {
                const l = VoiceBars.levels;
                const n = l ? l.length : 0;
                if (n === 0)
                    return 0;
                const p = t * (n - 1);
                const i = Math.floor(p);
                const f = p - i;
                const a = l[i];
                const b = i + 1 < n ? l[i + 1] : l[i];
                return a + (b - a) * f;
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = width;
                const h = height;
                const mid = h / 2;
                const maxAmp = h * 0.46;
                const e = root.energy;

                // envelope points: level-driven amplitude, tapered to the ends so
                // the shape closes, with a gentle phase drift for life.
                const pts = [];
                for (let x = 0; x <= w; x += 2) {
                    const t = w > 0 ? x / w : 0;
                    const taper = Math.sin(Math.PI * t);
                    const flow = 0.88 + 0.12 * Math.sin(x * 0.055 + phase);
                    pts.push({ x: x, a: level(t) * maxAmp * taper * flow });
                }

                // filled body between the mirrored envelopes.
                ctx.beginPath();
                for (let i = 0; i < pts.length; i++) {
                    const y = mid - pts[i].a;
                    if (i === 0) ctx.moveTo(pts[i].x, y); else ctx.lineTo(pts[i].x, y);
                }
                for (let i = pts.length - 1; i >= 0; i--)
                    ctx.lineTo(pts[i].x, mid + pts[i].a);
                ctx.closePath();
                ctx.fillStyle = Qt.alpha(Theme.primary, 0.08 + 0.20 * e);
                ctx.fill();

                // resting centre line.
                ctx.lineWidth = 2 * root.s;
                ctx.lineCap = "round";
                ctx.strokeStyle = Qt.alpha(Theme.primary, 0.22);
                ctx.beginPath();
                ctx.moveTo(0, mid);
                ctx.lineTo(w, mid);
                ctx.stroke();

                // bright mirrored crests.
                ctx.lineWidth = 2.4 * root.s;
                ctx.lineJoin = "round";
                ctx.strokeStyle = Qt.alpha(Theme.primary, 0.45 + 0.55 * e);
                for (let s = -1; s <= 1; s += 2) {
                    ctx.beginPath();
                    for (let i = 0; i < pts.length; i++) {
                        const y = mid + s * pts[i].a;
                        if (i === 0) ctx.moveTo(pts[i].x, y); else ctx.lineTo(pts[i].x, y);
                    }
                    ctx.stroke();
                }
            }

            Timer {
                interval: 33
                running: root.open && !root.off
                repeat: true
                onTriggered: {
                    wave.phase = (wave.phase + 0.2) % 6.28318;
                    wave.requestPaint();
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Speak now · Super + ` to stop")
            color: root.inkDim
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.letterSpacing: 0.5
        }
    }

    // ── dictation off ─────────────────────────────────────────────────────────
    Row {
        id: offCol
        visible: root.off
        anchors.centerIn: parent
        spacing: 9 * root.s
        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: width
            name: "mic-off"
            stroke: 1.7
            color: root.inkDim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Dictation off")
            color: root.inkDim
            font.family: Theme.fontPrimary
            font.pixelSize: 13 * root.s
            font.weight: Font.DemiBold
        }
    }

    Timer {
        running: root.off && root.open
        interval: 1800
        onTriggered: root.closeRequested()
    }
}
