import QtQuick
import "../../modules"
import Ryoku.Ui.Singletons

// The per-widget colour and geometry popover, lifted out of the old Appearance
// route so the Widgets route can open it for a selected widget by gid. Chrome is
// paper ink and inversion; the swatches stay coloured, because there the colour
// is the data. Every backing key is a root.widget* helper (the qsbar Theme), so
// this file adds no state of its own. `gid` addresses the widget; `label` names
// it in the header; `dismissed()` fires when the scrim or a click closes it.
Item {
    id: pop
    property var root: null
    property var tk: null
    property string gid: ""
    property string label: ""
    signal dismissed()

    anchors.fill: parent

    // preset row for a per-widget geometry knob (opacity/radius/pad)
    component GeomRow: Column {
        id: grow
        property string glabel: ""
        property string gkey: ""
        property var opts: []
        readonly property real cellGap: pop.tk ? pop.tk.gap / 3 : 4
        width: parent ? parent.width : 0
        spacing: grow.cellGap
        UiText {
            text: grow.glabel
            color: pop.tk ? Tokens.inkMuted : "#958f87"
            font.family: pop.tk ? Tokens.mono : "monospace"
            font.pixelSize: pop.tk ? Tokens.fTiny : 9
            font.letterSpacing: pop.tk ? Tokens.trackLabel : 0.7
        }
        Row {
            width: parent.width
            spacing: grow.cellGap
            Repeater {
                model: grow.opts
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: pop.root.widgetGeomOf(pop.gid)[grow.gkey] === modelData.v
                    width: pop.root.evenW((grow.width - (grow.opts.length - 1) * grow.cellGap) / grow.opts.length)
                    height: pop.tk ? Tokens.ctlH : 26
                    radius: pop.tk ? Tokens.radius : 6
                    color: sel ? (pop.tk ? Tokens.bone : "#cdc4ba")
                        : gma.containsMouse ? (pop.tk ? Tokens.tint5 : "#111111") : "transparent"
                    border.color: sel ? "transparent" : (pop.tk ? Tokens.line : "#333333")
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: pop.tk ? Tokens.snap : 90 } }
                    UiText {
                        anchors.centerIn: parent
                        text: I18n.tr(modelData.label)
                        color: parent.sel ? (pop.tk ? Tokens.inkOnBone : "#000000") : (pop.tk ? Tokens.ink : "#cdc4ba")
                        font.family: pop.tk ? Tokens.mono : "monospace"
                        font.pixelSize: pop.tk ? Tokens.fSmall : 13
                    }
                    MouseArea {
                        id: gma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.root.setWidgetGeom(pop.gid, grow.gkey, modelData.v)
                    }
                }
            }
        }
    }

    // frame width preset row - GeomRow's language, wired to the border width
    // instead of the widgetGeom map.
    component FrameWidthRow: Column {
        id: fwrow
        property string glabel: ""
        property var opts: []
        readonly property real cellGap: pop.tk ? pop.tk.gap / 3 : 4
        width: parent ? parent.width : 0
        spacing: fwrow.cellGap
        UiText {
            text: fwrow.glabel
            color: pop.tk ? Tokens.inkMuted : "#958f87"
            font.family: pop.tk ? Tokens.mono : "monospace"
            font.pixelSize: pop.tk ? Tokens.fTiny : 9
            font.letterSpacing: pop.tk ? Tokens.trackLabel : 0.7
        }
        Row {
            width: parent.width
            spacing: fwrow.cellGap
            Repeater {
                model: fwrow.opts
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: pop.root.widgetBorderWidth(pop.gid) === modelData.v
                    width: pop.root.evenW((fwrow.width - (fwrow.opts.length - 1) * fwrow.cellGap) / fwrow.opts.length)
                    height: pop.tk ? Tokens.ctlH : 26
                    radius: pop.tk ? Tokens.radius : 6
                    color: sel ? (pop.tk ? Tokens.bone : "#cdc4ba")
                        : fwma.containsMouse ? (pop.tk ? Tokens.tint5 : "#111111") : "transparent"
                    border.color: sel ? "transparent" : (pop.tk ? Tokens.line : "#333333")
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: pop.tk ? Tokens.snap : 90 } }
                    UiText {
                        anchors.centerIn: parent
                        text: I18n.tr(modelData.label)
                        color: parent.sel ? (pop.tk ? Tokens.inkOnBone : "#000000") : (pop.tk ? Tokens.ink : "#cdc4ba")
                        font.family: pop.tk ? Tokens.mono : "monospace"
                        font.pixelSize: pop.tk ? Tokens.fSmall : 13
                    }
                    MouseArea {
                        id: fwma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.root.setWidgetBorderWidth(pop.gid, modelData.v)
                    }
                }
            }
        }
    }

    // frame colour row - swatches for the border key. inherit/surface are
    // labelled chips (not fixed palette colours) and invert when chosen; the
    // rest render as the palette swatches do, with a bone ring.
    component FrameColorRow: Column {
        id: fcrow
        property string glabel: ""
        readonly property real cellGap: pop.tk ? pop.tk.gap / 2 : 4
        width: parent ? parent.width : 0
        spacing: pop.tk ? pop.tk.gap / 3 : 4
        UiText {
            text: fcrow.glabel
            color: pop.tk ? Tokens.inkMuted : "#958f87"
            font.family: pop.tk ? Tokens.mono : "monospace"
            font.pixelSize: pop.tk ? Tokens.fTiny : 9
            font.letterSpacing: pop.tk ? Tokens.trackLabel : 0.7
        }
        Grid {
            width: parent.width
            columns: 8
            columnSpacing: fcrow.cellGap
            rowSpacing: fcrow.cellGap
            Repeater {
                model: ["inherit", "surface"].concat(pop.root.barColorOptions)
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool labelled: modelData === "inherit" || modelData === "surface"
                    readonly property bool selected: pop.root.widgetBorderColorKey(pop.gid) === modelData
                    width: pop.root.evenW((fcrow.width - 7 * fcrow.cellGap) / 8)
                    height: pop.tk ? Tokens.ctlH : 26
                    radius: pop.tk ? Tokens.radius : 6
                    color: labelled
                        ? (selected ? (pop.tk ? Tokens.bone : "#cdc4ba")
                            : fcma.containsMouse ? (pop.tk ? Tokens.tint5 : "#111111") : "transparent")
                        : pop.root.paletteColor(modelData)
                    border.color: labelled
                        ? (selected ? "transparent"
                            : (fcma.containsMouse ? (pop.tk ? Tokens.ink : "#cccccc") : (pop.tk ? Tokens.line : "#333333")))
                        : (selected ? (pop.tk ? Tokens.bone : "#cdc4ba") : (pop.tk ? Tokens.line : "#333333"))
                    border.width: (!labelled && selected) ? 2 : 1
                    scale: fcma.containsMouse ? 1.06 : 1.0
                    z: fcma.containsMouse ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: pop.tk ? Tokens.snap : 90; easing.type: Easing.OutCubic } }
                    UiText {
                        anchors.centerIn: parent
                        text: parent.labelled
                            ? (modelData === "inherit" ? I18n.tr("Auto") : I18n.tr("Fill"))
                            : (modelData === "foreground" ? "F" : modelData.slice(-1))
                        color: parent.labelled
                            ? (parent.selected ? (pop.tk ? Tokens.inkOnBone : "#000000") : (pop.tk ? Tokens.ink : "#cdc4ba"))
                            : pop.root.paletteContrastColor(modelData)
                        font.family: pop.tk ? Tokens.mono : "monospace"
                        font.pixelSize: pop.tk ? Tokens.fTiny : 9
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: fcma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.root.setWidgetBorderColorKey(pop.gid, modelData)
                    }
                }
            }
        }
    }

    // dim backdrop: click outside to dismiss. The scrim is tk ink at low alpha,
    // not a hardcoded black, so it darkens paper honestly.
    Rectangle {
        anchors.fill: parent
        color: pop.tk ? Qt.rgba(Tokens.ink.r, Tokens.ink.g, Tokens.ink.b, 0.32) : Qt.rgba(0, 0, 0, 0.38)
        MouseArea { anchors.fill: parent; onClicked: pop.dismissed() }
    }

    Rectangle {
        id: menu
        anchors.centerIn: parent
        readonly property int cell: pop.tk ? Tokens.ctlH : 26
        readonly property int pad: pop.tk ? pop.tk.gap : 12
        width: Math.min(parent.width - 2 * (pop.tk ? pop.tk.pad : 20),
            8 * cell + 7 * (pop.tk ? pop.tk.gap / 2 : 4) + 2 * pad)
        height: menuCol.implicitHeight + 2 * pad
        radius: pop.tk ? Tokens.radius : 6
        color: pop.tk ? Tokens.paperLift : "#161310"
        border.color: pop.tk ? Tokens.line : "#333333"
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }   // eat clicks inside

        Column {
            id: menuCol
            anchors.fill: parent
            anchors.margins: menu.pad
            spacing: pop.tk ? pop.tk.gap : 10

            // header: "<WIDGET> APPEARANCE" + reset / inherit affordance
            Item {
                width: parent.width
                height: pop.tk ? pop.tk.eyebrowH : 16
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("%1 APPEARANCE").arg(pop.label.toUpperCase())
                    color: pop.tk ? Tokens.inkMuted : "#958f87"
                    font.family: pop.tk ? Tokens.mono : "monospace"
                    font.pixelSize: pop.tk ? Tokens.fMicro : 11
                    font.letterSpacing: pop.tk ? Tokens.trackMark : 2.2
                    font.weight: Font.DemiBold
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (pop.root.widgetPaletteId(pop.gid) === "inherit" && !pop.root.widgetGeomCustomized(pop.gid)) ? I18n.tr("INHERIT") : I18n.tr("RESET")
                    color: resetMa.containsMouse ? (pop.tk ? Tokens.ink : "#cdc4ba") : (pop.tk ? Tokens.inkFaint : "#7a756e")
                    font.family: pop.tk ? Tokens.mono : "monospace"
                    font.pixelSize: pop.tk ? Tokens.fTiny : 9
                }
                MouseArea {
                    id: resetMa
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: pop.tk ? Tokens.ctlH * 2 : 48
                    height: parent.height
                    enabled: pop.root.widgetPaletteId(pop.gid) !== "inherit" || pop.root.widgetGeomCustomized(pop.gid)
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { pop.root.resetWidgetColor(pop.gid); pop.root.resetWidgetGeom(pop.gid) }
                }
            }

            // palette swatches (colors.toml palette, 8 across). The colour is the
            // data, so the swatch keeps its hue; a bone ring marks the current pick.
            Grid {
                width: parent.width
                columns: 8
                columnSpacing: pop.tk ? pop.tk.gap / 2 : 4
                rowSpacing: pop.tk ? pop.tk.gap / 2 : 4
                Repeater {
                    model: pop.root.barColorOptions
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool selected:
                            pop.root.widgetPaletteId(pop.gid) === modelData
                        width: pop.root.evenW((menuCol.width - 7 * (pop.tk ? pop.tk.gap / 2 : 4)) / 8)
                        height: pop.tk ? Tokens.ctlH : 26
                        radius: pop.tk ? Tokens.radius : 6
                        color: pop.root.paletteColor(modelData)
                        border.color: selected ? (pop.tk ? Tokens.bone : "#cdc4ba") : (pop.tk ? Tokens.line : "#333333")
                        border.width: selected ? 2 : 1
                        scale: swatchMa.containsMouse ? 1.06 : 1.0
                        z: swatchMa.containsMouse ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: pop.tk ? Tokens.snap : 90; easing.type: Easing.OutCubic } }
                        UiText {
                            anchors.centerIn: parent
                            text: modelData === "foreground" ? "F" : modelData.slice(-1)
                            color: pop.root.paletteContrastColor(modelData)
                            font.family: pop.tk ? Tokens.mono : "monospace"
                            font.pixelSize: pop.tk ? Tokens.fTiny : 9
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: swatchMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (parent.selected) pop.root.resetWidgetColor(pop.gid)
                                else pop.root.setWidgetPaletteColor(pop.gid, modelData)
                            }
                        }
                    }
                }
            }

            // frame (border) toggle - a bone plate when on, inversion, not a tint.
            Rectangle {
                width: parent.width
                height: pop.tk ? Tokens.ctlH : 26
                radius: pop.tk ? Tokens.radius : 6
                readonly property bool outlineOn: pop.root.widgetHasBorder(pop.gid)
                color: outlineOn ? (pop.tk ? Tokens.bone : "#cdc4ba")
                    : borderMa.containsMouse ? (pop.tk ? Tokens.tint5 : "#111111") : "transparent"
                border.color: outlineOn ? "transparent" : (pop.tk ? Tokens.line : "#333333")
                border.width: 1
                Behavior on color { ColorAnimation { duration: pop.tk ? Tokens.snap : 90 } }
                UiText {
                    anchors.centerIn: parent
                    text: I18n.tr("Frame")
                    color: parent.outlineOn ? (pop.tk ? Tokens.inkOnBone : "#000000") : (pop.tk ? Tokens.ink : "#cdc4ba")
                    font.family: pop.tk ? Tokens.mono : "monospace"
                    font.pixelSize: pop.tk ? Tokens.fSmall : 13
                }
                MouseArea {
                    id: borderMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pop.root.setWidgetBorderEnabled(
                        pop.gid, !pop.root.widgetHasBorder(pop.gid))
                }
            }

            FrameWidthRow {
                glabel: I18n.tr("WIDTH")
                visible: pop.root.widgetHasBorder(pop.gid)
                opts: [{ v: 0.5, label: "0.5" }, { v: 1, label: "1" }, { v: 1.5, label: "1.5" }, { v: 2, label: "2" }]
            }
            FrameColorRow {
                glabel: I18n.tr("COLOUR")
                visible: pop.root.widgetHasBorder(pop.gid)
            }

            // content tone - only meaningful when the group carries a fill
            Row {
                width: parent.width
                spacing: pop.tk ? pop.tk.gap / 3 : 4
                visible: pop.root.widgetHasFill(pop.gid)
                Repeater {
                    model: [
                        { id: "auto",       label: I18n.tr("Auto") },
                        { id: "background", label: "BG" },
                        { id: "foreground", label: "FG" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected:
                            pop.root.widgetTone(pop.gid) === modelData.id
                        width: pop.root.evenW((menuCol.width - 2 * (pop.tk ? pop.tk.gap / 3 : 4)) / 3)
                        height: pop.tk ? Tokens.ctlH : 26
                        radius: pop.tk ? Tokens.radius : 6
                        color: selected ? (pop.tk ? Tokens.bone : "#cdc4ba")
                            : toneMa.containsMouse ? (pop.tk ? Tokens.tint5 : "#111111") : "transparent"
                        border.color: selected ? "transparent" : (pop.tk ? Tokens.line : "#333333")
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: pop.tk ? Tokens.snap : 90 } }
                        UiText {
                            anchors.centerIn: parent
                            text: I18n.tr(modelData.label)
                            color: parent.selected ? (pop.tk ? Tokens.inkOnBone : "#000000") : (pop.tk ? Tokens.ink : "#cdc4ba")
                            font.family: pop.tk ? Tokens.mono : "monospace"
                            font.pixelSize: pop.tk ? Tokens.fSmall : 13
                        }
                        MouseArea {
                            id: toneMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pop.root.setWidgetTone(pop.gid, modelData.id)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: pop.tk ? Tokens.line : "#333333" }
            GeomRow {
                glabel: I18n.tr("OPACITY")
                gkey: "opacity"
                opts: [{ v: 1, label: "100" }, { v: 0.85, label: "85" }, { v: 0.7, label: "70" }, { v: 0.5, label: "50" }]
            }
            GeomRow {
                glabel: I18n.tr("CORNERS")
                gkey: "radius"
                opts: [{ v: 0, label: "0" }, { v: 4, label: "4" }, { v: 8, label: "8" }, { v: 12, label: "12" }]
            }
            GeomRow {
                glabel: I18n.tr("PADDING")
                gkey: "pad"
                opts: [{ v: 0, label: "0" }, { v: 2, label: "2" }, { v: 4, label: "4" }, { v: 6, label: "6" }]
            }
        }
    }
}
