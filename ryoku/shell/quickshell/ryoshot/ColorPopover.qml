import QtQuick
import QtQuick.Layouts
import "Singletons"
import Ryoku.Ui.Singletons

Item {
    id: pop

    /** Externally driven current colour; seeds the HSV state on change. */
    property color selected: Theme.accent

    /** Renders the eyedropper button in its armed (active) state. */
    property bool eyedropArmed: false

    /** Emitted on any swatch, square, hue, or hex commit. */
    signal picked(color c)

    /** The parent closes the popover and arms sampling in the overlay. */
    signal eyedropRequested()

    signal closeRequested()

    focus: visible
    Keys.onEscapePressed: pop.closeRequested()

    readonly property int arrow: 7
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight + arrow

    property real hue: 0
    property real sat: 1
    property real val: 1
    property bool syncing: false

    readonly property color current: Qt.hsva(pop.hue, pop.sat, pop.val, 1)

    /**
     * Pulls hue/sat/val from an incoming colour. Greys read back a NaN/-1 hue
     * from Qt, so the prior hue is kept to avoid the marker jumping to red.
     */
    function syncFrom(c) {
        pop.syncing = true;
        if (c.hsvHue >= 0) pop.hue = c.hsvHue;
        pop.sat = c.hsvSaturation;
        pop.val = c.hsvValue;
        pop.syncing = false;
    }

    onSelectedChanged: if (!pop.syncing) pop.syncFrom(pop.selected)
    Component.onCompleted: {
        pop.syncFrom(pop.selected);
        appear.start();
    }

    /** Sets sat/val from a point inside the square and emits the new colour. */
    function pickSquare(px, py, w, h) {
        pop.sat = Math.max(0, Math.min(1, px / w));
        pop.val = Math.max(0, Math.min(1, 1 - py / h));
        pop.emitPick();
    }

    /** Sets hue from a point along the strip and emits the new colour. */
    function pickHue(px, w) {
        pop.hue = Math.max(0, Math.min(1, px / w));
        pop.emitPick();
    }

    function emitPick() {
        pop.syncing = true;
        pop.picked(pop.current);
        pop.syncing = false;
    }

    /** Two-digit hex for a 0..1 channel, used to render the #rrggbb readout. */
    function hex2(f) {
        var n = Math.round(f * 255);
        var s = n.toString(16);
        return s.length === 1 ? "0" + s : s;
    }

    readonly property string hexText:
        "#" + hex2(current.r) + hex2(current.g) + hex2(current.b)

    opacity: 0
    scale: 0.92
    transformOrigin: Item.Top
    ParallelAnimation {
        id: appear
        NumberAnimation { target: pop; property: "opacity"; from: 0; to: 1; duration: Theme.snap; easing.type: Easing.OutCubic }
        NumberAnimation { target: pop; property: "scale"; from: 0.92; to: 1; duration: Theme.snap; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        width: parent.width
        height: parent.height - pop.arrow
        radius: Theme.radius
        color: Theme.panel
        border.color: Theme.hair
        border.width: 1
        implicitWidth: 200
        implicitHeight: content.implicitHeight + 24

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                id: square
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                radius: 6
                clip: true
                color: Qt.hsva(pop.hue, 1, 1, 1)

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1) }
                    }
                }

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: Qt.rgba(0, 0, 0, 0)
                    border.color: Theme.ink
                    border.width: 2
                    x: pop.sat * square.width - width / 2
                    y: (1 - pop.val) * square.height - height / 2
                }

                TapHandler {
                    onTapped: (p) => pop.pickSquare(p.position.x, p.position.y, square.width, square.height)
                }
                DragHandler {
                    target: null
                    onCentroidChanged: if (active) pop.pickSquare(centroid.position.x, centroid.position.y, square.width, square.height)
                }
            }

            Rectangle {
                id: hueStrip
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                radius: 7
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.000; color: Qt.hsva(0.000, 1, 1, 1) }
                    GradientStop { position: 0.167; color: Qt.hsva(0.167, 1, 1, 1) }
                    GradientStop { position: 0.333; color: Qt.hsva(0.333, 1, 1, 1) }
                    GradientStop { position: 0.500; color: Qt.hsva(0.500, 1, 1, 1) }
                    GradientStop { position: 0.667; color: Qt.hsva(0.667, 1, 1, 1) }
                    GradientStop { position: 0.833; color: Qt.hsva(0.833, 1, 1, 1) }
                    GradientStop { position: 1.000; color: Qt.hsva(1.000, 1, 1, 1) }
                }

                Rectangle {
                    width: 6
                    height: parent.height + 4
                    y: -2
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0)
                    border.color: Theme.ink
                    border.width: 2
                    x: pop.hue * hueStrip.width - width / 2
                }

                TapHandler {
                    onTapped: (p) => pop.pickHue(p.position.x, hueStrip.width)
                }
                DragHandler {
                    target: null
                    onCentroidChanged: if (active) pop.pickHue(centroid.position.x, hueStrip.width)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Theme.swatches
                    Rectangle {
                        id: swatch
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        radius: 4
                        color: modelData
                        readonly property bool sel: Qt.colorEqual(pop.selected, modelData)
                        border.color: sel ? Theme.ink
                            : (swHover.hovered ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(1, 1, 1, 0.18))
                        border.width: sel ? 2 : 1
                        scale: swHover.hovered ? 1.12 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        HoverHandler { id: swHover }
                        TapHandler { onTapped: pop.picked(swatch.modelData) }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconButton {
                    id: eyedrop
                    icon: "pen"
                    active: pop.eyedropArmed
                    tooltip: I18n.tr("Pick a colour from the shot (i)")
                    onClicked: pop.eyedropRequested()
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 5
                    color: pop.current
                    border.color: Qt.rgba(1, 1, 1, 0.25)
                    border.width: 1
                }

                Rectangle {
                    id: hexBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    radius: 5
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Theme.hair
                    border.width: 1

                    SequentialAnimation {
                        id: hexFlash
                        ColorAnimation { target: hexBox; property: "border.color"; to: Theme.accent; duration: 90 }
                        ColorAnimation { target: hexBox; property: "border.color"; to: Theme.hair; duration: 240 }
                    }

                    TextInput {
                        id: hexField
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.ink
                        font.family: Theme.mono
                        font.pixelSize: 12
                        selectByMouse: true
                        selectionColor: Theme.accent
                        text: pop.hexText
                        maximumLength: 7
                        onActiveFocusChanged: if (activeFocus) selectAll()

                        /**
                         * Accepts a #rrggbb (or rrggbb) string on Enter or focus
                         * loss; a value Qt cannot parse reverts to the current
                         * colour so a half-typed hex never snaps the picker.
                         */
                        function commit() {
                            var t = text.trim();
                            if (t.length > 0 && t[0] !== "#") t = "#" + t;
                            if (/^#[0-9a-fA-F]{3}$/.test(t))
                                t = "#" + t[1] + t[1] + t[2] + t[2] + t[3] + t[3];
                            if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                                pop.picked(t);
                                pop.syncFrom(t);
                            } else {
                                hexFlash.start();
                            }
                            text = Qt.binding(function () { return pop.hexText; });
                        }
                        onEditingFinished: commit()
                        Keys.onReturnPressed: commit()
                        Keys.onEnterPressed: commit()
                    }
                }
            }
        }
    }

    Canvas {
        width: pop.arrow * 2
        height: pop.arrow
        anchors.bottom: card.top
        anchors.horizontalCenter: card.horizontalCenter
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.beginPath();
            ctx.moveTo(0, height);
            ctx.lineTo(width, height);
            ctx.lineTo(width / 2, 0);
            ctx.closePath();
            ctx.fillStyle = Theme.panel;
            ctx.fill();
        }
    }
}
