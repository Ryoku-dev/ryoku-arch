import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// One setting, drawn as a compact row instead of a value-hero card. The label
// reads first (primary ink), the description sits under it (muted), and the
// control lives on the right -- or, for a control that needs room (a segmented
// bar, chips, a slider, a picker), in a band directly beneath the text. Rows
// stack inside a SettingCard and are parted by a hairline, so a page of toggles
// reads as one instrument sheet, not a wall of scattered tiles.
//
// The row never places itself: SettingCard's column flows it full width and
// SettingsSheet decides inline vs band from the control kind. Overlap is
// prevented by reservation (the text column stops at the control), never by
// tuned margins.
Item {
    id: row

    property string label: ""
    property string desc: ""
    property string eg: ""          // a worked example, shown faint under the desc
    property string value: ""       // compact readout (a slider number, a count); empty hides
    property string unit: ""
    property string def: ""         // factory value, struck when changed
    property string source: ""      // owning file, faint on hover
    property bool changed: false
    property bool block: false      // control band whose height is the control's own (chips, gallery)
    property int footH: 0           // control band of a fixed height (a picker, a field)
    property bool divider: false    // hairline above the row (every row but the first)
    property int controlWidth: 0    // width reserved for an inline control
    property bool spotlight: false  // flashed after a search jump

    signal resetRequested()

    default property alias control: slot.data

    readonly property int padV: Tokens.s3
    readonly property int padH: Tokens.s4
    readonly property bool banded: block || footH > 0
    readonly property real bandH: block
        ? Math.max(Tokens.ctlH, slot.children.length > 0 ? slot.children[0].implicitHeight : 0)
        : (footH > 0 ? footH : Tokens.ctlH)

    // inline rows hug the text at a comfortable minimum; band rows add the
    // control's own height beneath it. The card binds to this, so a control can
    // never bleed into the next row.
    implicitHeight: banded
        ? padV + txt.implicitHeight + Tokens.s3 + bandH + padV
        : Math.max(Tokens.rowH, padV + txt.implicitHeight + padV)
    height: implicitHeight

    // A row gated by a master switch (a dock's rows under Enabled, an accent slot
    // under Follow wallpaper) stops accepting input through `enabled`, so it has to
    // stop looking live as well: an inert control at full ink lies about its state.
    opacity: row.enabled ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: Tokens.snap; easing.type: Tokens.ease } }

    // search spotlight: a brief bone-tint wash when a search result lands here.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Tokens.radius
        color: Tokens.tint16
        opacity: row.spotlight ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease } }
    }
    // hover wash, quieter than a cell's so a stack of rows does not strobe.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Tokens.radius
        color: hh.hovered ? Tokens.tint5 : "transparent"
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
    }
    HoverHandler { id: hh }

    // the part between rows, inset so it reads as a rule not a box edge.
    Rectangle {
        visible: row.divider
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: row.padH; anchors.rightMargin: row.padH
        height: 1
        color: Tokens.lineSoft
    }

    // changed reads as a solid ink edge; no colour is spent on it.
    Rectangle {
        visible: row.changed
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 2
        height: parent.height - Tokens.s3
        color: Tokens.ink
    }

    // affordances at the top-right, used only for BANDED rows: the control sits
    // in a band below, so this corner is free. Shows the owning file on hover,
    // and when the row is changed the struck default plus a revert glyph.
    Row {
        id: topRight
        visible: row.banded && hh.hovered && (row.changed || row.source !== "")
        anchors { right: parent.right; rightMargin: row.padH; top: parent.top; topMargin: row.padV }
        spacing: Tokens.s2
        z: 3
        Text {
            visible: row.changed && row.def !== ""
            text: row.def + (row.unit ? " " + row.unit : "")
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            font.strikeout: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: !row.changed && row.source !== ""
            text: row.source.replace(".json", "")
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            visible: row.changed
            width: 18; height: 18; radius: Tokens.radius
            color: rhb.hovered ? Tokens.tint10 : "transparent"
            border.width: Tokens.border
            border.color: rhb.hovered ? Tokens.lineStrong : Tokens.line
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent; text: "\u21ba"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 11 }
            HoverHandler { id: rhb; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.resetRequested() }
        }
    }

    // text column: label first, then the description. Its right edge stops at
    // the inline value/control, so the two never collide.
    Column {
        id: txt
        anchors {
            left: parent.left; leftMargin: row.padH
            top: parent.top; topMargin: row.padV
            right: row.banded ? parent.right : vcluster.left
            rightMargin: row.banded ? row.padH : Tokens.s3
        }
        spacing: 1
        Text {
            width: parent.width
            text: I18n.tr(row.label)
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fRow
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            visible: row.desc !== ""
            width: parent.width
            text: I18n.tr(row.desc)
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            visible: row.eg !== ""
            width: parent.width
            text: I18n.tr("e.g. ") + row.eg
            color: Tokens.inkFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fTiny
            elide: Text.ElideRight
        }
    }

    // the inline right cluster, seated LEFT of the control so nothing overlaps
    // it: the compact value readout (a slider or stepper number) always, plus,
    // on hover when changed, the struck default and a revert glyph.
    Row {
        id: vcluster
        visible: !row.banded && (row.value !== "" || (row.changed && hh.hovered))
        anchors { right: slot.left; rightMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
        spacing: Tokens.s2
        Text {
            visible: row.value !== ""
            text: row.value
            color: Tokens.ink
            font.family: Tokens.ui; font.pixelSize: Tokens.fBody; font.weight: Font.Light
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: row.value !== "" && row.unit !== ""
            text: row.unit
            color: Tokens.inkMuted
            font.family: Tokens.ui; font.pixelSize: 10
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: row.changed && hh.hovered && row.def !== ""
            text: row.def + (row.unit ? " " + row.unit : "")
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.strikeout: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            visible: row.changed && hh.hovered
            width: 18; height: 18; radius: Tokens.radius
            color: rhi.hovered ? Tokens.tint10 : "transparent"
            border.width: Tokens.border
            border.color: rhi.hovered ? Tokens.lineStrong : Tokens.line
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.centerIn: parent; text: "\u21ba"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 11 }
            HoverHandler { id: rhi; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: row.resetRequested() }
        }
    }

    // the control: inline at the right, or a full-width band beneath the text.
    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: row.padH
        anchors.verticalCenter: row.banded ? undefined : parent.verticalCenter
        anchors.left: row.banded ? parent.left : undefined
        anchors.leftMargin: row.padH
        anchors.bottom: row.banded ? parent.bottom : undefined
        anchors.bottomMargin: row.padV
        width: row.banded ? undefined : row.controlWidth
        height: row.bandH
    }
}
