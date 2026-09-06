pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import shell.services
import "Singletons"
import "../../components"

// The Add palette docked at the left of the desktop edit session (docs/stage.md):
// "Add layer" at the top (cut another picture, or drop a PNG), then a searchable
// card per desktop element the session offers: every built-in widget, each
// plugin and the visualizer: that toggles it on or off. It is decoupled from
// the desktop: `items` is supplied and `toggle(id)` is emitted, so this stays a
// pure list with no cross-module wiring.
Rectangle {
    id: pal
    property var items: []        // [{ id, label, icon, enabled }]
    signal toggle(string id)
    signal closed()

    property string query: ""
    readonly property var shown: (pal.items || []).filter(it =>
        pal.query.length === 0 || ("" + it.label).toLowerCase().indexOf(pal.query.toLowerCase()) >= 0)

    width: 300
    radius: Theme.radiusWidget
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.92)
    border.width: 1
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)

    function _path(u) { return ("" + u).replace(/^file:\/\//, ""); }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // Header.
        Item {
            width: parent.width
            height: 24
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Add to the stage"
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 12
                color: closeMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
                MaterialIcon { anchors.centerIn: parent; text: "close"; font.pixelSize: 16; color: Theme.onSurfaceVariant }
                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pal.closed() }
            }
        }

        // Add layer.
        Row {
            width: parent.width
            spacing: 8
            StageBtn {
                width: (parent.width - 8) / 2
                height: 40
                kind: "outlined"
                icon: "content_cut"
                label: "Cut\u2026"
                onAct: cutDlg.open()
            }
            StageBtn {
                width: (parent.width - 8) / 2
                height: 40
                kind: "outlined"
                icon: "image"
                label: "PNG\u2026"
                onAct: pngDlg.open()
            }
        }

        // Search.
        Rectangle {
            width: parent.width
            height: 34
            radius: Theme.radiusWidget
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                MaterialIcon { anchors.verticalCenter: parent.verticalCenter; text: "search"; font.pixelSize: 16; color: Theme.onSurfaceVariant }
                TextInput {
                    id: search
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm - 1
                    clip: true
                    onTextChanged: pal.query = text
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: search.text.length === 0
                        text: "Search widgets"
                        color: Theme.onSurfaceVariant
                        font: search.font
                    }
                }
            }
        }

        // Cards.
        Flickable {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: cards
                width: parent.width
                spacing: 6
                Repeater {
                    model: pal.shown
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        width: cards.width
                        height: 52
                        radius: Theme.radiusWidget
                        color: cardMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05) : "transparent"
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10
                            Rectangle {
                                width: 34; height: 34; radius: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: card.modelData.enabled ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: card.modelData.icon
                                    font.pixelSize: 17
                                    color: card.modelData.enabled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 34 - 10 - 74
                                text: card.modelData.label
                                elide: Text.ElideRight
                                color: Theme.onSurface
                                font.family: Theme.fontPrimary
                                font.pixelSize: Theme.fontSm
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 74; height: 30; radius: 15
                                color: card.modelData.enabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                                    : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Text {
                                    anchors.centerIn: parent
                                    text: card.modelData.enabled ? "On" : "Add"
                                    color: card.modelData.enabled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: Theme.fontSm - 1
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pal.toggle(card.modelData.id)
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: cutDlg
        title: "Cut a layer from a picture"
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp)", "All files (*)"]
        onAccepted: StageBackend.cutLayer(pal._path(cutDlg.selectedFile))
    }
    FileDialog {
        id: pngDlg
        title: "Add a PNG layer"
        nameFilters: ["PNG images (*.png)", "All files (*)"]
        onAccepted: StageBackend.addLayer(pal._path(pngDlg.selectedFile))
    }
}
