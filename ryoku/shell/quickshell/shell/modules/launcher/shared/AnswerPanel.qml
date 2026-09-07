import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// Instant-answer body panel, rendered under the divider when the "?" prefix
// has produced a DuckDuckGo instant answer for the current query. A small
// source eyebrow, the heading, and the answer body wrapped and capped so a
// long abstract cannot push the fallback Search row out of reach. Pure
// display: the Web provider fetches and hands us the parsed answer.
Item {
    id: root

    property real s: 1
    // Parsed answer from ddg.parseAnswer: { available, heading, text, source, url }.
    property var answer: ({ available: false, heading: "", text: "", source: "", url: "" })

    implicitHeight: col.implicitHeight

    // Prefer the source ("via Wikipedia") when DDG named one; a generic
    // "ANSWER" eyebrow fits calc/random-number answers that carry no source.
    readonly property string eyebrow: (answer && answer.source && String(answer.source).length > 0)
        ? I18n.tr("via %1").arg(answer.source)
        : I18n.tr("ANSWER")
    readonly property string heading: (answer && answer.heading) ? String(answer.heading) : ""
    readonly property string bodyText: (answer && answer.text) ? String(answer.text) : ""

    Column {
        id: col
        width: parent.width
        spacing: 5 * root.s

        Text {
            width: parent.width
            text: root.eyebrow
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
            font.letterSpacing: 1
        }

        Text {
            width: parent.width
            visible: root.heading.length > 0
            text: root.heading
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: Metrics.fontTitle * root.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.bodyText
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: Text.WordWrap
            // cap at five lines so a long Wikipedia abstract cannot swallow
            // the launcher; the ellipsis signals there is more to read.
            maximumLineCount: 5
            elide: Text.ElideRight
        }
    }
}
