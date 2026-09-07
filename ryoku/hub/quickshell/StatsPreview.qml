pragma ComponentBehavior: Bound
import QtQuick
import Ryoku.Ui.Singletons

/**
 * A plain-QML preview of the system-stats desktop panel for the Desktop Widgets
 * section: a CPU area chart, ticked metric rows, a dual-line network chart, a
 * disk-usage bar and a block of temps/battery. A 1:1 copy of the tuned design
 * /tmp/refimg/p3_stats.qml with fixed sample values -- no Sysinfo/StatsFeed
 * feeds, no live readings. Ink stays bright white by design and the background
 * is transparent so the card surface shows through. Drawn at its native 521x916
 * box with an implicit size; the page scales the whole box to fit.
 */
Item {
    id: root

    property var now: new Date()   // optional; the sample charts are static

    implicitWidth: 521
    implicitHeight: 916

    readonly property color ink: "#eceef2"
    readonly property color dim: "#c7ccd4"
    readonly property real lx: 64      // label left
    readonly property real rx: 456     // value right edge

    component Row1: Item {
        property string label: ""
        property string value: ""
        property color tick: "transparent"
        width: root.width; height: 30
        Rectangle { x: root.lx - 18; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 20; radius: 1; color: parent.tick; visible: parent.tick.a > 0 }
        Text { x: root.lx; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr(parent.label); color: root.ink; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.Medium }
        Text { x: root.rx - implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: parent.value; color: root.ink; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.Medium }
    }

    // ---- CPU area chart ----
    Canvas {
        x: 64; y: 60; width: 392; height: 70
        onPaint: {
            var c = getContext("2d"); c.reset();
            var pts = [0.3, 0.35, 0.55, 0.42, 0.7, 0.5, 0.85, 0.45, 0.6, 0.4, 0.38, 0.5, 0.44, 0.3, 0.32, 0.28, 0.34, 0.3, 0.42, 0.36, 0.3, 0.28, 0.33, 0.3];
            var n = pts.length, dx = width / (n - 1);
            c.beginPath(); c.moveTo(0, height);
            for (var i = 0; i < n; i++) c.lineTo(i * dx, height - pts[i] * height);
            c.lineTo(width, height); c.closePath();
            c.fillStyle = "rgba(210,214,222,0.28)"; c.fill();
            c.beginPath();
            for (i = 0; i < n; i++) { var yy = height - pts[i] * height; if (i === 0) c.moveTo(0, yy); else c.lineTo(i * dx, yy); }
            c.lineWidth = 2; c.strokeStyle = "rgba(236,238,242,0.9)"; c.stroke();
        }
        Component.onCompleted: requestPaint()
    }

    Column {
        y: 150; width: parent.width; spacing: 0
        Row1 { label: I18n.tr("CPU"); value: "22.5%"; tick: "#8fb7c9" }
        Row1 { label: I18n.tr("GPU"); value: "0%"; tick: "#8fb7c9" }
        Row1 { label: I18n.tr("Memory"); value: "3.8 GiB" }
        Row1 { label: I18n.tr("GPU Power"); value: "1 W" }
    }

    // ---- network chart ----
    Column {
        x: 64; y: 300; spacing: 14
        Repeater {
            model: ["5.4 KiB/s", "4.1 KiB/s", "2.7 KiB/s", "1.4 KiB/s", "0 B/s"]
            Text { required property var modelData; text: modelData; color: root.dim; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.Normal }
        }
    }
    Canvas {
        x: 150; y: 300; width: 306; height: 108
        onPaint: {
            var c = getContext("2d"); c.reset();
            function line(arr, col) {
                c.beginPath(); var n = arr.length, dx = width / (n - 1);
                for (var i = 0; i < n; i++) { var yy = height - arr[i] * height; if (i === 0) c.moveTo(0, yy); else c.lineTo(i * dx, yy); }
                c.lineWidth = 1.6; c.strokeStyle = col; c.stroke();
            }
            var dn = [0.05, 0.1, 0.08, 0.9, 0.12, 0.06, 0.2, 0.1, 0.3, 0.15, 0.1, 0.25, 0.12, 0.4, 0.1];
            var up = [0.02, 0.03, 0.02, 0.05, 0.03, 0.02, 0.06, 0.03, 0.04, 0.03, 0.02, 0.05, 0.03, 0.06, 0.02];
            line(up, "rgba(224,150,170,0.9)"); line(dn, "rgba(140,170,220,0.9)");
        }
        Component.onCompleted: requestPaint()
    }
    Column {
        y: 430; width: parent.width; spacing: 0
        Row1 { label: I18n.tr("Download Rate"); value: "344.0 B/s"; tick: "#8caadc" }
        Row1 { label: I18n.tr("Upload Rate"); value: "0.0 B/s"; tick: "#e096aa" }
    }

    // ---- disk progress ----
    Rectangle {
        x: 64; y: 540; width: 392; height: 10; radius: 5; color: "#2a2d33"
        Rectangle { width: parent.width * 0.322; height: parent.height; radius: 5; color: "#bfe4c9" }
    }
    Column {
        y: 576; width: parent.width; spacing: 0
        Row1 { label: I18n.tr("Disk Used"); value: "55.6 GiB" }
        Row1 { label: I18n.tr("Total"); value: "172.7 GiB" }
    }

    // ---- temps / battery ----
    Column {
        y: 700; width: parent.width; spacing: 0
        Row1 { label: I18n.tr("CPU Temperature"); value: "45.3 \u00b0C"; tick: "#8caadc" }
        Row1 { label: I18n.tr("GPU Temperature"); value: "42 \u00b0C"; tick: "#b79ae0" }
        Row1 { label: I18n.tr("Charging Rate"); value: "30.3 W"; tick: "#8fd0c4" }
        Row1 { label: I18n.tr("Fan Speed"); value: "2,712.0 RPM"; tick: "#cdd68a" }
        Row1 { label: I18n.tr("Battery"); value: "78%"; tick: "#e096aa" }
    }
}
