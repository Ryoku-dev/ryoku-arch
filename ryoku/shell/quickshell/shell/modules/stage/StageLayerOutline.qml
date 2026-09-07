pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// A stage layer's on-desktop selection affordance (docs/stage.md): the same
// hover/selected outline + name chip every element wears, sized to the layer's
// opaque bounding box so the subject reads as one clickable thing. The box is
// scanned once per rev from a small downscaled alpha probe, falling back to a
// stacked centre band when there is no image yet. Layers never drag, so the
// outline owns the click that selects them.
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

    StageOutline {
        anchors.fill: parent
        box: lo.box
        title: lo.sb.layerLabel(lo.wallPath, lo.slot)
        selected: lo.selected
        clickable: true
        // The subject (slot 0) shows the engine's cut progress as a ring.
        ringPercent: (lo.slot === 0 && lo.sb.busy && lo.sb.stage === "cut") ? lo.sb.percent : -1
        onPicked: lo.picked()
    }
}
