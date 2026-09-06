pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../../components"

// One layer's on-desktop edit control (docs/stage.md), shown only in edit mode:
// a soft outline around the layer plane and a chip sitting on the subject with
// a one-tap Behind <-> In front flip, plus a near <-> far control in Parallax.
// The chip is placed on the layer's opaque bounding box, cheaply scanned once
// per rev from a downscaled alpha probe, falling back to a stacked centre.
Item {
    id: chip
    anchors.fill: parent

    property string wallPath: ""
    property int slot: 0
    property int count: 1
    property bool parallax: false

    readonly property var sb: StageBackend
    readonly property string url: chip.sb.layerUrlFor(chip.wallPath, chip.slot)
    readonly property bool front: chip.sb.layerFront(chip.wallPath, chip.slot)

    // Opaque-bounds probe: a small alpha scan gives the subject's centre so the
    // chip lands on it; any failure (or no image) falls back to a stacked centre.
    property real bx: 0.5
    property real by: 0.6
    property bool bboxReady: false
    readonly property real fallbackY: Math.max(0.2, Math.min(0.8, 0.55 + (chip.slot - (chip.count - 1) / 2) * 0.16))
    readonly property real anchorX: chip.bboxReady ? chip.bx : 0.5
    readonly property real anchorY: chip.bboxReady ? chip.by : chip.fallbackY

    Canvas {
        id: probe
        width: 84
        height: 84
        visible: false
        property string src: chip.url
        onSrcChanged: {
            chip.bboxReady = false;
            if (probe.src !== "")
                probe.loadImage(probe.src);
        }
        onImageLoaded: probe.requestPaint()
        onPaint: {
            if (chip.url === "" || !probe.isImageLoaded(chip.url))
                return;
            const ctx = probe.getContext("2d");
            ctx.clearRect(0, 0, probe.width, probe.height);
            ctx.drawImage(chip.url, 0, 0, probe.width, probe.height);
            try {
                const d = ctx.getImageData(0, 0, probe.width, probe.height).data;
                let minx = probe.width, miny = probe.height, maxx = 0, maxy = 0, found = false;
                for (let y = 0; y < probe.height; y++) {
                    for (let x = 0; x < probe.width; x++) {
                        if (d[(y * probe.width + x) * 4 + 3] > 24) {
                            found = true;
                            if (x < minx) minx = x;
                            if (x > maxx) maxx = x;
                            if (y < miny) miny = y;
                            if (y > maxy) maxy = y;
                        }
                    }
                }
                if (found) {
                    chip.bx = (minx + maxx) / 2 / probe.width;
                    chip.by = (miny + maxy) / 2 / probe.height;
                    chip.bboxReady = true;
                }
            } catch (e) {
                chip.bboxReady = false;
            }
        }
    }

    // Soft outline for the layer plane, inset per slot so stacked layers read apart.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 12 + chip.slot * 12
        radius: Theme.radiusWidget
        color: "transparent"
        border.width: 2
        border.color: chip.front
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.35)
    }

    // The chip pill.
    Rectangle {
        id: pill
        x: Math.round(Math.max(8, Math.min(chip.width - width - 8, chip.width * chip.anchorX - width / 2)))
        y: Math.round(Math.max(40, Math.min(chip.height - 120, chip.height * chip.anchorY + 12)))
        width: row.implicitWidth + 20
        height: 40
        radius: 20
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.sb.layerLabel(chip.wallPath, chip.slot)
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: Font.DemiBold
            }

            // One-tap Behind <-> In front flip.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: flipRow.implicitWidth + 18
                height: 28
                radius: 14
                color: chip.front ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Row {
                    id: flipRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "swap_vert"
                        font.pixelSize: 15
                        color: chip.front ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.front ? "In front" : "Behind"
                        color: chip.front ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chip.sb.setLayerFront(chip.slot, !chip.front)
                }
            }

            // near <-> far drift, only in Parallax.
            Item {
                id: nf
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.parallax
                width: 128
                height: 28
                readonly property real depth: chip.sb.layerDepth(chip.wallPath, chip.slot)
                Text {
                    id: nearLbl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "near"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                Text {
                    id: farLbl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "far"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 3
                }
                Rectangle {
                    id: track
                    anchors.left: nearLbl.right
                    anchors.right: farLbl.left
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5
                    radius: 2.5
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.18)
                    Rectangle {
                        width: 13
                        height: 13
                        radius: 6.5
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(track.width - 13, (track.width - 13) * nf.depth))
                        color: Theme.surface
                        border.width: 2
                        border.color: Theme.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        cursorShape: Qt.SizeHorCursor
                        function set(mx) {
                            const frac = Math.max(0, Math.min(1, (mx - 6.5) / Math.max(1, track.width - 13)));
                            chip.sb.setLayerDepth(chip.slot, frac);
                        }
                        onPressed: mouse => set(mouse.x)
                        onPositionChanged: mouse => { if (mouse.buttons & Qt.LeftButton) set(mouse.x); }
                    }
                }
            }
        }
    }
}
