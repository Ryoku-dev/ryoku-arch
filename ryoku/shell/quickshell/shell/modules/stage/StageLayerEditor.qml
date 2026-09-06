import QtQuick
import shell.services
import "Singletons"

// The per-layer knob panel under Scene (docs/stage.md): a collapsible header
// (with an eye to enable/disable the layer) over the depth, parallax, look and
// motion knobs. Every edit is a coalesced `set-layer` intent via StageBackend;
// feather/lift/shadow/shadowAngle inherit Config's global look until set here.
Item {
    id: ed
    property string wallPath: ""
    property int slot: 0            // 0-based layer index
    property bool expanded: false
    property bool removable: false
    signal toggle()
    signal remove()
    width: parent ? parent.width : 0
    implicitHeight: col.implicitHeight

    readonly property string url: StageBackend.layerUrlFor(ed.wallPath, ed.slot)

    Column {
        id: col
        width: parent.width
        spacing: 4

        StagePanelHeader {
            icon: {
                const lbl = StageBackend.layerLabel(ed.wallPath, ed.slot).toLowerCase();
                return lbl.indexOf("subject") === 0 ? "person" : "layers";
            }
            label: StageBackend.layerLabel(ed.wallPath, ed.slot)
            expanded: ed.expanded
            showEye: true
            eyeOn: StageBackend.layerEnabled(ed.wallPath, ed.slot)
            onToggle: ed.toggle()
            onEye: StageBackend.toggleLayerEnabled(ed.slot)
        }

        Column {
            width: parent.width
            spacing: 8
            visible: ed.expanded

            Rectangle {
                width: parent.width
                height: 120
                radius: Theme.radiusWidget
                clip: true
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.04)
                border.width: 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
                Image {
                    anchors.fill: parent
                    anchors.margins: 8
                    source: ed.url
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: parent.width - 16
                    sourceSize.height: parent.height - 16
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.crossfade } }
                }
            }

            StageSection { title: "Depth" }
            StageDragSlider {
                title: "Feather"
                value: StageBackend.layerFeather(ed.wallPath, ed.slot, Config.feather)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { feather: Math.max(0, Math.min(1, v)) })
            }
            StageDragSlider {
                title: "Lift"
                value: StageBackend.layerLift(ed.wallPath, ed.slot, Config.lift)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { lift: Math.max(0, Math.min(1, v)) })
            }
            StageDragSlider {
                title: "Shadow strength"
                value: StageBackend.layerShadow(ed.wallPath, ed.slot, Config.shadow)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { shadow: Math.max(0, Math.min(1, v)) })
            }
            Row {
                width: parent.width
                spacing: 12
                StageAngleDial {
                    angle: StageBackend.layerShadowAngle(ed.wallPath, ed.slot, Config.shadowAngle)
                    onChanged: deg => StageBackend.setLayer(ed.slot, { shadowAngle: Math.round(deg) })
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 84 - 12
                    spacing: 2
                    Text {
                        text: "Shadow angle"
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: StageBackend.layerShadowAngle(ed.wallPath, ed.slot, Config.shadowAngle) + "\u00B0 - Drag the dot to set where the shadow falls."
                        wrapMode: Text.WordWrap
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 3
                        width: parent.width
                    }
                }
            }

            StageSection { title: "Parallax" }
            StageDragSlider {
                title: "Parallax speed"
                value: StageBackend.layerParallax(ed.wallPath, ed.slot)
                min: 0; max: 2; decimals: 1
                onChanged: v => StageBackend.setLayer(ed.slot, { parallax: Math.max(0, Math.min(2, v)) })
            }
            StageDragSlider {
                title: "Depth factor"
                value: StageBackend.layerDepthFactor(ed.wallPath, ed.slot)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { depthFactor: Math.max(0, Math.min(1, v)) })
            }
            StageDragSlider {
                title: "Max drift"
                value: StageBackend.layerMouseMax(ed.wallPath, ed.slot)
                min: 0; max: 96; decimals: 0; unit: " px"
                onChanged: v => StageBackend.setLayer(ed.slot, { mouseMax: Math.max(0, Math.min(96, Math.round(v))) })
            }

            StageSection { title: "Look" }
            StageDragSlider {
                title: "Opacity"
                value: StageBackend.layerOpacity(ed.wallPath, ed.slot)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { opacity: Math.max(0, Math.min(1, v)) })
            }
            StageDragSlider {
                title: "Offset X"
                value: StageBackend.layerOffsetX(ed.wallPath, ed.slot)
                min: -400; max: 400; decimals: 0; unit: " px"
                onChanged: v => StageBackend.setLayer(ed.slot, { offsetX: Math.round(v) })
            }
            StageDragSlider {
                title: "Offset Y"
                value: StageBackend.layerOffsetY(ed.wallPath, ed.slot)
                min: -400; max: 400; decimals: 0; unit: " px"
                onChanged: v => StageBackend.setLayer(ed.slot, { offsetY: Math.round(v) })
            }

            StageSection { title: "Motion" }
            StageField {
                title: "Animation"
                choices: [
                    { id: "none", label: "None" },
                    { id: "float", label: "Float" },
                    { id: "pulse", label: "Pulse" },
                    { id: "scale", label: "Scale" },
                    { id: "wiggle", label: "Wiggle" },
                    { id: "rotate", label: "Rotate" }
                ]
                current: StageBackend.layerAnimType(ed.wallPath, ed.slot)
                onChose: id => StageBackend.setLayer(ed.slot, { animType: id })
            }
            StageDragSlider {
                title: "Animation speed"
                value: StageBackend.layerAnimSpeed(ed.wallPath, ed.slot)
                min: 0.1; max: 3; decimals: 1
                visible: StageBackend.layerAnimType(ed.wallPath, ed.slot) !== "none"
                onChanged: v => StageBackend.setLayer(ed.slot, { animSpeed: Math.max(0.1, Math.min(3, v)) })
            }
            StageDragSlider {
                title: "Animation amplitude"
                value: StageBackend.layerAnimAmplitude(ed.wallPath, ed.slot)
                min: 0; max: 64; decimals: 0
                visible: StageBackend.layerAnimType(ed.wallPath, ed.slot) !== "none"
                onChanged: v => StageBackend.setLayer(ed.slot, { animAmplitude: Math.max(0, Math.min(64, Math.round(v))) })
            }
            StageDragSlider {
                title: "Audio reactivity"
                value: StageBackend.layerAudioLevel(ed.wallPath, ed.slot)
                min: 0; max: 1; decimals: 2
                onChanged: v => StageBackend.setLayer(ed.slot, { audioLevel: Math.max(0, Math.min(1, v)) })
            }
            StageBtn {
                visible: ed.removable
                kind: "ghost"
                icon: "delete"
                label: "Remove this layer"
                onAct: ed.remove()
            }
        }
    }
}
