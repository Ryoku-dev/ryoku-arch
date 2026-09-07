pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

// A live preview of the desktop audio visualiser for the Desktop page's
// Visualizer subtab. It renders through Ryoku.Ui.SpectrumField -- the same
// item, and the same shader, the desktop draws with -- so the preview is the
// real geometry and can never drift into a second implementation of the looks.
//
// The hub has no audio feed, so a synthetic signal stands in for cava: a
// bass-heavy travelling wave advanced by a ~30fps Timer, pushed into the
// field's `levels`. It reads the live draft, so the picture retunes as the
// knobs are edited.
//
// Monochrome by design -- app content carries no accent -- the ramp is eight
// ink stops from Tokens, so the preview is the desktop look in the hub's own
// palette. Polar looks are aimed by dragging on the stage.
Item {
    id: root

    property var hub

    implicitHeight: 260
    // folds flat out of the layout on the General subtab (the page toggles
    // `visible`); the shared extras slot measures childrenRect, so the height
    // must actually reach 0 or an empty gap would push the settings down.
    height: visible ? implicitHeight : 0

    // ── live draft reads (defaults mirror vizA in Hub.qml) ──────────────────
    readonly property var d: (root.hub && root.hub.draft) ? root.hub.draft : ({})
    function pick(k, dflt) { var v = root.d[k]; return v === undefined ? dflt : v; }

    readonly property bool vEnabled: root.pick("enabled", true)
    // `circle` is the old id for the orb look; any other unknown style the field
    // itself resolves back to bars, so a stale draft never previews blank.
    readonly property string vStyle: {
        var s = root.pick("style", "bars");
        if (s === "circle") s = "orb";
        return field.styles.indexOf(s) >= 0 ? s : "bars";
    }
    readonly property string vGrow: root.pick("grow", "up")
    readonly property real vAngle: root.pick("angle", 0)
    readonly property real vTiltX: root.pick("tiltX", 0)
    readonly property real vTiltY: root.pick("tiltY", 0)
    readonly property string vShape: root.pick("shape", "rounded")
    readonly property bool vMirror: root.pick("mirror", false)
    readonly property bool vPeakCaps: root.pick("peaks", false)
    readonly property int vBars: Math.max(2, Math.min(128, Math.round(root.pick("bars", 64))))
    readonly property int vSeg: Math.max(3, Math.min(24, Math.round(root.pick("segments", 10))))
    readonly property real vThick: Math.max(0.1, Math.min(1, root.pick("thickness", 0.58)))
    readonly property real vReflection: Math.max(0, Math.min(1, root.pick("reflection", 0.1)))
    readonly property real vBloom: Math.max(0, Math.min(1, root.pick("bloom", 0.6)))
    readonly property real vSpin: root.pick("spin", 0)
    // the look's box, the one geometry it has
    readonly property real vX: root.pick("x", 0)
    readonly property real vY: root.pick("y", 0.58)
    readonly property real vW: root.pick("w", 1)
    readonly property real vH: root.pick("h", 0.42)

    // ── synthetic motion ────────────────────────────────────────────────────
    // no audio in the hub, so a travelling wave stands in for cava. one phase,
    // nudged each frame; the field repushes its band levels when they change.
    property real phase: 0
    Timer {
        interval: Math.round(1000 / 30)
        running: root.visible && root.vEnabled
        repeat: true
        onTriggered: root.phase += 0.09
    }

    // mirror folds the band order symmetric around the centre -- bass in the
    // middle -- exactly as the real renderer's srcIndex does.
    function srcIndex(i) {
        if (!root.vMirror)
            return i;
        var c = Math.floor(root.vBars / 2);
        return Math.max(0, Math.min(root.vBars - 1, Math.abs(i - c)));
    }
    // a band's 0..1 magnitude: a bass envelope, two drifting sines, an idle floor.
    function levelAt(i) {
        var n = Math.max(1, root.vBars);
        var s = root.srcIndex(i);
        var t = s / n;
        var env = Math.pow(1 - t, 1.35) * 0.9 + 0.1;
        var w1 = 0.5 + 0.5 * Math.sin(s * 0.5 - root.phase * 2.1);
        var w2 = 0.5 + 0.5 * Math.sin(s * 0.17 + root.phase * 1.3);
        var idle = 0.10 + 0.06 * Math.sin(s * 0.4 + root.phase);
        var v = env * (0.32 + 0.68 * (0.6 * w1 + 0.4 * w2));
        return Math.max(idle, Math.max(0.02, Math.min(1, v)));
    }
    // a signed -1..1 sample per band, tapered at the ends: the `line` trace.
    function signalAt(i) {
        var s = root.srcIndex(i);
        var t = s / Math.max(1, root.vBars);
        var win = Math.sin(Math.PI * t);
        var sig = Math.sin(t * Math.PI * 8 - root.phase * 3) * 0.6
                + Math.sin(t * Math.PI * 17 + root.phase * 2) * 0.3
                + Math.sin(t * Math.PI * 3 - root.phase * 1.5) * 0.5;
        return Math.max(-1, Math.min(1, sig * (0.35 + 0.65 * win)));
    }

    readonly property var vLevels: {
        var out = [];
        for (var i = 0; i < root.vBars; i++)
            // the shader reads `line` band slots as an oscilloscope sample, so
            // that look feeds a waveform swinging around the 0.5 midline rather
            // than a level rising from a floor as the bar looks do.
            out.push(root.vStyle === "line" ? 0.5 + 0.5 * root.signalAt(i)
                                            : root.levelAt(i));
        return out;
    }
    // peak holds sit a touch above the live level, for the caps look.
    readonly property var vPeaks: {
        var out = [];
        for (var i = 0; i < root.vBars; i++)
            out.push(Math.min(1, root.levelAt(i) + 0.08));
        return out;
    }
    // mean level, for the field's bloom and polar pulses.
    readonly property real vEnergy: {
        var sum = 0, n = root.vBars;
        for (var i = 0; i < n; i++) sum += root.levelAt(i);
        return n > 0 ? sum / n : 0;
    }
    // Colour follows the pinned choice so the preview matches the desktop: a
    // gradient sweeps colour into colour2, a single pin walks bass->treble, and
    // with neither pinned the hub draws in ink alone (app content carries no
    // accent), eight stops from dim to full ink for the shader to sweep.
    readonly property string vColor: "" + root.pick("color", "")
    readonly property string vColor2: "" + root.pick("color2", "")
    readonly property bool vHasColor: /^#[0-9a-fA-F]{6}$/.test(root.vColor)
    readonly property bool vHasColor2: /^#[0-9a-fA-F]{6}$/.test(root.vColor2)
    readonly property bool vGradient: root.pick("gradient", false) === true && root.vHasColor && root.vHasColor2
    readonly property var vRamp: {
        var out = [];
        var i, t;
        if (root.vGradient) {
            var g0 = Qt.color(root.vColor), g1 = Qt.color(root.vColor2);
            for (i = 0; i < 8; i++)
                out.push(Qt.tint(g0, Qt.rgba(g1.r, g1.g, g1.b, i / 7)));
            return out;
        }
        if (root.vHasColor) {
            var base = Qt.color(root.vColor);
            for (i = 0; i < 8; i++) {
                t = i / 7;
                var f = 1 + (t - 0.5) * 0.36;
                out.push(f >= 1 ? Qt.lighter(base, f) : Qt.darker(base, 1 / f));
            }
            return out;
        }
        var a = Tokens.inkDim, b = Tokens.ink;
        for (i = 0; i < 8; i++) {
            t = i / 7;
            out.push(Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                             a.b + (b.b - a.b) * t, 1));
        }
        return out;
    }

    // the frame: flat, one hairline, Tokens radius -- the hub is print.
    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: "transparent"
        border.width: Tokens.border
        border.color: Tokens.line
    }

    // header: the // PREVIEW_ mark the other surfaces wear, and a live readout.
    Row {
        id: header
        anchors { left: parent.left; top: parent.top; margins: Tokens.s4 }
        spacing: Tokens.s2
        Text {
            text: "//"
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: I18n.tr("PREVIEW_")
            color: Tokens.inkMuted
            font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackLabel
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Text {
        anchors { right: parent.right; top: parent.top; margins: Tokens.s4 }
        text: root.vStyle.toUpperCase() + " \u00b7 " + root.vBars
        color: Tokens.inkFaint
        font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
    }

    // the stage: the whole screen the spectrum sits on, full card width, so the
    // preview shows the surface a monitor would, not a strip along one edge.
    Item {
        id: stage
        anchors {
            left: parent.left; right: parent.right
            top: header.bottom; bottom: parent.bottom
            leftMargin: Tokens.s4; rightMargin: Tokens.s4
            topMargin: Tokens.s3; bottomMargin: Tokens.s4
        }
        clip: true

        // the real renderer: same item and shader the desktop draws with.
        SpectrumField {
            id: field
            anchors.fill: parent
            visible: root.vEnabled
            style: root.vStyle
            grow: root.vGrow
            angle: root.vAngle
            tiltX: root.vTiltX
            tiltY: root.vTiltY
            shape: root.vShape
            thickness: root.vThick
            reflection: root.vReflection
            glow: root.vBloom
            segments: root.vSeg
            peakCaps: root.vPeakCaps
            boxX: root.vX
            boxY: root.vY
            boxW: root.vW
            boxH: root.vH
            spin: root.vSpin
            energy: root.vEnergy
            fade: 1
            levels: root.vLevels
            peaks: root.vPeaks
            ramp: root.vRamp
        }

        // a calm ring marking the polar origin the drag moves.
        Rectangle {
            visible: root.vEnabled
            width: Tokens.s4; height: width; radius: width / 2
            color: "transparent"
            border.width: Tokens.border
            border.color: Tokens.lineStrong
            x: (root.vX + root.vW / 2) * stage.width - width / 2
            y: (root.vY + root.vH / 2) * stage.height - height / 2
        }

        // a monospace hint, shown only while a polar look can be aimed.
        Text {
            visible: root.vEnabled
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Tokens.s2 }
            text: I18n.tr("DRAG TO PLACE")
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackLabel
        }

        // Aim the polar looks: a drag anywhere on the stage sets the origin from
        // the pointer (clamped 0..1) through the same edit path the settings
        // rows use (root.hub.edit), so the desktop origin moves with the
        // preview. Edge looks are not placed, so the area is disabled for them;
        // preventStealing keeps the drag from scrolling the settings page.
        MouseArea {
            anchors.fill: parent
            enabled: root.vEnabled
            preventStealing: true
            onPressed: (m) => place(m.x, m.y)
            onPositionChanged: (m) => place(m.x, m.y)
            function place(x, y) {
                if (!root.hub || !root.hub.edit)
                    return;
                root.hub.edit("x", Math.max(-0.2, Math.min(1, x / width - root.vW / 2)));
                root.hub.edit("y", Math.max(-0.2, Math.min(1, y / height - root.vH / 2)));
            }
        }
    }

    // off state: a calm placeholder, no red -- the hub's hazard voice is
    // black and white and reads as more serious for it.
    Text {
        anchors.centerIn: stage
        visible: !root.vEnabled
        text: I18n.tr("VISUALIZER OFF")
        color: Tokens.inkMuted
        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
        font.weight: Font.Medium; font.letterSpacing: 2
    }
}
