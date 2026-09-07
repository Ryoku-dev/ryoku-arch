import QtQuick
import QtQuick.Controls
import Quickshell
import "../../shared/Singletons"
import "metrics.js" as MainMetrics
import "." as MainVariant
import Ryoku.Ui.Singletons

// The search row: the 力 brand glyph, the query field, an active-mode chip, and a
// result counter. The mode chip names the command the current prefix routes to
// (FILE, PKG, CALC...), so it is always clear what a query will do.
Item {
    id: root

    property real s: 1
    property string text: ""
    property string modeLabel: ""   // e.g. "FILE", "PKG", "CALC"; "" at root
    property int resultCount: 0
    property int totalCount: 0
    property bool gridActive: false
    property bool helpActive: false
    readonly property alias input: field

    signal moved(int delta)
    signal accepted()
    signal dismissed()
    signal keyPressed(var event)
    signal gridToggled()
    signal helpToggled()

    height: MainMetrics.searchHeight * s

    function focusField() { field.forceActiveFocus(); }
    function clear() { field.text = ""; }

    MainVariant.BrandMark {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: MainMetrics.padOuter * root.s
        size: 19 * root.s
    }

    TextField {
        id: field
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: glyph.right
        anchors.leftMargin: 12 * root.s
        anchors.right: chip.left
        anchors.rightMargin: 10 * root.s
        background: null
        padding: 0
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: MainMetrics.fontSearch * root.s
        placeholderText: I18n.tr("Search apps, type / for commands")
        placeholderTextColor: Theme.faint
        selectByMouse: true
        selectionColor: Theme.verm
        onTextChanged: root.text = text
        Keys.onUpPressed: root.moved(-1)
        Keys.onDownPressed: root.moved(1)
        Keys.onPressed: (e) => {
            root.keyPressed(e);
            if (e.accepted)
                return;
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.accepted();
                e.accepted = true;
            } else if (e.key === Qt.Key_F1) {
                root.helpToggled();
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape) {
                root.dismissed();
                e.accepted = true;
            }
        }
    }

    // active-mode chip: a small vermilion-tinted pill naming the command the
    // current prefix routes to. Hidden at the root (plain app search).
    Rectangle {
        id: chip
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: counter.left
        anchors.rightMargin: root.modeLabel.length ? 10 * root.s : 0
        width: root.modeLabel.length ? chipText.implicitWidth + 16 * root.s : 0
        height: 20 * root.s
        radius: Theme.radius
        visible: root.modeLabel.length > 0
        color: Theme.threadBg
        border.width: 1
        border.color: Theme.lineStrong

        Text {
            id: chipText
            anchors.centerIn: parent
            text: root.modeLabel
            color: Theme.vermLit
            font.family: Theme.mono
            font.pixelSize: 9 * root.s
            font.letterSpacing: 1
        }
    }

    Text {
        id: counter
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: helpBtn.left
        anchors.rightMargin: 10 * root.s
        text: root.text.length ? (root.resultCount + " / " + root.totalCount) : ""
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        font.features: { "tnum": 1 }
    }

    // help toggle: a plain "?" (ASCII, never tofu). Opens the cheat-sheet panel;
    // click again to close.
    Rectangle {
        id: helpBtn
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: gridBtn.left
        anchors.rightMargin: 4 * root.s
        width: 30 * root.s
        height: 30 * root.s
        radius: MainMetrics.radiusGlyph * root.s
        color: helpArea.containsMouse || root.helpActive ? Theme.threadBg : "transparent"

        Text {
            anchors.centerIn: parent
            text: "?"
            color: helpArea.containsMouse || root.helpActive ? Theme.vermLit : Theme.iconDim
            font.family: Theme.font
            font.pixelSize: 15 * root.s
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: helpArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.helpToggled()
        }
    }

    // all-apps toggle: a 3x3 tile glyph (drawn, not a font, so it can't tofu).
    // Vermilion when the grid is open or hovered. Clears any query and shows the
    // alphabetical grid; click again to close.
    Rectangle {
        id: gridBtn
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: (MainMetrics.padOuter - 6) * root.s
        width: 30 * root.s
        height: 30 * root.s
        radius: MainMetrics.radiusGlyph * root.s
        color: gridArea.containsMouse || root.gridActive ? Theme.threadBg : "transparent"

        Grid {
            anchors.centerIn: parent
            columns: 3
            rowSpacing: 3 * root.s
            columnSpacing: 3 * root.s
            Repeater {
                model: 9
                Rectangle {
                    width: 3.5 * root.s
                    height: 3.5 * root.s
                    radius: 1 * root.s
                    color: gridArea.containsMouse || root.gridActive ? Theme.vermLit : Theme.iconDim
                }
            }
        }

        MouseArea {
            id: gridArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.gridToggled()
        }
    }
}
