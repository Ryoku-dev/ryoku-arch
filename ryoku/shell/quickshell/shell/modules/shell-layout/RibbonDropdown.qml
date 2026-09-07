pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "../stage/Singletons" as StageCfg
import "../../components"

// A ribbon button that drops a panel down from itself (docs/stage.md), Paint's
// Colours/Rotate way: one panel open at a time, keyed on StageSession.panel, it
// closes on Escape or a click elsewhere (the canvas handles the outside click).
// The panel is reparented into the session's overlay so it draws over the canvas
// and clears the ribbon, anchored under the button and clamped on screen.
Item {
    id: dd

    property Item overlay: null
    property string key: ""
    property string label: ""
    property string icon: ""
    property real panelW: 320
    // Overlay-space Y where the panel's top sits (just under the ribbon).
    property real dropY: 0

    default property alias body: bodyCol.data

    readonly property bool open: StageCfg.StageSession.panel === dd.key

    implicitWidth: btn.width
    implicitHeight: 44
    width: implicitWidth
    height: 44

    Rectangle {
        id: btn
        anchors.verticalCenter: parent.verticalCenter
        width: btnRow.implicitWidth + 26
        height: 40
        radius: Theme.radiusWidget
        color: dd.open ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            : ma.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
        border.width: dd.open ? 0 : 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: dd.icon.length > 0
                text: dd.icon
                font.pixelSize: 17
                color: dd.open ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: dd.label
                color: dd.open ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: Font.DemiBold
            }
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: dd.open ? "expand_less" : "expand_more"
                font.pixelSize: 18
                color: dd.open ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurfaceVariant
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: StageCfg.StageSession.togglePanel(dd.key)
        }
    }

    // The panel, reparented into the overlay above the canvas.
    Rectangle {
        id: panel
        parent: dd.overlay
        visible: dd.open && dd.overlay !== null
        z: 50
        width: dd.panelW
        height: Math.min(dd.overlay ? dd.overlay.height - dd.dropY - 16 : 600, bodyCol.implicitHeight + 24)
        radius: 12
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.98)
        border.width: 1
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)

        x: {
            if (!dd.overlay || !dd.open)
                return 0;
            const p = dd.mapToItem(dd.overlay, 0, 0);
            const maxX = dd.overlay.width - dd.panelW - 12;
            return Math.max(12, Math.min(maxX, p.x));
        }
        y: dd.dropY

        // Absorb clicks so a press inside the panel never falls to the canvas.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 12
            contentWidth: width
            contentHeight: bodyCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: bodyCol
                width: flick.width
                spacing: 8
            }
        }
    }
}
