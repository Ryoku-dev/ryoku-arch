pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk
import "lib/kana.js" as Kana
import shell.services as Svc
import Ryoku.Ui.Singletons as Ui

/**
 * Good-night face: a minimal greeting card: a vertical rule, a time-of-day
 * greeting stacked in two lines, the weekday in an angular faux-kana stroke
 * alphabet (self-contained, no font dependency, "Japanese style but readable"),
 * the date and the time, closed by a second rule. Drawn on its own dark panel as
 * the reference design, at a fixed 431x765 box scaled by clockScale, so s=1 is
 * pixel-identical to the tuned preview.
 */
Item {
    id: face

    property real underL: Scheme.wallLstar
    // a pinned colour ("" = the reference bright ink) paints this face's ink.
    property string inkColorA: ""
    readonly property real s: Config.clockScale
    readonly property color ink: face.inkColorA !== "" ? face.inkColorA : "#e9eaec"

    readonly property var t: Clk.parts(Now.date, Config.clock24h)
    readonly property var dp: Clk.dateParts(Now.date, Svc.Config.formatLoc)

    // greeting by hour, split into two stacked words (GOOD / <part>).
    readonly property string greetWord: {
        var h = Now.date.getHours();
        if (h >= 5 && h < 12) return Ui.I18n.tr("Morning");
        if (h >= 12 && h < 17) return Ui.I18n.tr("Afternoon");
        if (h >= 17 && h < 21) return Ui.I18n.tr("Evening");
        return Ui.I18n.tr("Night");
    }

    implicitWidth: box.width * face.s
    implicitHeight: box.height * face.s

    Item {
        id: box
        width: 431; height: 765
        transform: Scale { xScale: face.s; yScale: face.s }


        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 120
            spacing: 26

            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: 70; color: face.ink; opacity: 0.85 }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Ui.I18n.tr("Good").toUpperCase(); color: face.ink
                    font.family: "Inter Display"; font.weight: Font.Medium
                    font.pixelSize: 26; font.letterSpacing: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: face.greetWord.toUpperCase(); color: face.ink
                    font.family: "Inter Display"; font.weight: Font.Medium
                    font.pixelSize: 26; font.letterSpacing: 10
                }
            }

            Canvas {
                id: wk
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property string txt: face.dp.weekdayShort.toUpperCase()
                readonly property real cell: 62
                readonly property real gap: 20
                width: Kana.width(txt, cell, gap) + 12
                height: cell + 12
                onTxtChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.reset(); c.clearRect(0, 0, width, height);
                    Kana.draw(c, txt, 6, 6, cell, gap, 11, face.ink);
                }
                Component.onCompleted: requestPaint()
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Clk.pad2(face.dp.dom) + " " + face.dp.month.toUpperCase()
                color: face.ink
                font.family: "Inter Display"; font.weight: Font.DemiBold
                font.pixelSize: 22; font.letterSpacing: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.t.hh + ":" + face.t.mm + (Config.clock24h ? "" : " " + face.t.ampm)
                color: face.ink
                font.family: "Inter Display"; font.weight: Font.Medium
                font.pixelSize: 22; font.letterSpacing: 3
            }

            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: 70; color: face.ink; opacity: 0.85 }
        }
    }
}
