pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../stage"
import "../stage/Singletons" as Stage

// Edit shell, Parallax tab (docs/stage.md): motion on. Parallax switch, Drift
// for the selected layer (the subject by default), then the shared Motion,
// Mouse and Backdrop knobs. At 1366 Motion and Mouse fold into drop-downs.
Item {
    id: tab
    anchors.fill: parent

    property Item overlay: null
    property real dropY: 0
    property string monitor: ""
    property bool narrow: false

    readonly property var sb: Stage.StageBackend
    readonly property var cfg: Stage.Config
    readonly property var ses: Stage.StageSession
    readonly property string wall: tab.sb.current
    readonly property string effect: tab.sb.effect
    readonly property int selIndex: tab.ses.isLayer(tab.ses.selected) ? tab.ses.layerIndex(tab.ses.selected) : 0

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RibbonGroup {
            caption: "Parallax"
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Parallax"; checked: tab.effect === "parallax"
                onToggled: { tab.sb.setEffect(tab.effect === "parallax" ? "depth" : "parallax"); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Drift"
            StageDragSlider {
                width: 150
                anchors.verticalCenter: parent.verticalCenter
                title: ""
                value: tab.sb.layerDepth(tab.wall, tab.selIndex)
                min: 0; max: 1; decimals: 2
                onChanged: v => { tab.sb.setLayerDepth(tab.selIndex, v); tab.ses.markDirty(); }
            }
        }

        // Motion: three groups when wide, one drop-down at 1366.
        RibbonGroup {
            caption: "Amount"
            visible: !tab.narrow
            StageSeg {
                width: 200
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "subtle", label: "Subtle" }, { id: "normal", label: "Normal" }, { id: "strong", label: "Strong" }]
                current: tab.cfg.amount
                onChose: id => { tab.cfg.setAmount(id); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Idle"
            visible: !tab.narrow
            StageSeg {
                width: 200
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "none", label: "None" }, { id: "float", label: "Float" }, { id: "breathe", label: "Breathe" }]
                current: tab.cfg.idle
                onChose: id => { tab.cfg.setIdle(id); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Music"
            visible: !tab.narrow
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "React to music"; checked: tab.cfg.music
                onToggled: { tab.cfg.setMusic(!tab.cfg.music); tab.ses.markDirty(); }
            }
        }
        RibbonDropdown {
            visible: tab.narrow
            overlay: tab.overlay; dropY: tab.dropY
            key: "motion"; label: "Motion"; icon: "animation"; panelW: 260
            Text { text: "Amount"; color: Theme.onSurfaceVariant; font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 3; font.weight: Font.DemiBold }
            StageSeg {
                width: 236
                options: [{ id: "subtle", label: "Subtle" }, { id: "normal", label: "Normal" }, { id: "strong", label: "Strong" }]
                current: tab.cfg.amount
                onChose: id => { tab.cfg.setAmount(id); tab.ses.markDirty(); }
            }
            Text { text: "Idle"; color: Theme.onSurfaceVariant; font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 3; font.weight: Font.DemiBold }
            StageSeg {
                width: 236
                options: [{ id: "none", label: "None" }, { id: "float", label: "Float" }, { id: "breathe", label: "Breathe" }]
                current: tab.cfg.idle
                onChose: id => { tab.cfg.setIdle(id); tab.ses.markDirty(); }
            }
            StageSwitch { label: "React to music"; checked: tab.cfg.music; onToggled: { tab.cfg.setMusic(!tab.cfg.music); tab.ses.markDirty(); } }
        }

        // Mouse: one group when wide, a drop-down at 1366.
        RibbonGroup {
            caption: "Pointer"
            visible: !tab.narrow
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                StageSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Follow mouse"; checked: tab.cfg.followMouse
                    onToggled: { tab.cfg.setMouse(!tab.cfg.followMouse); tab.ses.markDirty(); }
                }
                StageDragSlider {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    title: "Sensitivity"
                    value: tab.cfg.sensitivity
                    min: 0; max: 2; decimals: 2
                    onChanged: v => { tab.cfg.setSensitivity(v); tab.ses.markDirty(); }
                }
                StageDragSlider {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    title: "Range"
                    value: tab.cfg.range
                    min: 0; max: 2; decimals: 2
                    onChanged: v => { tab.cfg.setRange(v); tab.ses.markDirty(); }
                }
            }
        }
        RibbonDropdown {
            visible: tab.narrow
            overlay: tab.overlay; dropY: tab.dropY
            key: "mouse"; label: "Mouse"; icon: "mouse"; panelW: 260
            StageSwitch { label: "Follow mouse"; checked: tab.cfg.followMouse; onToggled: { tab.cfg.setMouse(!tab.cfg.followMouse); tab.ses.markDirty(); } }
            StageDragSlider {
                width: 236
                title: "Sensitivity"
                value: tab.cfg.sensitivity
                min: 0; max: 2; decimals: 2
                onChanged: v => { tab.cfg.setSensitivity(v); tab.ses.markDirty(); }
            }
            StageDragSlider {
                width: 236
                title: "Range"
                value: tab.cfg.range
                min: 0; max: 2; decimals: 2
                onChanged: v => { tab.cfg.setRange(v); tab.ses.markDirty(); }
            }
        }

        RibbonGroup {
            caption: "Backdrop"
            last: true
            StageDragSlider {
                width: 150
                anchors.verticalCenter: parent.verticalCenter
                title: ""
                value: tab.cfg.backdrop
                min: 0; max: 1; decimals: 2
                onChanged: v => { tab.cfg.setBackdrop(v); tab.ses.markDirty(); }
            }
        }
    }
}
