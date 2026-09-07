pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"

// A stage layer's on-desktop selection affordance (docs/stage.md): a hover /
// selected outline plus a name chip sized to the layer's opaque bounding box, so
// the subject reads as one clickable thing. The box is scanned once per rev from
// a small downscaled alpha probe, with a stacked centre-band fallback until the
// image lands. The subject slot draws the engine's cut ring while it runs.
// Self-contained (it inlines the outline + chip + ring) so it depends on nothing
// the widgets editor owns.
Item {
    id: lo
    anchors.fill: parent

    property string wallPath: ""
    property int slot: 0
    property int count: 1
    property bool selected: false

    signal picked()

    readonly property var sb: StageBackend
    readonly property string url: lo.sb.layerUrlFor(lo.wallPath, lo.slot)
    readonly property int ringPercent: (lo.slot === 0 && lo.sb.busy && lo.sb.stage === "cut") ? lo.sb.percent : -1

    // Normalised opaque bounds from the probe; a stacked fallback until it lands.
    property real bx0: 0.3
    property real by0: 0.35
    property real bx1: 0.7
    property real by1: 0.9
    property bool bboxReady: false
    readonly property real fbCY: Math.max(0.25, Math.min(0.75, 0.55 + (lo.slot - (lo.count - 1) / 2) * 0.16))

    readonly property rect box: {
        const x0 = lo.bboxReady ? lo.bx0 : 0.3;
        const y0 = lo.bboxReady ? lo.by0 : (lo.fbCY - 0.2);
        const x1 = lo.bboxReady ? lo.bx1 : 0.7;
        const y1 = lo.bboxReady ? lo.by1 : (lo.fbCY + 0.2);
        return Qt.rect(lo.width * x0, lo.height * y0,
            lo.width * (x1 - x0), lo.height * (y1 - y0));
    }

    visible: lo.box.width > 1 && lo.box.height > 1

    Canvas {
        id: probe
        width: 84
        height: 84
        visible: false
        property string src: lo.url
        onSrcChanged: {
            lo.bboxReady = false;
            if (probe.src !== "")
                probe.loadImage(probe.src);
        }
        onImageLoaded: probe.requestPaint()
        onPaint: {
            if (lo.url === "" || !probe.isImageLoaded(lo.url))
                return;
            const ctx = probe.getContext("2d");
            ctx.clearRect(0, 0, probe.width, probe.height);
            ctx.drawImage(lo.url, 0, 0, probe.width, probe.height);
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
                    lo.bx0 = minx / probe.width;
                    lo.by0 = miny / probe.height;
                    lo.bx1 = (maxx + 1) / probe.width;
                    lo.by1 = (maxy + 1) / probe.height;
                    lo.bboxReady = true;
                }
            } catch (e) {
                lo.bboxReady = false;
            }
        }
    }

    Rectangle {
        id: frame
        x: lo.box.x
        y: lo.box.y
        width: lo.box.width
        height: lo.box.height
        radius: Theme.radiusWidget
        color: lo.ringPercent >= 0 ? Qt.rgba(0, 0, 0, 0.28) : "transparent"
        border.width: lo.selected ? 2 : 1
        border.color: lo.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
            : hover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
            : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.28)
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        HoverHandler { id: hover }
        TapHandler { onTapped: lo.picked() }

        Canvas {
            id: ring
            anchors.centerIn: parent
            width: 54
            height: 54
            visible: lo.ringPercent >= 0
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2, cy = height / 2, r = width / 2 - 3;
                ctx.lineWidth = 3;
                ctx.strokeStyle = Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.25);
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.stroke();
                const frac = Math.max(0.04, Math.min(1, lo.ringPercent / 100));
                ctx.strokeStyle = Theme.primary;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
                ctx.stroke();
            }
            Connections {
                target: lo
                function onRingPercentChanged() { ring.requestPaint(); }
            }
            Component.onCompleted: ring.requestPaint()
        }
    }

    Rectangle {
        id: chip
        visible: (lo.selected || lo.ringPercent >= 0)
        x: Math.round(Math.max(8, Math.min(lo.width - width - 8,
            lo.box.x + lo.box.width / 2 - width / 2)))
        y: Math.round(lo.box.y > 40 ? lo.box.y - height - 6 : lo.box.y + lo.box.height + 6)
        width: label.implicitWidth + 22
        height: 28
        radius: 14
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.92)
        Text {
            id: label
            anchors.centerIn: parent
            text: lo.sb.layerLabel(lo.wallPath, lo.slot)
            color: Theme.inkOn(Theme.primary, Theme.onPrimary)
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 1
            font.weight: Font.DemiBold
        }
    }
}
