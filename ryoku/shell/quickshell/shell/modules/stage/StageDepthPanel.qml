pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import shell.services
import "Singletons"
import "../../components"

// The Depth scope's floating panel (docs/stage.md): the look every layer
// inherits -- Edge, and Shadow with its direction dial once shadow is on -- then
// the layer list (each behind or in front of the widgets, near/far while
// Parallax is on, removable unless it is the subject) and Add layer (cut from a
// picture, or drop in a PNG). Quality and the two switches live on the island's
// second row, so nothing here is shown twice.
StagePanel {
    id: dp
    title: "Depth"
    kind: "depth"
    bodyWidth: 332
    defaultX: 60
    defaultY: 120

    readonly property var sb: StageBackend
    readonly property string wall: dp.sb.current
    readonly property bool parallax: dp.sb.effect === "parallax"
    readonly property int layerCount: dp.sb.layerCountFor(dp.wall)

    function _path(u) { return ("" + u).replace(/^file:\/\//, ""); }

    StageDragSlider {
        width: parent.width
        title: "Edge"
        value: Config.edge
        min: 0; max: 1; decimals: 2
        onChanged: v => Config.setEdge(v)
    }

    Item {
        width: parent.width
        height: 46
        StageDragSlider {
            id: shadowSlider
            anchors.left: parent.left
            anchors.right: Config.shadow > 0 ? dial.left : parent.right
            anchors.rightMargin: Config.shadow > 0 ? 12 : 0
            anchors.verticalCenter: parent.verticalCenter
            title: "Shadow"
            value: Config.shadow
            min: 0; max: 1; decimals: 2
            onChanged: v => Config.setShadow(v)
        }
        StageAngleDial {
            id: dial
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: Config.shadow > 0
            dim: 44
            angle: Config.shadowAngle
            onChanged: deg => Config.setShadowAngle(deg)
        }
    }

    Text {
        text: "Layers"
        color: Theme.onSurfaceVariant
        font.family: Theme.fontPrimary
        font.pixelSize: Theme.fontSm - 2
        font.weight: Font.DemiBold
    }

    Repeater {
        model: dp.layerCount
        delegate: Column {
            id: layerRow
            required property int index
            width: parent.width
            spacing: 6

            Row {
                width: parent.width
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - removeBtn.width
                    elide: Text.ElideRight
                    text: dp.sb.layerLabel(dp.wall, layerRow.index)
                    color: dp.sb.layerEnabled(dp.wall, layerRow.index) ? Theme.onSurface : Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    id: removeBtn
                    visible: layerRow.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 26 : 0
                    height: 26
                    radius: 13
                    color: rmMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
                    MaterialIcon { anchors.centerIn: parent; text: "close"; font.pixelSize: 16; color: Theme.onSurfaceVariant }
                    MouseArea {
                        id: rmMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dp.sb.removeLayer(layerRow.index);
                            StageSession.markDirty();
                            if (StageSession.selected === ("layer:" + layerRow.index))
                                StageSession.deselect();
                        }
                    }
                }
            }

            StageSeg {
                width: parent.width
                options: [
                    { id: "behind", label: "Behind widgets" },
                    { id: "front", label: "In front" }
                ]
                current: dp.sb.layerFront(dp.wall, layerRow.index) ? "front" : "behind"
                onChose: id => { dp.sb.setLayerFront(layerRow.index, id === "front"); StageSession.markDirty(); }
            }

            StageDragSlider {
                width: parent.width
                visible: dp.parallax
                title: "Drift (near\u2013far)"
                value: dp.sb.layerDepth(dp.wall, layerRow.index)
                min: 0; max: 1; decimals: 2
                onChanged: v => { dp.sb.setLayerDepth(layerRow.index, v); StageSession.markDirty(); }
            }
        }
    }

    Row {
        width: parent.width
        spacing: 8
        component AddBtn: Rectangle {
            id: ab
            property string icon: ""
            property string label: ""
            signal act()
            width: (parent.width - 8) / 2
            height: 38
            radius: Theme.radiusWidget
            color: abMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
            border.width: 1
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
            Row {
                anchors.centerIn: parent
                spacing: 6
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; text: ab.icon; font.pixelSize: 16; color: Theme.onSurface }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ab.label
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 2
                    font.weight: Font.DemiBold
                }
            }
            MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ab.act() }
        }
        AddBtn { icon: "content_cut"; label: "Cut a picture"; onAct: cutDlg.open() }
        AddBtn { icon: "image"; label: "Add a PNG"; onAct: pngDlg.open() }
    }

    FileDialog {
        id: cutDlg
        title: "Cut a layer from a picture"
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp)", "All files (*)"]
        onAccepted: { dp.sb.cutLayer(dp._path(cutDlg.selectedFile)); StageSession.markDirty(); }
    }
    FileDialog {
        id: pngDlg
        title: "Add a PNG layer"
        nameFilters: ["PNG images (*.png)", "All files (*)"]
        onAccepted: { dp.sb.addLayer(dp._path(pngDlg.selectedFile)); StageSession.markDirty(); }
    }
}
