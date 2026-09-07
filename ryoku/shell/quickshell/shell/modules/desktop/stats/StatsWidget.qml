pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import Ryoku.Ui.Singletons as Ui
import "../Singletons"

// System stats panel for the wallpaper: a CPU area chart, ticked metric rows, a
// dual-line network chart, a disk-usage bar and a block of temps/battery. It is
// a 1:1 copy of the design preview (/tmp/refimg/p3_stats.qml): every
// coordinate, font, size and weight is verbatim; sample values are swapped for
// live feeds, and text ink follows the wallpaper luminance under the widget so
// it reads on any backdrop.
//
// The design is built at its native 521x916 inside `box` and scaled by root.s,
// so at s=1 the output is pixel-identical to the preview. CPU/mem/temp come from
// Sysinfo, GPU/network/disk/fan from StatsFeed, charge/level from Battery; both
// pollers are owner-refcounted and claimed only while this is active and visible.
Item {
    id: root

    property real underL: 0        // local wallpaper L* under the widget; ink adapts to it
    // WidgetSlot pins a hex here to paint this widget's ink; "" follows the wallpaper.
    property string inkColorA: ""
    property real s: 1             // scale (Config.statsScale)
    property bool active: true     // visible/enabled

    implicitWidth: box.width * root.s
    implicitHeight: box.height * root.s

    // claim the two pollers only while a surface wants them (MusicViz idiom), so
    // a disabled or covered panel costs nothing.
    readonly property bool wanted: root.active && root.visible
    onWantedChanged: {
        Sysinfo.setActive(root, root.wanted);
        StatsFeed.setActive(root, root.wanted);
    }
    Component.onCompleted: {
        Sysinfo.setActive(root, root.wanted);
        StatsFeed.setActive(root, root.wanted);
    }
    Component.onDestruction: {
        Sysinfo.setActive(root, false);
        StatsFeed.setActive(root, false);
    }

    // human byte-rate: B/s under 1 KiB, then KiB/s, MiB/s, GiB/s (1 decimal).
    function fmtRate(bps) {
        var b = Math.max(0, bps || 0);
        if (b < 1024)
            return b.toFixed(1) + " B/s";
        if (b < 1048576)
            return (b / 1024).toFixed(1) + " KiB/s";
        if (b < 1073741824)
            return (b / 1048576).toFixed(1) + " MiB/s";
        return (b / 1073741824).toFixed(1) + " GiB/s";
    }

    // shared peak for the network chart: both lines normalise to this so their
    // relative heights stay honest; the y-axis labels read off it too.
    readonly property real netMax: {
        var m = 0;
        var a = StatsFeed.netDownHist || [];
        var b = StatsFeed.netUpHist || [];
        for (var i = 0; i < a.length; i++)
            if (a[i] > m) m = a[i];
        for (var j = 0; j < b.length; j++)
            if (b[j] > m) m = b[j];
        return m;
    }
    // five axis labels, max at the top down to a bare "0 B/s" at the baseline.
    readonly property var netAxisLabels: {
        var out = [];
        for (var k = 4; k >= 0; k--) {
            var v = root.netMax * k / 4;
            out.push(v <= 0 ? "0 B/s" : root.fmtRate(v));
        }
        return out;
    }
    readonly property real diskFrac: StatsFeed.diskTotalGiB > 0
        ? Math.max(0, Math.min(1, StatsFeed.diskUsedGiB / StatsFeed.diskTotalGiB)) : 0

    Item {
        id: box
        width: 521
        height: 916
        transform: Scale { xScale: root.s; yScale: root.s }

        readonly property color ink: Theme.inkOn2(root.underL, root.inkColorA)
        readonly property color dim: Theme.inkDimOn2(root.underL, root.inkColorA)
        readonly property real lx: 64      // label left
        readonly property real rx: 456     // value right edge

        component Row1: Item {
            property string label: ""
            property string value: ""
            property color tick: "transparent"
            width: box.width; height: 30
            Rectangle { x: box.lx - 18; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 20; radius: 1; color: parent.tick; visible: parent.tick.a > 0 }
            Text { x: box.lx; anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: box.ink; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.Medium }
            Text { x: box.rx - implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: parent.value; color: box.ink; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.Medium }
        }


        // ---- CPU area chart ----
        Canvas {
            id: cpuCanvas
            x: 64; y: 60; width: 392; height: 70
            property var pts: Sysinfo.cpuHistory
            property color ink: box.ink
            onPtsChanged: requestPaint()
            onInkChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset();
                var arr = cpuCanvas.pts || [];
                var n = arr.length;
                if (n < 2) return;
                var dx = width/(n-1);
                function fy(v){ return height - Math.max(0, Math.min(1, v)) * height; }
                c.beginPath(); c.moveTo(0, height);
                for (var i=0;i<n;i++) c.lineTo(i*dx, fy(arr[i]));
                c.lineTo(width, height); c.closePath();
                c.fillStyle = Qt.rgba(cpuCanvas.ink.r, cpuCanvas.ink.g, cpuCanvas.ink.b, 0.28); c.fill();
                c.beginPath();
                for (i=0;i<n;i++){ var yy=fy(arr[i]); if(i===0)c.moveTo(0,yy); else c.lineTo(i*dx,yy); }
                c.lineWidth=2; c.strokeStyle=Qt.rgba(cpuCanvas.ink.r, cpuCanvas.ink.g, cpuCanvas.ink.b, 0.9); c.stroke();
            }
            Component.onCompleted: requestPaint()
        }

        Column {
            y: 150; width: parent.width; spacing: 0
            Row1 { label: "CPU"; value: (Sysinfo.cpu*100).toFixed(1)+"%"; tick: "#8fb7c9" }
            Row1 { label: "GPU"; value: StatsFeed.gpuPct+"%"; tick: "#8fb7c9" }
            Row1 { label: Ui.I18n.tr("Memory"); value: Sysinfo.memUsedGiB.toFixed(1)+" GiB" }
            Row1 { label: Ui.I18n.tr("GPU Power"); value: StatsFeed.gpuPowerW.toFixed(0)+" W" }
        }

        // ---- network chart ----
        // y-axis labels spread across the chart's own height (not a fixed
        // spacing), so the "0 B/s" baseline lands at the chart bottom instead of
        // spilling down onto the Download Rate row below.
        Item {
            x: 64; y: 300; width: 80; height: 108
            Repeater {
                model: root.netAxisLabels
                delegate: Text {
                    required property int index
                    required property string modelData
                    y: index * (parent.height - implicitHeight) / 4
                    text: modelData; color: box.dim; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.Normal
                }
            }
        }
        Canvas {
            id: netCanvas
            x: 150; y: 300; width: 306; height: 108
            property var dn: StatsFeed.netDownHist
            property var up: StatsFeed.netUpHist
            property real peak: root.netMax
            onDnChanged: requestPaint()
            onUpChanged: requestPaint()
            onPeakChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset();
                var pk = netCanvas.peak > 0 ? netCanvas.peak : 1;
                function line(arr,col){ if(!arr||arr.length<2) return; c.beginPath(); var n=arr.length,dx=width/(n-1);
                    for(var i=0;i<n;i++){var f=Math.max(0,Math.min(1,arr[i]/pk)); var yy=height-f*height; if(i===0)c.moveTo(0,yy);else c.lineTo(i*dx,yy);}
                    c.lineWidth=1.6; c.strokeStyle=col; c.stroke(); }
                line(netCanvas.up,"rgba(224,150,170,0.9)"); line(netCanvas.dn,"rgba(140,170,220,0.9)");
            }
            Component.onCompleted: requestPaint()
        }
        Column {
            y: 430; width: parent.width; spacing: 0
            Row1 { label: Ui.I18n.tr("Download Rate"); value: root.fmtRate(StatsFeed.downBps); tick: "#8caadc" }
            Row1 { label: Ui.I18n.tr("Upload Rate"); value: root.fmtRate(StatsFeed.upBps); tick: "#e096aa" }
        }

        // ---- disk progress ----
        Rectangle {
            x: 64; y: 540; width: 392; height: 10; radius: 5; color: "#2a2d33"
            Rectangle { width: parent.width*root.diskFrac; height: parent.height; radius: 5; color: "#bfe4c9" }
        }
        Column {
            y: 576; width: parent.width; spacing: 0
            Row1 { label: Ui.I18n.tr("Disk Used"); value: StatsFeed.diskUsedGiB.toFixed(1)+" GiB" }
            Row1 { label: Ui.I18n.tr("Total"); value: StatsFeed.diskTotalGiB.toFixed(1)+" GiB" }
        }

        // ---- temps / battery ----
        Column {
            y: 700; width: parent.width; spacing: 0
            Row1 { label: Ui.I18n.tr("CPU Temperature"); value: Sysinfo.tempC.toFixed(1)+" \u00b0C"; tick: "#8caadc" }
            Row1 { label: Ui.I18n.tr("GPU Temperature"); value: StatsFeed.gpuTempC.toFixed(0)+" \u00b0C"; tick: "#b79ae0" }
            Row1 { label: Ui.I18n.tr("Charging Rate"); value: Math.abs(Battery.rateW).toFixed(1)+" W"; tick: "#8fd0c4" }
            Row1 { label: Ui.I18n.tr("Fan Speed"); value: StatsFeed.fanRpm.toLocaleString(Qt.locale(), 'f', 1)+" RPM"; tick: "#cdd68a" }
            Row1 { label: Ui.I18n.tr("Battery"); value: Battery.pct+"%"; tick: "#e096aa" }
        }
    }
}
