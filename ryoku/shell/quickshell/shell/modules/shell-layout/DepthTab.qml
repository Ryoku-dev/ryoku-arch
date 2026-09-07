pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import shell.services
import "../stage"
import "../stage/Singletons" as Stage
import "../../components"

// Edit shell, Depth tab (docs/stage.md): the still cut. Depth switch, Subject
// (behind/in front of the widgets), Edge and Shadow (render-only, live), a
// Quality picker whose choice only marks a pending tier, and a Re-cut button
// that is the second, explicit press. The Layers drop-down carries the per-layer
// rows and the Cut / Add / Clear actions, each of the engine ones behind its own
// confirm.
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
    readonly property bool parallax: tab.effect === "parallax"
    readonly property int layerCount: tab.sb.layerCountFor(tab.wall)
    readonly property int selIndex: tab.ses.isLayer(tab.ses.selected) ? tab.ses.layerIndex(tab.ses.selected) : 0

    // The tier the Quality picker is proposing, if any (a pending confirm).
    property string pendingTier: ""
    property string pickedCut: ""

    function tierLabel(t) { return t === "fine" ? "Fine" : t === "standard" ? "Standard" : "Draft"; }
    function _path(u) { return ("" + u).replace(/^file:\/\//, ""); }

    Connections {
        target: tab.ses
        function onPendingChanged() {
            if (tab.ses.pending !== "quality") tab.pendingTier = "";
            if (tab.ses.pending !== "cut") tab.pickedCut = "";
        }
    }

    // A small pill button for the drop-down actions and confirms.
    component MiniAct: Rectangle {
        id: ma2
        property string icon: ""
        property string label: ""
        property bool filled: false
        signal act()
        implicitWidth: maRow.implicitWidth + 24
        width: implicitWidth
        height: 34
        radius: Theme.radiusWidget
        color: ma2.filled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : maMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        border.width: ma2.filled ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Row {
            id: maRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon { anchors.verticalCenter: parent.verticalCenter; visible: ma2.icon.length > 0; text: ma2.icon; font.pixelSize: 16; color: ma2.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ma2.label; color: ma2.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface; font.family: Theme.fontPrimary; font.pixelSize: Theme.fontSm - 2; font.weight: Font.DemiBold }
        }
        MouseArea { id: maMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ma2.act() }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RibbonGroup {
            caption: "Depth"
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Depth"; checked: tab.effect !== "off"
                onToggled: { tab.sb.setEffect(tab.effect === "off" ? "depth" : "off"); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Subject"
            StageSeg {
                width: 220
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "behind", label: "Behind widgets" }, { id: "front", label: "In front" }]
                current: tab.sb.layerFront(tab.wall, tab.selIndex) ? "front" : "behind"
                onChose: id => { tab.sb.setLayerFront(tab.selIndex, id === "front"); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Edge"
            StageDragSlider {
                width: 130
                anchors.verticalCenter: parent.verticalCenter
                title: ""
                value: tab.cfg.edge
                min: 0; max: 1; decimals: 2
                onChanged: v => { tab.cfg.setEdge(v); tab.ses.markDirty(); }
            }
        }
        RibbonGroup {
            caption: "Shadow"
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                StageDragSlider {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    title: ""
                    value: tab.cfg.shadow
                    min: 0; max: 1; decimals: 2
                    onChanged: v => { tab.cfg.setShadow(v); tab.ses.markDirty(); }
                }
                StageAngleDial {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tab.cfg.shadow > 0
                    dim: 40
                    angle: tab.cfg.shadowAngle
                    onChanged: deg => { tab.cfg.setShadowAngle(deg); tab.ses.markDirty(); }
                }
            }
        }
        RibbonGroup {
            caption: "Quality"
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                StageSeg {
                    id: qSeg
                    width: 210
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ id: "draft", label: "Draft" }, { id: "standard", label: "Standard" }, { id: "fine", label: "Fine" }]
                    current: (tab.ses.pending === "quality" && tab.pendingTier !== "") ? tab.pendingTier : tab.cfg.quality
                    onChose: id => { tab.pendingTier = id; tab.ses.setPending("quality"); }
                }
                // The Re-cut button: fills once a tier is pending; shows Download
                // for a missing model, and Stop with the percent while cutting.
                Rectangle {
                    id: recut
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool pendingQ: tab.ses.pending === "quality" && tab.pendingTier !== ""
                    readonly property string tierNow: recut.pendingQ ? tab.pendingTier : tab.cfg.quality
                    readonly property var model: tab.sb.modelForQuality(recut.tierNow)
                    readonly property bool installed: !!(recut.model && recut.model.installed === true)
                    readonly property string mode: tab.sb.busy ? "stop"
                        : (recut.pendingQ && !recut.installed) ? "download"
                        : recut.pendingQ ? "recut" : "idle"
                    readonly property string label: recut.mode === "stop" ? ("Stop " + tab.sb.percent + "%")
                        : recut.mode === "download" ? ("Download " + (recut.model ? recut.model.size : ""))
                        : recut.mode === "recut" ? ("Re-cut in " + tab.tierLabel(tab.pendingTier))
                        : "Re-cut"
                    readonly property bool filled: recut.mode !== "idle"
                    width: recRow.implicitWidth + 26
                    height: 38
                    radius: Theme.radiusWidget
                    color: recut.filled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, recMa.containsMouse ? 0.95 : 0.85)
                        : recMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
                    border.width: recut.filled ? 0 : 1
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Row {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: recut.mode === "stop" ? "stop" : recut.mode === "download" ? "download" : "auto_fix_high"
                            font.pixelSize: 17
                            color: recut.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: recut.label
                            color: recut.filled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 1
                            font.weight: Font.DemiBold
                        }
                    }
                    MouseArea {
                        id: recMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (recut.mode === "stop") { tab.sb.cancel(); return; }
                            if (recut.mode === "download") { if (recut.model) tab.sb.install(recut.model.id); return; }
                            if (recut.mode === "recut") {
                                tab.cfg.setQuality(tab.pendingTier);
                                tab.sb.refresh();
                                tab.ses.clearPending();
                                tab.pendingTier = "";
                                tab.ses.markDirty();
                                return;
                            }
                            tab.sb.refresh();
                        }
                    }
                }
            }
        }

        // Layers: per-layer rows plus the confirmed Cut / Add / Clear.
        RibbonDropdown {
            id: layersDd
            overlay: tab.overlay; dropY: tab.dropY
            key: "layers"; label: "Layers"; icon: "layers"; panelW: 340

            Repeater {
                model: tab.layerCount
                delegate: Column {
                    id: layerRow
                    required property int index
                    width: parent.width
                    spacing: 5
                    Row {
                        width: parent.width
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - rmBtn.width
                            elide: Text.ElideRight
                            text: tab.sb.layerLabel(tab.wall, layerRow.index)
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 1
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            id: rmBtn
                            visible: layerRow.index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: visible ? 26 : 0
                            height: 26; radius: 13
                            color: rmMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
                            MaterialIcon { anchors.centerIn: parent; text: "close"; font.pixelSize: 16; color: Theme.onSurfaceVariant }
                            MouseArea {
                                id: rmMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    tab.sb.removeLayer(layerRow.index);
                                    tab.ses.markDirty();
                                    if (tab.ses.selected === ("layer:" + layerRow.index)) tab.ses.deselect();
                                }
                            }
                        }
                    }
                    StageSeg {
                        width: parent.width
                        options: [{ id: "behind", label: "Behind widgets" }, { id: "front", label: "In front" }]
                        current: tab.sb.layerFront(tab.wall, layerRow.index) ? "front" : "behind"
                        onChose: id => { tab.sb.setLayerFront(layerRow.index, id === "front"); tab.ses.markDirty(); }
                    }
                    StageDragSlider {
                        width: parent.width
                        visible: tab.parallax
                        title: "Drift (near to far)"
                        value: tab.sb.layerDepth(tab.wall, layerRow.index)
                        min: 0; max: 1; decimals: 2
                        onChanged: v => { tab.sb.setLayerDepth(layerRow.index, v); tab.ses.markDirty(); }
                    }
                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10) }
                }
            }

            // Cut a picture: pick, then confirm with the file name.
            Row {
                width: parent.width
                spacing: 8
                visible: tab.ses.pending !== "cut" && tab.ses.pending !== "clear"
                MiniAct { icon: "content_cut"; label: "Cut a picture..."; onAct: cutDlg.open() }
            }
            Row {
                width: parent.width
                spacing: 8
                visible: tab.ses.pending !== "cut" && tab.ses.pending !== "clear"
                MiniAct { icon: "image"; label: "Add a PNG..."; onAct: pngDlg.open() }
                MiniAct { icon: "layers_clear"; label: "Clear cut-outs"; onAct: tab.ses.setPending("clear") }
            }
            // Cut confirm row.
            Column {
                width: parent.width
                spacing: 6
                visible: tab.ses.pending === "cut"
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: "Cut from " + tab._path(tab.pickedCut).split("/").pop()
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }
                Row {
                    spacing: 8
                    MiniAct { icon: "content_cut"; label: "Cut"; filled: true; onAct: { tab.sb.cutLayer(tab._path(tab.pickedCut)); tab.ses.markDirty(); tab.ses.clearPending(); tab.pickedCut = ""; } }
                    MiniAct { label: "Cancel"; onAct: { tab.ses.clearPending(); tab.pickedCut = ""; } }
                }
            }
            // Clear confirm row.
            Column {
                width: parent.width
                spacing: 6
                visible: tab.ses.pending === "clear"
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Remove every cut-out from this wallpaper?"
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                }
                Row {
                    spacing: 8
                    MiniAct { icon: "layers_clear"; label: "Clear"; filled: true; onAct: { tab.sb.clear(); tab.ses.markDirty(); tab.ses.clearPending(); } }
                    MiniAct { label: "Cancel"; onAct: tab.ses.clearPending() }
                }
            }
        }
    }

    FileDialog {
        id: cutDlg
        title: "Cut a layer from a picture"
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp)", "All files (*)"]
        onAccepted: { tab.pickedCut = "" + cutDlg.selectedFile; tab.ses.setPending("cut"); }
    }
    FileDialog {
        id: pngDlg
        title: "Add a PNG layer"
        nameFilters: ["PNG images (*.png)", "All files (*)"]
        onAccepted: { tab.sb.addLayer(tab._path(pngDlg.selectedFile)); tab.ses.markDirty(); }
    }
}
