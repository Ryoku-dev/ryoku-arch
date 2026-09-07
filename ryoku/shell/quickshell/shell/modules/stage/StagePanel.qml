pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../../components"

// A floating panel inside the editor (docs/stage.md): a small window with a
// title row -- a grab handle to move it, a pin to keep it open after Done, and a
// close -- over a body no wider than 360 px. It remembers where it last sat on
// this monitor in stage-ui.json, so reopening it lands it back in place. The
// parent owns whether it is shown; this owns where it is and its chrome.
Item {
    id: panel

    property string title: ""
    property string monitor: ""
    property string kind: ""            // persistence key: depth | settings | style | add
    property bool pinned: false
    property real bodyWidth: 320        // clamped to <= 360
    property real defaultX: 60
    property real defaultY: 120

    default property alias content: body.data

    signal closeRequested()
    signal pinToggled()

    readonly property real chromeW: Math.min(360, Math.max(240, panel.bodyWidth))
    width: card.width
    height: card.height

    function _restore() {
        const p = StageSession.panelPos(panel.monitor, panel.kind);
        panel.x = p ? Math.max(0, Math.min((parent ? parent.width : 2000) - width, p.x)) : panel.defaultX;
        panel.y = p ? Math.max(0, Math.min((parent ? parent.height : 1200) - height, p.y)) : panel.defaultY;
    }
    Component.onCompleted: panel._restore()

    Rectangle {
        id: card
        width: panel.chromeW + 24
        height: header.height + body.implicitHeight + 20
        radius: Theme.radiusWidget
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)

        // Absorb every click so nothing falls through to the desktop below.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        // Title row: grab handle (move), title, pin, close.
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            height: 38

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "drag_indicator"
                    font.pixelSize: 18
                    color: Theme.onSurfaceVariant
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.title
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm
                    font.weight: Font.DemiBold
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                component IconBtn: Rectangle {
                    id: ib
                    property string icon: ""
                    property bool on: false
                    signal act()
                    width: 30; height: 30; radius: 15
                    color: ib.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                        : ibMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: ib.icon
                        font.pixelSize: 17
                        color: ib.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    }
                    MouseArea { id: ibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.act() }
                }
                IconBtn { icon: "push_pin"; on: panel.pinned; onAct: panel.pinToggled() }
                IconBtn { icon: "close"; onAct: panel.closeRequested() }
            }

            // Drag the panel by its title row, clamped to the surface.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 66
                cursorShape: Qt.SizeAllCursor
                property real px: 0
                property real py: 0
                onPressed: mouse => { px = mouse.x; py = mouse.y; }
                onPositionChanged: mouse => {
                    if (!(mouse.buttons & Qt.LeftButton) || !panel.parent)
                        return;
                    panel.x = Math.max(0, Math.min(panel.parent.width - panel.width, panel.x + mouse.x - px));
                    panel.y = Math.max(0, Math.min(panel.parent.height - panel.height, panel.y + mouse.y - py));
                }
                onReleased: StageSession.setPanelPos(panel.monitor, panel.kind, panel.x, panel.y)
            }
        }

        Column {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 2
            spacing: 10
        }
    }
}
