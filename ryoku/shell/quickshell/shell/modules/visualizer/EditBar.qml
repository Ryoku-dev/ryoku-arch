pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The spectrum's editing bar, shown while a look is being placed, so a look is tuned
// where you can see it rather than in the Hub with the desktop behind a window.
//
// Fixed to an edge of the screen, never to the box: a readout of the thing being
// moved must not move with it. Controls come from Ryoku.Ui and metrics from Tokens;
// the tray is the Hub's gallery with the Hub's painter, so one catalogue draws what
// the eleven looks look like.
Item {
    id: bar

    // The box being placed, in screen px, so the bar can step out from under it.
    required property rect box

    signal done

    readonly property bool atTop: bar.box.y + bar.box.height > bar.height - 200
    readonly property alias trayOpen: tray.open
    readonly property alias colorOpen: colorPop.open

    // The colour the spectrum actually wears: a pinned one wins, else the live
    // wallpaper/theme accent the rest of the shell follows.
    readonly property color wallpaperColor: Scheme.accent
    readonly property color effectiveColor: Config.hasCustomColor ? Config.customColor : bar.wallpaperColor

    function closeTray() { tray.open = false; }
    function toggleTray() { tray.open = !tray.open; if (tray.open) colorPop.open = false; }
    function closeColor() { colorPop.open = false; }
    function toggleColor() {
        if (!colorPop.open) {
            colorPop.editing = "a";
            colorPop.seed(bar.effectiveColor);
            tray.open = false;
        }
        colorPop.open = !colorPop.open;
    }
    // Each drag/type lands on the stop being edited: the base colour, or the
    // gradient's second stop.
    function commitColor() {
        if (colorPop.editing === "b")
            Config.setColor2(colorPop.curHex);
        else
            Config.setColor(colorPop.curHex);
    }
    // "#RRGGBB" for a colour, the syntax visualizer.json stores.
    function hexOf(c) {
        return "#" + [c.r, c.g, c.b].map(function (x) {
            var s = Math.round(x * 255).toString(16);
            return s.length === 1 ? "0" + s : s;
        }).join("").toUpperCase();
    }

    anchors.fill: parent

    // The bar and the tray are laid out at their natural width, then scaled to
    // fit the surface: every control sits in one row (about 1900 logical px),
    // and a scaled display is narrower in logical px than in pixels (1600 at
    // 1.6x on a 2560-wide panel), so the row ran off both edges and the
    // right-hand controls were unreachable. Scaling keeps one layout and every
    // hit target in place; the origin is the edge the bar hangs from, so the
    // scaled plate keeps its inset and stays centred.
    function fit(w) { return Math.min(1, (bar.width - 2 * Tokens.s5) / Math.max(1, w)); }

    // --- the look tray --------------------------------------------------------
    Rectangle {
        id: tray
        property bool open: false

        x: Math.round((bar.width - width) / 2)
        // measured against the plate's SCALED extent, so the gap stays a token
        y: bar.atTop ? plate.y + plate.height * plate.scale + Tokens.s3
                     : plate.y + plate.height * (1 - plate.scale) - height - Tokens.s3
        width: gal.width + 2 * Tokens.s4
        height: gal.height + 2 * Tokens.s4
        scale: bar.fit(width)
        transformOrigin: bar.atTop ? Item.Top : Item.Bottom
        radius: Tokens.radius
        color: Qt.alpha(Tokens.paper, 0.94)
        border.width: Tokens.border
        border.color: Tokens.line
        visible: opacity > 0.01
        opacity: tray.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease } }

        // a shield: a click that misses a tile must not start a drag behind the tray
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Gallery {
            id: gal
            anchors.centerIn: parent
            width: 11 * 132 + 10 * 7
            painter: VizStyles
            options: VizStyles.styles.map(function (s) { return { key: s.key, origin: s.kind, draw: s.key }; })
            current: Config.styleId
            onChose: (k) => {
                Config.setStyle(k);
                tray.open = false;
            }
        }
    }

    // --- the bar --------------------------------------------------------------
    Rectangle {
        id: plate
        x: Math.round((bar.width - width) / 2)
        y: bar.atTop ? Tokens.s5 : Math.round(bar.height - height - Tokens.s5)
        width: col.width + 2 * Tokens.s5
        height: col.height + 2 * Tokens.s4
        scale: bar.fit(width)
        transformOrigin: bar.atTop ? Item.Top : Item.Bottom
        radius: Tokens.radius
        color: Qt.alpha(Tokens.paper, 0.94)
        border.width: Tokens.border
        border.color: Tokens.line

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
            id: col
            anchors.centerIn: parent
            spacing: Tokens.s3

            Row {
                id: controls
                spacing: Tokens.s5

                Group {
                    label: I18n.tr("VIZ")
                    Row {
                        spacing: Tokens.s2
                        Repeater {
                            model: Config.count
                            Rectangle {
                                id: vizDot
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 10
                                color: vizDot.index === Config.active ? Tokens.ink
                                    : (dotHov.hovered ? Tokens.tint16 : "transparent")
                                border.width: Tokens.border
                                border.color: vizDot.index === Config.active ? Tokens.ink : Tokens.lineStrong
                                Behavior on color { ColorAnimation { duration: Tokens.snap } }
                                Text {
                                    anchors.centerIn: parent
                                    text: vizDot.index + 1
                                    color: vizDot.index === Config.active ? Tokens.paper : Tokens.inkMuted
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fSmall
                                    font.weight: Font.DemiBold
                                }
                                HoverHandler { id: dotHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Config.setActive(vizDot.index) }
                            }
                        }
                        Btn {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+"
                            compact: true
                            armed: Config.count < Config.maxVisualizers
                            onAct: Config.addVisualizer()
                        }
                        Btn {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u2212"
                            compact: true
                            armed: Config.count > 1
                            onAct: if (Config.count > 1) Config.removeVisualizer(Config.active)
                        }
                    }
                }

                Group {
                    // A light caution: each visualiser is its own full-screen pass.
                    label: I18n.tr("RAM")
                    Value {
                        text: "~" + Config.ramEstimateMB + " MB"
                        color: Config.count >= 3 ? Tokens.alert : Tokens.inkMuted
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("LOOK")
                    // Drawn, because a name alone does not say what a ribbon is.
                    Rectangle {
                        width: 176
                        height: 30
                        radius: Tokens.radius
                        color: tray.open ? Tokens.tint16 : (lookHov.hovered ? Tokens.tint10 : "transparent")
                        border.width: Tokens.border
                        border.color: tray.open ? Tokens.ink : (lookHov.hovered ? Tokens.lineStrong : Tokens.line)
                        Behavior on color { ColorAnimation { duration: Tokens.snap } }

                        Row {
                            anchors { left: parent.left; leftMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                            spacing: Tokens.s2
                            Canvas {
                                id: art
                                width: 46
                                height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                onPaint: {
                                    var c = getContext("2d");
                                    c.reset();
                                    VizStyles.draw(c, Config.styleId, width, height, 0.98, 0.45);
                                }
                                Component.onCompleted: art.requestPaint()
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Config.styleId
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fRow
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                            text: tray.open ? "\u25b4" : "\u25be"
                            color: Tokens.inkDim
                            font.pixelSize: 11
                        }
                        HoverHandler { id: lookHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: bar.toggleTray() }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (w) => Config.cycleStyle(w.angleDelta.y > 0 ? 1 : -1)
                        }
                        Connections {
                            target: Config
                            function onStyleIdChanged() { art.requestPaint(); }
                        }
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("COLOR")
                    // A swatch that reads AUTO while following the wallpaper, or the
                    // pinned hex; it opens the picker below the bar.
                    Rectangle {
                        width: 108
                        height: 30
                        radius: Tokens.radius
                        color: colorPop.open ? Tokens.tint16 : (colHov.hovered ? Tokens.tint10 : "transparent")
                        border.width: Tokens.border
                        border.color: colorPop.open ? Tokens.ink : (colHov.hovered ? Tokens.lineStrong : Tokens.line)
                        Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        Row {
                            anchors { left: parent.left; leftMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                            spacing: Tokens.s2
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                radius: Tokens.radius
                                clip: true
                                color: bar.effectiveColor
                                border.width: Tokens.border
                                border.color: Tokens.lineStrong
                                Rectangle {
                                    anchors.fill: parent
                                    visible: Config.gradient
                                    radius: Tokens.radius
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Config.customColor }
                                        GradientStop { position: 1; color: Config.color2Value }
                                    }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Config.gradient ? I18n.tr("GRADIENT")
                                    : (Config.hasCustomColor ? Config.colorHex : I18n.tr("AUTO"))
                                color: Tokens.ink
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fRow
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: Tokens.s2; verticalCenter: parent.verticalCenter }
                            text: colorPop.open ? "\u25b4" : "\u25be"
                            color: Tokens.inkDim
                            font.pixelSize: 11
                        }
                        HoverHandler { id: colHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: bar.toggleColor() }
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("BANDS")
                    Row {
                        spacing: Tokens.s2
                        Step {
                            anchors.verticalCenter: parent.verticalCenter
                            value: Config.bars
                            from: 16
                            to: 128
                            onModified: (v) => Config.setBars(v)
                        }
                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Config.bars
                        }
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("MIRROR")
                    dim: !Config.mirrorApplies
                    Sw {
                        on: Config.mirror
                        onToggled: if (Config.mirrorApplies) Config.toggleMirror()
                    }
                }
                Group {
                    label: I18n.tr("PEAKS")
                    dim: !Config.peaksApply
                    Sw {
                        on: Config.peaks
                        onToggled: if (Config.peaksApply) Config.togglePeaks()
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("GAIN")
                    Row {
                        spacing: Tokens.s2
                        Slid {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            value: Config.gain
                            from: 0.5
                            to: 2
                            onModified: (v) => Config.setGain(v)
                        }
                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(Config.gain * 100) + "%"
                        }
                    }
                }
                Group {
                    label: I18n.tr("SMOOTHING")
                    Row {
                        spacing: Tokens.s2
                        Slid {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            value: Config.smoothing
                            from: 0
                            to: 1
                            onModified: (v) => Config.setSmoothing(v)
                        }
                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(Config.smoothing * 100) + "%"
                        }
                    }
                }

                Rule {}

                Group {
                    label: I18n.tr("ANGLE")
                    Row {
                        spacing: Tokens.s2
                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(Config.angle) + "\u00b0"
                        }
                        Btn {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("SQUARE")
                            compact: true
                            armed: Math.round(Config.angle) !== 0
                            onAct: Config.rotate(0)
                        }
                    }
                }

                Group {
                    // One group, two axes: a lean is one idea.
                    label: I18n.tr("LEAN")
                    Row {
                        spacing: Tokens.s2
                        Slid {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72
                            value: Config.tiltX
                            from: -Config.tiltMax
                            to: Config.tiltMax
                            onModified: (v) => Config.setTiltX(v)
                        }
                        Slid {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72
                            value: Config.tiltY
                            from: -Config.tiltMax
                            to: Config.tiltMax
                            onModified: (v) => Config.setTiltY(v)
                        }
                        Value {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(Config.tiltX) + "\u00b0 " + Math.round(Config.tiltY) + "\u00b0"
                        }
                        Btn {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("LEVEL")
                            compact: true
                            armed: Math.round(Config.tiltX) !== 0 || Math.round(Config.tiltY) !== 0
                            onAct: Config.levelTilt()
                        }
                    }
                }
                Group {
                    label: I18n.tr("SIZE")
                    Value {
                        text: Math.round(Config.w * 100) + "\u00d7" + Math.round(Config.h * 100) + "%"
                    }
                }

                Rule {}

                Group {
                    label: ""
                    Row {
                        spacing: Tokens.s2
                        Btn {
                            text: I18n.tr("FLIP")
                            onAct: Config.flip()
                        }
                        Btn {
                            text: I18n.tr("DONE")
                            primary: true
                            onAct: bar.done()
                        }
                    }
                }
            }

            // Under a hairline: an instruction is not a control, and outside the
            // plate it was unreadable over a picture.
            Rectangle {
                width: controls.width
                height: Tokens.border
                color: Tokens.lineSoft
            }
            Text {
                // Phrase by phrase, so each is a translatable unit.
                text: [I18n.tr("drag to move"), I18n.tr("corner to size"),
                       I18n.tr("dot to turn"), I18n.tr("scroll to resize"),
                       "f " + I18n.tr("flip"), "m " + I18n.tr("mirror"),
                       "r " + I18n.tr("square")].join("     ")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fMicro
                font.letterSpacing: Tokens.trackLabel
            }
        }
    }

    // --- the colour picker ----------------------------------------------------
    // The shell's paper-and-ink picker, inline under the bar: drag the square for
    // saturation and value, drag the rail for hue, or type a #hex. AUTO drops the
    // pin and follows the wallpaper again, the way every other role does.
    Rectangle {
        id: colorPop
        property bool open: false
        property real hh: 0
        property real ss: 1
        property real vv: 1
        // which stop the square/rail/hex edits: the base "a" or the gradient's "b".
        property string editing: "a"
        // Turning a gradient on needs both stops to exist, or it cannot paint; pin
        // the current effective colour as the base and a lighter twin as the second.
        function ensureStops() {
            if (!Config.hasCustomColor)
                Config.setColor(bar.hexOf(bar.effectiveColor));
            if (!Config.hasColor2)
                Config.setColor2(bar.hexOf(Qt.lighter(bar.effectiveColor, 1.5)));
        }
        function setGradient(on) {
            if (on)
                colorPop.ensureStops();
            Config.setGradient(on);
            if (!on)
                colorPop.selectStop("a");
        }
        function selectStop(which) {
            colorPop.editing = which;
            colorPop.seed(which === "b" ? Config.color2Value : Config.customColor);
        }
        readonly property color cur: Qt.hsva(colorPop.hh, colorPop.ss, colorPop.vv, 1)
        readonly property string curHex: bar.hexOf(colorPop.cur)

        function seed(c) {
            colorPop.hh = c.hsvHue < 0 ? 0 : c.hsvHue;
            colorPop.ss = c.hsvSaturation;
            colorPop.vv = c.hsvValue;
        }

        x: Math.round((bar.width - width) / 2)
        y: bar.atTop ? plate.y + plate.height + Tokens.s3 : plate.y - height - Tokens.s3
        width: 244
        height: pick.height + 2 * Tokens.s4
        radius: Tokens.radius
        color: Qt.alpha(Tokens.paper, 0.96)
        border.width: Tokens.border
        border.color: Tokens.line
        visible: opacity > 0.01
        opacity: colorPop.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease } }

        // a shield so a miss does not start a placement drag on the surface behind
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

        Column {
            id: pick
            anchors.centerIn: parent
            width: parent.width - 2 * Tokens.s4
            spacing: Tokens.s3

            // Two stops and a gradient switch: the picker below edits the selected
            // stop; a gradient sweeps stop A into stop B across the spectrum.
            Item {
                width: parent.width
                height: 28
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: Tokens.s2
                    Sw {
                        anchors.verticalCenter: parent.verticalCenter
                        on: Config.gradient
                        onToggled: colorPop.setGradient(!Config.gradient)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("GRADIENT")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny
                        font.letterSpacing: Tokens.trackMark
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: Tokens.s2
                    Rectangle {
                        width: 26
                        height: 26
                        radius: Tokens.radius
                        color: Config.customColor
                        border.width: colorPop.editing === "a" ? 2 : Tokens.border
                        border.color: colorPop.editing === "a" ? Tokens.ink : Tokens.lineStrong
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: colorPop.selectStop("a") }
                    }
                    Rectangle {
                        visible: Config.gradient
                        width: 26
                        height: 26
                        radius: Tokens.radius
                        color: Config.color2Value
                        border.width: colorPop.editing === "b" ? 2 : Tokens.border
                        border.color: colorPop.editing === "b" ? Tokens.ink : Tokens.lineStrong
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: colorPop.selectStop("b") }
                    }
                }
            }

            Item {
                id: sv
                width: parent.width
                height: 140
                Rectangle { anchors.fill: parent; radius: Tokens.radius; color: Qt.hsva(colorPop.hh, 1, 1, 1) }
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ffffff" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radius
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: "#000000" }
                    }
                }
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "transparent"
                    border.width: 2
                    border.color: colorPop.vv > 0.5 ? "#000000" : "#ffffff"
                    x: colorPop.ss * sv.width - 6
                    y: (1 - colorPop.vv) * sv.height - 6
                }
                MouseArea {
                    anchors.fill: parent
                    function set(mx, my) {
                        colorPop.ss = Math.max(0, Math.min(1, mx / width));
                        colorPop.vv = Math.max(0, Math.min(1, 1 - my / height));
                        bar.commitColor();
                    }
                    onPressed: (e) => set(e.x, e.y)
                    onPositionChanged: (e) => { if (pressed) set(e.x, e.y); }
                }
            }

            Item {
                id: hueRail
                width: parent.width
                height: 14
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.000; color: "#ff0000" }
                        GradientStop { position: 0.167; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.500; color: "#00ffff" }
                        GradientStop { position: 0.667; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1.000; color: "#ff0000" }
                    }
                }
                Rectangle {
                    width: 4
                    height: parent.height + 6
                    y: -3
                    x: Math.max(0, Math.min(hueRail.width - width, colorPop.hh * hueRail.width - 2))
                    color: "#ffffff"
                    border.width: 1
                    border.color: "#000000"
                }
                MouseArea {
                    anchors.fill: parent
                    function set(mx) { colorPop.hh = Math.max(0, Math.min(1, mx / width)); bar.commitColor(); }
                    onPressed: (e) => set(e.x)
                    onPositionChanged: (e) => { if (pressed) set(e.x); }
                }
            }

            Row {
                width: parent.width
                spacing: Tokens.s2
                Rectangle {
                    id: hexBox
                    width: parent.width - autoBtn.width - Tokens.s2
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: hexField.activeFocus ? 2 : Tokens.border
                    border.color: hexField.activeFocus ? Tokens.ink : Tokens.line
                    TextInput {
                        id: hexField
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.s2
                        anchors.rightMargin: Tokens.s2
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Tokens.ink
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        selectByMouse: true
                        maximumLength: 7
                        text: colorPop.curHex
                        onActiveFocusChanged: if (activeFocus) selectAll()
                        function commit() {
                            var t = text.trim();
                            if (t.length > 0 && t[0] !== "#") t = "#" + t;
                            if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                                colorPop.seed(Qt.color(t));
                                bar.commitColor();
                            }
                            text = Qt.binding(function () { return colorPop.curHex; });
                        }
                        Keys.onReturnPressed: commit()
                        Keys.onEnterPressed: commit()
                        Keys.onEscapePressed: (e) => { bar.closeColor(); e.accepted = true; }
                        onEditingFinished: commit()
                    }
                }
                Btn {
                    id: autoBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("AUTO")
                    compact: true
                    armed: Config.hasCustomColor || Config.gradient
                    onAct: {
                        Config.setGradient(false);
                        Config.clearColor();
                        colorPop.editing = "a";
                        colorPop.seed(bar.wallpaperColor);
                    }
                }
            }
        }
    }

    // The eyebrow says what the control below it is.
    component Group: Column {
        property string label: ""
        property bool dim: false
        spacing: 7
        opacity: dim ? 0.35 : 1
        enabled: !dim
        Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
        Text {
            text: I18n.tr(parent.label)
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fTiny
            font.letterSpacing: Tokens.trackMark
            font.weight: Font.Medium
        }
    }
    component Value: Text {
        color: Tokens.ink
        font.family: Tokens.mono
        font.pixelSize: Tokens.fRow
    }
    component Rule: Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Tokens.border
        height: 34
        color: Tokens.lineSoft
    }
}
