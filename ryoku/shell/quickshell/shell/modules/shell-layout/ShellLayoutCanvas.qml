pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../stage"
import "../stage/Singletons" as StageCfg

// The Edit shell layout session's canvas (docs/stage.md): the same island scoped
// to the shell's surfaces, and a labelled outline over each surface at its
// current edge. Its host (a per-monitor overlay window) fills it to the screen.
// The island's second row offers the edges the selected surface may take and
// applies on click; two surfaces on one edge stack so both stay reachable.
Item {
    id: canvas
    anchors.fill: parent

    property string monitor: ""

    readonly property var ses: StageCfg.StageSession
    readonly property var selSurface: Layout.surfaces.find(s => s.id === canvas.ses.selected) || null

    function cap(s) { return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    focus: true
    Keys.onEscapePressed: e => { if (canvas.ses.escapeStep() === "leave") canvas.ses.leave(); e.accepted = true; }
    Keys.onReturnPressed: e => { canvas.ses.leave(); e.accepted = true; }
    onVisibleChanged: if (canvas.visible) canvas.forceActiveFocus()
    Component.onCompleted: canvas.forceActiveFocus()

    // A click on bare screen drops the selection.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: canvas.ses.deselect()
    }

    // One labelled outline per surface, hugging its current edge; peers on the
    // same edge stack away from it.
    Repeater {
        model: Layout.surfaces
        delegate: Rectangle {
            id: pill
            required property var modelData
            readonly property string edge: Layout.edgeOf(pill.modelData.id)
            readonly property int order: Layout.orderOnEdge(pill.modelData.id)
            readonly property bool selected: canvas.ses.selected === pill.modelData.id

            width: pillRow.implicitWidth + 28
            height: 34
            radius: Theme.radiusWidget
            x: pill.edge === "left" ? 16
                : pill.edge === "right" ? canvas.width - width - 16
                : (canvas.width - width) / 2
            y: pill.edge === "top" ? 132 + pill.order * 42
                : pill.edge === "bottom" ? canvas.height - height - 16 - pill.order * 42
                : (canvas.height - height) / 2 + pill.order * 42
            color: pill.selected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
            border.width: pill.selected ? 0 : 1
            border.color: pillMa.containsMouse
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.45)
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.modelData.label
                    color: pill.selected ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00b7 " + pill.edge
                    color: pill.selected ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 2
                }
            }
            MouseArea {
                id: pillMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: canvas.ses.select(pill.modelData.id)
            }
        }
    }

    StageIsland {
        title: "Edit shell layout"
        monitor: canvas.monitor
        scopes: Layout.surfaces.map(s => ({ id: s.id, label: s.label }))
        scope: canvas.ses.selected
        showReset: canvas.ses.dirty
        onScopeChose: id => canvas.ses.select(id)
        onReset: canvas.ses.reset()
        onDone: canvas.ses.leave()

        Row {
            spacing: 8
            visible: canvas.selSurface !== null
            Repeater {
                model: canvas.selSurface ? Layout.legalEdges(canvas.selSurface.id) : []
                delegate: Rectangle {
                    id: eb
                    required property string modelData
                    readonly property bool on: canvas.selSurface
                        && Layout.edgeOf(canvas.selSurface.id) === eb.modelData
                    width: ebText.implicitWidth + 26
                    height: 34
                    radius: Theme.radiusWidget
                    color: eb.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                        : ebMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
                    border.width: eb.on ? 0 : 1
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Text {
                        id: ebText
                        anchors.centerIn: parent
                        text: canvas.cap(eb.modelData)
                        color: eb.on ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: eb.on ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: ebMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (canvas.selSurface) Layout.setEdge(canvas.selSurface.id, eb.modelData)
                    }
                }
            }
        }
    }
}
