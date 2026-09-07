pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Ryoku.Ui.Singletons

/**
 * A plain-QML preview of the all-in-one desktop face for the Desktop Widgets
 * section, so the chosen layout reads at a glance without leaning over to the
 * wallpaper. It mirrors the live aio/AioWidget.qml in its two fixed layouts
 * (wide 708x454, tall 714x885) with sample weather, sample date/time off `now`
 * and a static spectrum/waveform -- no cava feed, no Weather singleton. Ink is
 * fixed bright white (wide) or navy-tinted (tall) by design, exactly as in the
 * live widget; the background is transparent so the card surface shows through.
 * The design is drawn at its native pixel box with an implicit size; the page
 * scales the whole box to fit.
 */
Item {
    id: root

    property string style: "wide"      // wide | tall
    readonly property bool tall: root.style === "tall"

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    implicitWidth: root.tall ? 714 : 708
    implicitHeight: root.tall ? 885 : 454

    Loader {
        anchors.fill: parent
        sourceComponent: root.tall ? tallCard : wideCard
    }

    // ── WIDE (708 x 454) ────────────────────────────────────────────────────
    Component {
        id: wideCard
        Item {
            id: w
            implicitWidth: 708
            implicitHeight: 454
            readonly property color ink: "#ffffff"
            readonly property color dim: "#b9bcc2"
            readonly property string sym: "Material Symbols Rounded"

            // the letter-spaced date line: MONTH DD YYYY, each glyph split apart.
            readonly property string dateLine: {
                var parts = [Qt.formatDate(root.now, "MMMM").toUpperCase(),
                             Qt.formatDate(root.now, "dd"),
                             Qt.formatDate(root.now, "yyyy")];
                var out = [];
                for (var i = 0; i < parts.length; i++)
                    out.push(parts[i].split("").join(" "));
                return out.join("   ");
            }

            // ---- diagonal divider ----
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "#ffffff"; strokeWidth: 2; fillColor: "transparent"
                    startX: 360; startY: 20
                    PathLine { x: 250; y: 330 }
                }
            }

            // ---- weather cluster (top-left) ----
            Text {
                x: 44; y: 40
                text: "partly_cloudy_day"  // sun/cloud glyph (Material Symbols ligature)
                color: w.ink; font.family: w.sym; font.pixelSize: 46
            }
            Text {
                x: 150; y: 34
                text: "77\u00b0"; color: w.ink
                font.family: "Inter Display"; font.weight: Font.DemiBold; font.pixelSize: 52
            }
            Row {
                x: 150; y: 96; spacing: 14
                Row { spacing: 2
                    Text { text: "\u2191"; color: "#e0564b"; font.pixelSize: 22; font.family: "Inter Display"; font.weight: Font.Bold }
                    Text { text: "79\u00b0"; color: w.dim; font.pixelSize: 22; font.family: "Inter Display"; font.weight: Font.Medium }
                }
                Row { spacing: 2
                    Text { text: "\u2193"; color: "#4a90d9"; font.pixelSize: 22; font.family: "Inter Display"; font.weight: Font.Bold }
                    Text { text: "63\u00b0"; color: w.dim; font.pixelSize: 22; font.family: "Inter Display"; font.weight: Font.Medium }
                }
            }
            Text {
                x: 150; y: 128
                text: I18n.tr("Clear"); color: w.dim
                font.family: "Inter Display"; font.pixelSize: 24; font.weight: Font.Medium
            }

            // ---- big weekday ----
            Text {
                x: 34; y: 150
                text: Qt.formatDate(root.now, "ddd").toUpperCase(); color: w.ink
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: 200; font.letterSpacing: -6
            }

            // ---- time card (top-right): a true parallelogram leaning '/' with
            // the divider, filled white, holding an upright dark clock. Corner
            // points are the live widget's 0.28*height shear resolved. ----
            Item {
                id: card
                x: 392; y: 74; width: 296; height: 74
                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeColor: "transparent"; strokeWidth: 0; fillColor: "#ffffff"
                        startX: 20.72; startY: 0
                        PathLine { x: 316.72; y: 0 }
                        PathLine { x: 296; y: 74 }
                        PathLine { x: 0; y: 74 }
                        PathLine { x: 20.72; y: 0 }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: Qt.formatTime(root.now, "HH:mm"); color: "#1a1c1f"
                    font.family: "Inter Display"; font.weight: Font.Black; font.pixelSize: 46; font.letterSpacing: 1
                }
            }
            Text {
                x: 392; y: 168
                text: w.dateLine; color: w.dim
                font.family: "Inter Display"; font.weight: Font.Medium; font.pixelSize: 17; font.letterSpacing: 3
            }

            // ---- static spectrum (bottom-right): a fixed mountain of 34 bars
            // sharing a baseline, standing in for the live cava feed. ----
            Row {
                x: 330; y: 300; spacing: 4
                Repeater {
                    model: 34
                    Rectangle {
                        required property int index
                        width: 5; radius: 2.5; color: "#ffffff"
                        anchors.bottom: parent.bottom
                        readonly property real d: Math.abs(index - 16.5) / 16.5
                        height: Math.max(6, (1 - d * d) * 120 * (0.6 + 0.4 * Math.sin(index * 1.7)))
                    }
                }
            }
        }
    }

    // ── TALL (714 x 885) ──────────────────────────────────────────────────────
    Component {
        id: tallCard
        Item {
            id: t
            implicitWidth: 714
            implicitHeight: 885

            // ---- static waveform (top) ----
            Row {
                x: 92; y: 92; spacing: 3
                Repeater {
                    model: 74
                    Item {
                        id: bar
                        required property int index
                        width: 3; height: 70
                        Rectangle {
                            width: 2; radius: 1; color: "#aeb9d8"; opacity: 0.85
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            height: Math.max(2, (0.35 + 0.65 * Math.abs(Math.sin(bar.index * 0.9) * Math.cos(bar.index * 0.37))) * 56 * (bar.index % 2 ? 0.7 : 1))
                        }
                    }
                }
            }

            // ---- huge day number ----
            Text {
                id: day
                anchors.horizontalCenter: parent.horizontalCenter
                y: 150
                text: Qt.formatDate(root.now, "dd")
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: 620; font.letterSpacing: -30
                color: "#6f80ac"; opacity: 0.55
            }

            // ---- month overlaid ----
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 430
                text: Qt.formatDate(root.now, "MMMM").toUpperCase()
                font.family: "Inter Display"; font.weight: Font.Bold
                font.pixelSize: 92; font.letterSpacing: 6
                color: "#c7ccdb"; opacity: 0.92
            }

            // ---- time + underline ----
            Text {
                id: tm
                anchors.horizontalCenter: parent.horizontalCenter
                y: 560
                text: Qt.formatTime(root.now, "HH:mm")
                color: "#eef1f8"
                font.family: "Inter Display"; font.weight: Font.Medium
                font.pixelSize: 30; font.letterSpacing: 4
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 606; width: 120; height: 2; color: "#c7ccdb"
            }

            // ---- vertical weekday ----
            Text {
                text: Qt.formatDate(root.now, "dddd").toUpperCase()
                color: "#8790ad"
                font.family: "Inter Display"; font.weight: Font.Medium
                font.pixelSize: 22; font.letterSpacing: 8
                transformOrigin: Item.Center
                rotation: -90
                x: 150 - width / 2 + height / 2
                y: 430
            }

            // ---- faint stars ----
            Repeater {
                model: [[600, 250], [640, 300], [90, 640], [610, 690], [120, 200]]
                Rectangle {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]
                    width: 3; height: 3; radius: 1.5; color: "#cfd6ea"; opacity: 0.5
                }
            }
        }
    }
}
