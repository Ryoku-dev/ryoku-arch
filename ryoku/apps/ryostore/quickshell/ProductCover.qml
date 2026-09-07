import QtQuick
import Ryoku.Ui.Singletons
import "lib/store.js" as StoreLogic

Item {
    id: cover

    required property var item
    property string mode: "cover"       // cover | hero | plate
    property bool selected: false
    property bool active: true
    property string artOverride: ""     // a caller showing the other look in place of ours

    readonly property bool tile: mode === "cover"
    // The catalogue shows a product as its author made it: `art` is the dithered
    // bake and `artRaw` the colour original, so browse leads with the colour and
    // the dither is what a detail view (or the install) opts into.
    readonly property string coverArt: {
        const raw = String(item && item.artRaw || "");
        return raw.length > 0 ? raw : String(item && item.art || "");
    }
    readonly property bool hasArtwork: cover.coverArt !== ""
    readonly property bool hasIdentity: Boolean(item && (item.id || item.name))
    readonly property string coverTitle: String(item && (item.name || item.id) || I18n.tr("Untitled"))
    readonly property color coverSurface: item && item.surface ? item.surface : Tokens.paperLift
    readonly property color coverAccent: item && item.accent ? item.accent : Tokens.inkDim
    readonly property var status: StoreLogic.statusLabels(item)
    readonly property string statusTag: (status.length > 0 && status[0] !== "AVAILABLE") ? status[0] : ""
    readonly property bool flagged: statusTag === "UPDATE" || statusTag === "ACTIVE" || statusTag === "ENABLED"

    clip: true
    Accessible.role: Accessible.Graphic
    Accessible.ignored: !cover.hasIdentity
    Accessible.name: [
        coverTitle,
        String(item && (item.categoryName || item.category) || ""),
        cover.status.map(s => I18n.tr(s)).join(", ")
    ].filter(Boolean).join(", ")

    Rectangle {
        anchors.fill: parent
        color: cover.coverSurface
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.rgba(cover.coverAccent.r, cover.coverAccent.g,
                               cover.coverAccent.b, 0.42)
            }
            GradientStop { position: 0.54; color: cover.coverSurface }
            GradientStop {
                position: 1
                color: Qt.darker(cover.coverSurface, 1.7)
            }
        }
    }

    Rectangle {
        width: parent.width * 0.82
        height: width
        anchors.centerIn: parent
        visible: !cover.hasArtwork && cover.hasIdentity
        rotation: -18
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Tokens.border)
        border.color: Qt.rgba(cover.coverAccent.r, cover.coverAccent.g,
                              cover.coverAccent.b, 0.45)
    }

    Text {
        anchors.centerIn: parent
        visible: !cover.hasArtwork && cover.hasIdentity
        text: cover.coverTitle.slice(0, 2).toUpperCase()
        color: Qt.rgba(cover.coverAccent.r, cover.coverAccent.g,
                       cover.coverAccent.b, 0.78)
        font.family: Tokens.display
        font.pixelSize: Math.max(Tokens.fHero, Math.min(parent.width, parent.height) * 0.28)
        font.weight: Font.Black
        font.letterSpacing: -2
    }

    ProductMedia {
        anchors.fill: parent
        source: cover.artOverride !== "" ? cover.artOverride : cover.coverArt
        mode: cover.mode
        surface: cover.coverSurface
        active: cover.active
    }

    // ── tile chrome (grid tiles only) ──────────────────────────────────────
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(parent.height * 0.6, 132)
        visible: cover.tile && cover.hasIdentity
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.58; color: "#b0000000" }
            GradientStop { position: 1; color: "#ec000000" }
        }
    }

    // status tag, accent-tinted for a live product, so a glance finds the
    // active rice or an available update in the strip
    Row {
        visible: cover.tile && cover.statusTag !== ""
        anchors { top: parent.top; left: parent.left; margins: Tokens.s2 }
        spacing: Tokens.s1

        Rectangle {
            width: tagText.implicitWidth + Tokens.s2 * 2
            height: tagText.implicitHeight + Tokens.s1 * 2
            radius: Tokens.radius
            color: cover.flagged
                    ? Qt.rgba(cover.coverAccent.r, cover.coverAccent.g, cover.coverAccent.b, 0.9)
                    : "#b3000000"
            border.width: Tokens.border
            border.color: cover.flagged ? "transparent" : "#33ffffff"

            Text {
                id: tagText
                anchors.centerIn: parent
                text: I18n.tr(cover.statusTag)
                color: cover.flagged ? Qt.rgba(0, 0, 0, 0.86) : "#e8ffffff"
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
            }
        }
    }

    Column {
        objectName: "ryostore-cover-metadata"
        visible: cover.tile && cover.hasIdentity
        x: Tokens.s3
        width: parent.width - Tokens.s3 * 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.s3
        spacing: Tokens.s1

        Text {
            width: parent.width
            text: cover.coverTitle
            color: "#f5f3ef"
            font.family: Tokens.display
            font.pixelSize: Tokens.fRow
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: String(cover.item && (cover.item.categoryName || cover.item.category) || "").toUpperCase()
            color: "#b8ffffff"
            font.family: Tokens.mono
            font.pixelSize: Tokens.fMicro
            font.letterSpacing: Tokens.trackLabel
            elide: Text.ElideRight
        }
    }

    // selection: an accent seam along the bottom plus a frame, so the focused
    // tile carries the product's own colour
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Tokens.border * 3
        visible: cover.tile && cover.selected
        color: cover.coverAccent
    }

    Rectangle {
        anchors.fill: parent
        visible: cover.tile
        color: "transparent"
        border.width: cover.selected ? Tokens.border * 2 : Tokens.border
        border.color: cover.selected
                ? Qt.rgba(cover.coverAccent.r, cover.coverAccent.g, cover.coverAccent.b, 0.9)
                : "#22ffffff"
    }
}
