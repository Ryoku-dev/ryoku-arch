pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import Ryoku.Ui.Singletons

// A vertical specimen poster for a section's dead right column: a framed noir
// image, stacked editorial type -- a // code line, a big JP title, a chapter
// numeral and label, a short quote, a scannable barcode and a kanji seal. Pure
// decoration in the reference's noir register: ink only, no accent, no control.
// Decor is the horizontal sibling that fills a wide dead slot; this fills a tall
// one. With no art it falls back to the procedural DitherField.
Item {
    id: pl
    visible: Tokens.showPosters

    property string code: "RYOKU"   // the // code line and the barcode
    property string title: ""       // big JP title
    property string sub: ""         // tracked english/romaji under the title
    property string chapter: ""     // big numeral, e.g. 07
    property string label: ""       // the chapter's name, tracked
    property string quote: ""       // fine-print english
    property string tate: ""        // optional vertical tategaki phrase
    property string seal: "\u529b"  // seal glyph (力 by default)
    property string motto: ""       // an editorial epigraph across the specimen head
    property string art: ""         // bare filename under ~/Pictures/ryodecors
    property real seed: 1.0         // DitherField fallback seed
    property real ditherFreq: 1.0

    readonly property bool hasArt: pl.art !== ""
    readonly property bool wide: pl.width >= 300

    // pure chrome: keep screen readers on the page's real controls.
    Accessible.ignored: true

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: "transparent"
        border.width: Tokens.border
        border.color: Tokens.line

        // ── header: code, JP title, subtitle, rule ──────────────────────────
        Column {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.s4 }
            spacing: Tokens.s2

            Text {
                text: "\u002f\u002f " + pl.code
                color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: 1.2
            }
            Text {
                visible: pl.title !== ""
                width: header.width
                text: pl.title
                color: Tokens.ink
                font.family: Tokens.jp; font.pixelSize: 28; font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                visible: pl.sub !== ""
                text: pl.sub
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
            }
            Rectangle { width: header.width; height: 1; color: Tokens.lineSoft }
        }

        // ── footer: chapter block, quote, barcode + seal ────────────────────
        Column {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Tokens.s4 }
            spacing: Tokens.s3

            Row {
                visible: pl.chapter !== "" || pl.label !== ""
                spacing: Tokens.s3

                Text {
                    text: pl.chapter
                    color: Tokens.ink
                    font.family: Tokens.display; font.pixelSize: Tokens.fHero
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: I18n.tr("CHAPTER")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                    }
                    Text {
                        visible: pl.label !== ""
                        text: I18n.tr(pl.label)
                        color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                    }
                }
            }

            Text {
                visible: pl.quote !== ""
                width: footer.width
                text: pl.quote
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Item {
                width: footer.width
                height: 26

                Barcode {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    visible: pl.width >= 200
                    text: pl.code; unit: 0.9; barHeight: 15
                }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 26; height: 26
                    color: "transparent"
                    border.width: Tokens.border; border.color: Tokens.line
                    Text {
                        anchors.centerIn: parent
                        text: pl.seal
                        color: Tokens.inkDim
                        font.family: Tokens.jp; font.pixelSize: 14
                    }
                }
            }
        }

        // ── the framed specimen, filling the middle ─────────────────────────
        Item {
            id: artPanel
            anchors {
                left: parent.left; right: parent.right
                top: header.bottom; bottom: footer.top
                leftMargin: Tokens.s4; rightMargin: Tokens.s4
                topMargin: Tokens.s3; bottomMargin: Tokens.s3
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Tokens.border; border.color: Tokens.line
                clip: true

                // an editorial epigraph across the specimen's head, set in
                // Fraunces italic; the art sits below it, never crowded.
                Text {
                    id: epigraph
                    visible: pl.motto !== ""
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.s3 }
                    text: pl.motto
                    color: Tokens.inkMuted
                    font.family: Tokens.display; font.italic: true; font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                DitherField {
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        top: epigraph.visible ? epigraph.bottom : parent.top
                        margins: 1; topMargin: epigraph.visible ? Tokens.s2 : 1
                    }
                    visible: !pl.hasArt || img.status === Image.Error
                    freq: pl.ditherFreq; seed: pl.seed
                }
                // the specimen floats on its own #000 ground, so PreserveAspectFit
                // shows it whole with margins that vanish into the panel -- no crop.
                Image {
                    id: img
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        top: epigraph.visible ? epigraph.bottom : parent.top
                        margins: 1; topMargin: epigraph.visible ? Tokens.s2 : 1
                    }
                    visible: pl.hasArt && img.status !== Image.Error
                    source: pl.hasArt ? Ryodecors.dir + pl.art : ""
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                    asynchronous: true
                }

                // an optional faint tategaki phrase down the specimen's edge.
                Column {
                    visible: pl.tate !== "" && pl.wide
                    anchors { right: parent.right; top: parent.top; margins: Tokens.s2 }
                    spacing: 1

                    Repeater {
                        model: pl.tate.length
                        Text {
                            required property int index
                            text: pl.tate.charAt(index)
                            color: Tokens.inkFaint
                            font.family: Tokens.jp; font.pixelSize: 11
                        }
                    }
                }
            }
            Ticks { color: Tokens.lineStrong; arm: 10 }
        }
    }
}
