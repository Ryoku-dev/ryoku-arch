pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../stage"
import "../stage/Singletons" as Stage

// The Edit shell canvas (docs/stage.md): what the ribbon acts on, drawn over the
// lifted desktop. On the Bar / Dock / Menus tabs it outlines every surface with
// its name and edge (placed inside the desktop, next to the surface) and, for
// the selected surface, shows its legal edges as clickable strips (a strip is
// the Edge control). On the Depth / Parallax tabs it outlines the subject and
// each layer (click to select) and rides the cut ring on the subject.
Item {
    id: canvas
    anchors.fill: parent

    property string monitor: ""
    // The y below which the ribbon sits, so top-edge marks are not hidden by it.
    property real topReserve: 150

    readonly property var ses: Stage.StageSession
    readonly property var sb: Stage.StageBackend
    readonly property string tabId: canvas.ses.tab
    readonly property bool surfaceTab: canvas.tabId === "bar" || canvas.tabId === "dock" || canvas.tabId === "menus"
    readonly property bool depthTab: canvas.tabId === "depth" || canvas.tabId === "parallax"
    readonly property string wall: canvas.sb.current
    readonly property int layerCount: canvas.sb.layerCountFor(canvas.wall)

    readonly property string stripSurface: canvas.tabId === "bar" ? "bar"
        : canvas.tabId === "dock" ? "dock"
        : canvas.tabId === "menus" ? (Layout.menuIds.indexOf(canvas.ses.selected) >= 0 ? canvas.ses.selected : "")
        : ""

    function cap(s) { return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    // A click on bare desktop closes an open panel first, else drops the
    // selection (docs/stage.md: click elsewhere closes the drop-down).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (canvas.ses.panel !== "")
                canvas.ses.closePanel();
            else if (!canvas.depthTab)
                canvas.ses.deselect();
        }
    }

    // Clickable legal-edge strips for the selected surface.
    Repeater {
        model: canvas.stripSurface !== "" ? Layout.legalEdges(canvas.stripSurface) : []
        delegate: Rectangle {
            id: strip
            required property string modelData
            readonly property bool horiz: strip.modelData === "top" || strip.modelData === "bottom"
            readonly property bool current: Layout.edgeOf(canvas.stripSurface) === strip.modelData
            readonly property real inset: 20

            x: strip.modelData === "left" ? strip.inset
                : strip.modelData === "right" ? canvas.width - width - strip.inset
                : 72
            y: strip.modelData === "top" ? canvas.topReserve
                : strip.modelData === "bottom" ? canvas.height - height - strip.inset
                : canvas.topReserve + 60
            width: strip.horiz ? canvas.width - 144 : 44
            height: strip.horiz ? 44 : canvas.height - (canvas.topReserve + 60) - strip.inset - 60

            radius: Theme.radiusWidget
            color: strip.current ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                : sMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
            border.width: 1
            border.color: strip.current ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.7)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                anchors.centerIn: parent
                text: canvas.cap(strip.modelData)
                color: strip.current ? Theme.primary : Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 1
                font.weight: strip.current ? Font.DemiBold : Font.Normal
                rotation: strip.horiz ? 0 : 0
            }
            MouseArea {
                id: sMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Layout.setEdge(canvas.stripSurface, strip.modelData)
            }
        }
    }

    // A labelled marker per surface, inside the desktop next to its edge.
    Repeater {
        model: canvas.surfaceTab ? Layout.surfaces : []
        delegate: Rectangle {
            id: mark
            required property var modelData
            readonly property string edge: Layout.edgeOf(mark.modelData.id)
            readonly property int order: Layout.orderOnEdge(mark.modelData.id)
            readonly property bool selected: canvas.stripSurface === mark.modelData.id

            width: markRow.implicitWidth + 24
            height: 32
            radius: Theme.radiusWidget
            x: mark.edge === "left" ? 76
                : mark.edge === "right" ? canvas.width - width - 76
                : Math.round((canvas.width - width) / 2)
            y: mark.edge === "top" ? canvas.topReserve + 56 + mark.order * 40
                : mark.edge === "bottom" ? canvas.height - height - 76 - mark.order * 40
                : Math.round(canvas.height / 2) - 60 + mark.order * 40
            color: mark.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
            border.width: mark.selected ? 0 : 1
            border.color: mMa.containsMouse
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Row {
                id: markRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: mark.modelData.label
                    color: mark.selected ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: canvas.cap(mark.edge)
                    color: mark.selected ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 2
                }
            }
            MouseArea {
                id: mMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (canvas.tabId === "menus" && mark.modelData.kind === "menu")
                        canvas.ses.select(mark.modelData.id);
                }
            }
        }
    }

    // Subject and layer outlines on the Depth / Parallax tabs.
    Repeater {
        model: canvas.depthTab ? canvas.layerCount : 0
        delegate: StageLayerOutline {
            required property int index
            anchors.fill: parent
            wallPath: canvas.wall
            slot: index
            count: canvas.layerCount
            selected: canvas.ses.selected === ("layer:" + index)
            onPicked: canvas.ses.select("layer:" + index)
        }
    }
}
