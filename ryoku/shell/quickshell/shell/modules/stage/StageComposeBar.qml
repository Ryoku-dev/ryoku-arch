pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"

// The Stage edit-mode toolbar (docs/stage.md): one slim, semi-transparent dock
// at the bottom of the live desktop carrying the stage knobs: effect, quality
// (inline download), edge, shadow (+ angle dial while > 0), motion (Parallax
// only) and Done, plus a live readout while a gesture is in flight. Adding
// layers and widgets lives in the left Add palette, not here. The row flows to
// as many rows as the screen needs (one at 2560, two at 1920) and never leaves
// the bottom edge, so the subject it edits is never obscured. One Escape cancels
// the current selection, a second (or Enter/Done) leaves.
Item {
    id: bar
    signal done()
    anchors.fill: parent

    readonly property var sb: StageBackend
    readonly property var cfg: Config
    readonly property string effect: bar.sb.effect
    readonly property bool parallax: bar.effect === "parallax"

    onVisibleChanged: if (bar.visible) bar.forceActiveFocus()
    Keys.onEscapePressed: e => {
        if (!StageSession.escapeUnwinds())
            bar.done();
        e.accepted = true;
    }
    Keys.onReturnPressed: e => { bar.done(); e.accepted = true; }

    function setQuality(id) {
        bar.cfg.setQuality(id);
        if (bar.sb.qualityInstalled(id) && bar.effect !== "off")
            bar.sb.refresh();
    }

    // A labelled cell: a small caps label over one control, so the Flow wraps in
    // readable groups instead of loose knobs.
    component Group: Column {
        id: grp
        property string label: ""
        spacing: 4
        Text {
            text: grp.label.toUpperCase()
            visible: grp.label.length > 0
            color: Theme.primary
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 4
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        id: dock
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        height: flow.implicitHeight + 24
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.84)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)

        // Absorb clicks on the bar itself so nothing falls through to widgets.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Flow {
            id: flow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 14

            Group {
                label: "Effect"
                width: 300
                StageSeg {
                    options: [
                        { id: "off", label: "Off" },
                        { id: "depth", label: "Depth" },
                        { id: "parallax", label: "Parallax" }
                    ]
                    current: bar.effect
                    onChose: id => bar.sb.setEffect(id)
                }
            }
            Group {
                label: "Quality"
                width: 340
                StageQuality {
                    current: bar.cfg.quality
                    onChose: id => bar.setQuality(id)
                }
            }
            Group {
                label: "Edge"
                width: 200
                StageDragSlider {
                    title: ""
                    value: bar.cfg.edge
                    min: 0; max: 1; decimals: 2
                    onChanged: v => bar.cfg.setEdge(v)
                }
            }
            Group {
                label: "Shadow"
                width: 200
                StageDragSlider {
                    title: ""
                    value: bar.cfg.shadow
                    min: 0; max: 1; decimals: 2
                    onChanged: v => bar.cfg.setShadow(v)
                }
            }
            Group {
                label: "Angle"
                width: 100
                visible: bar.cfg.shadow > 0
                StageAngleDial {
                    angle: bar.cfg.shadowAngle
                    onChanged: deg => bar.cfg.setShadowAngle(deg)
                }
            }
            Group {
                label: "Amount"
                width: 230
                visible: bar.parallax
                StageSeg {
                    options: [
                        { id: "subtle", label: "Subtle" },
                        { id: "normal", label: "Normal" },
                        { id: "strong", label: "Strong" }
                    ]
                    current: bar.cfg.amount
                    onChose: id => bar.cfg.setAmount(id)
                }
            }
            Group {
                label: "Idle"
                width: 240
                visible: bar.parallax
                StageSeg {
                    options: [
                        { id: "none", label: "None" },
                        { id: "float", label: "Float" },
                        { id: "breathe", label: "Breathe" }
                    ]
                    current: bar.cfg.idle
                    onChose: id => bar.cfg.setIdle(id)
                }
            }
            Group {
                label: "Music"
                width: 140
                visible: bar.parallax
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: Theme.radiusWidget
                    color: bar.cfg.music ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                        : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Text {
                        anchors.centerIn: parent
                        text: bar.cfg.music ? "React: On" : "React: Off"
                        color: bar.cfg.music ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bar.cfg.setMusic(!bar.cfg.music)
                    }
                }
            }
            // Live readout while a widget is being moved or resized.
            Group {
                label: "Editing"
                width: 200
                visible: StageSession.readout.length > 0
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: Theme.radiusWidget
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                    Text {
                        anchors.fill: parent
                        anchors.margins: 10
                        verticalAlignment: Text.AlignVCenter
                        text: StageSession.readout
                        elide: Text.ElideRight
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                    }
                }
            }
            Group {
                label: "Session"
                width: 150
                StageBtn {
                    width: parent.width
                    height: 38
                    kind: "filled"
                    icon: "check"
                    label: "Done"
                    onAct: bar.done()
                }
            }
        }
    }
}
