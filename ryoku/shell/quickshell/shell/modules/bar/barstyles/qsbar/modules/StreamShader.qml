pragma ComponentBehavior: Bound
import QtQuick
import shell.services

// GPU renderer for the qsbar gap animation (barAnim drift modes 1-6). The same
// procedural motion ParticleStream draws with a threaded Canvas, evaluated per
// pixel by stream.frag instead of rasterised on the CPU: one ShaderEffect per
// bar gap, a single clock float drives every mode, and `mode` selects the effect
// branch. The shader itself costs ~0 CPU; what costs is every frame it asks for,
// because each one is a compositor frame (see the clock below). reduce-motion /
// Power Saver unload it at the LazyLoader. cava is claimed only while audio
// plays, so a silent desktop pays nothing for it. The stateful modes (7 reactor,
// 8 quotes) keep the Canvas-based ParticleStream.
Item {
    id: root

    required property var  theme
    required property Item layout    // ReactorLayer: pillRuns, runRightEdge/Left()
    property string monitor: ""
    property int mode: (theme && theme.barAnim !== undefined) ? theme.barAnim : 1

    readonly property bool audioLive:  Media.playing
    readonly property real audioLevel: AudioBars.active ? Math.min(1, AudioBars.energy) : 0
    onAudioLiveChanged:      AudioBars.setActive(root, root.audioLive)
    Component.onCompleted:   AudioBars.setActive(root, root.audioLive)
    Component.onDestruction: AudioBars.setActive(root, false)

    // The clock. Not a FrameAnimation: while one runs the scene graph renders and
    // commits a frame every vsync whether or not the picture changed, and every
    // commit is a compositor frame. Measured on a 165 Hz hybrid laptop, that alone
    // held Hyprland at ~38% of a core and the shell at ~26%, silent, all day (#60
    // again, on the GPU path this time). So the picture is advanced by a Timer, only
    // as often as it needs to change, at ParticleStream's own paces: its
    // fullMotionTick while audio drives the stream (60 fps for the fast positional
    // modes 5 and 6, 30 fps otherwise), its driftTick (20 fps) for the silent drift,
    // both slowed by pollFactor on battery / Saver / Game Mode. The silent drift is
    // not promoted to full rate on Performance the way the Canvas does it: on a
    // full-screen layer that promotion is the whole cost. And it runs only where
    // the power profile allows it (Perf.ambientMotion: Performance), the same rule
    // ParticleStream applies, so a silent bar sits still on Balanced and Saver,
    // like caelestia and end-4. Music still animates the bar on every profile.
    // `time` is in seconds, matching stream.frag's time units.
    readonly property bool streamLive: root.visible && (root.audioLive || Perf.ambientMotion)
    readonly property int motionTick: (root.mode === 5 || root.mode === 6) ? 16 : 33
    readonly property int driftTick: 50
    property real time: 0
    Timer {
        id: clock
        interval: (root.audioLive ? root.motionTick : root.driftTick) * Perf.pollFactor
        repeat: true
        running: root.streamLive
        onTriggered: root.time += interval / 1000
    }

    // One shader instance per gap between widget clusters. gapX puts every pixel
    // on the shared global dot grid, so the stream stays continuous across gaps.
    Repeater {
        model: root.layout && root.layout.pillRuns
               ? Math.max(0, root.layout.pillRuns.length - 1) : 0

        delegate: ShaderEffect {
            id: gapFx
            required property int index
            readonly property var runs: root.layout.pillRuns
            // Reactive: ReactorLayer.runs re-derives when a cluster moves (a widget
            // appears, the clock ticks), so these edges follow the live layout.
            readonly property real x1: root.layout.runRightEdge(runs[index].e)
            readonly property real x2: root.layout.runLeftEdge(runs[index + 1].s)

            x: x1
            y: 0
            width: Math.max(0, x2 - x1)
            height: root.height
            // hidden when not live: a stopped clock clears the gap instead of freezing the last frame
            visible: root.streamLive && width > 10 && height > 0

            property real time: root.time
            property real aud:  root.audioLevel
            property real gapX: x1
            property real gapW: width
            property real gapH: height
            property real gapIndex: index
            property real mode: root.mode
            property vector4d seal: (root.theme && root.theme.seal)
                ? Qt.vector4d(root.theme.seal.r, root.theme.seal.g, root.theme.seal.b, 1.0)
                : Qt.vector4d(1.0, 1.0, 1.0, 1.0)

            fragmentShader: "../shaders/stream.frag.qsb"
        }
    }
}
