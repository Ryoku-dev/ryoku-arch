pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services
import Ryoku.Ui.Singletons

// Session-action confirmation dialog (contract 13 sec 2c). A ryoku-dialog layer
// surface holding one centred box: a 2px outline, radiusWindow corners, a centred
// wrapping title at the large label size (fontLg) with 40px vertical and 20px
// horizontal margins, then a two-button row where both buttons expand to split
// the row 50/50. Button order is negative (Cancel) on the LEFT, positive on the
// right. There is deliberately no Escape and no outside-click dismissal: the two
// buttons are the only exits, matching the reference's modal two-button prompt.
// The GTK modal flag has no layer-shell equivalent, so the box is self-masked
// (only it catches input) rather than blocking the whole screen; a stray click
// outside is a no-op and never dismisses. No reveal motion: the reference dialog
// simply appears (contract 13 sec 5 lists no dialog animation).
PanelWindow {
    id: root

    required property var modelData          // the screen this instance covers
    property string action: ""               // "logout" | "reboot" | "shutdown" | ""
    property string message: ""
    property string positiveLabel: ""
    property string negativeLabel: I18n.tr("Cancel")
    signal confirmed(string action)
    signal cancelled(string action)

    // measured reference geometry (contract 13 sec 2c); fixed px like the frame,
    // which does not scale with the monitor or font scale.
    readonly property int titleVMargin: 40
    readonly property int titleHMargin: 20
    readonly property int rowSpacing: 12

    screen: modelData
    visible: root.action !== ""
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "ryoku-dialog"

    anchors { top: true; bottom: true; left: true; right: true }

    // Only the box catches input; everything else clicks through. No path clears
    // the dialog on an outside click, so a stray press is a no-op.
    mask: Region {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
    }

    // Both buttons: a surface pill (radiusWidget, 8px padding) with a 14px label.
    // The row sets each width to half, so they expand equally. The subtle outline
    // and hover fill render the GTK button frame the reference draws.
    component DialogButton: Rectangle {
        id: btn
        required property string label
        signal clicked
        height: btnLabel.implicitHeight + 2 * Theme.paddingMd
        radius: Theme.radiusWidget
        color: btnArea.containsMouse ? Theme.surfaceContainerHigh : Theme.surface
        border.width: 1
        border.color: Theme.outlineVariant

        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: I18n.tr(btn.label)
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        id: box
        anchors.centerIn: parent

        // Box sizes to content: the title's natural width plus its horizontal
        // margins sets the inner width; the border wraps it.
        readonly property real innerWidth: title.implicitWidth + 2 * root.titleHMargin
        radius: Theme.radiusWindow
        color: Theme.surface
        border.width: Theme.borderWidth
        border.color: Theme.outline
        opacity: Theme.windowOpacity
        width: innerWidth + 2 * Theme.borderWidth
        height: col.height + 2 * Theme.borderWidth

        Column {
            id: col
            x: Theme.borderWidth
            y: Theme.borderWidth
            width: box.innerWidth
            spacing: root.rowSpacing

            // Title cell: the text centred with 40px above and below it.
            Item {
                width: parent.width
                height: title.implicitHeight + 2 * root.titleVMargin

                Text {
                    id: title
                    anchors.centerIn: parent
                    width: parent.width - 2 * root.titleHMargin
                    text: root.message
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontLg
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // Button row: negative (Cancel) left, positive right, each half wide.
            Row {
                width: parent.width
                spacing: 0

                DialogButton {
                    width: parent.width / 2
                    label: root.negativeLabel
                    onClicked: root.cancelled(root.action)
                }
                DialogButton {
                    width: parent.width / 2
                    label: root.positiveLabel
                    onClicked: root.confirmed(root.action)
                }
            }
        }
    }
}
