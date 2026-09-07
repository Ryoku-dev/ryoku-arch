pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import shell.services
import "Singletons"
import "../../components"

// Add tab (docs/stage.md): a horizontally scrollable strip of cards -- Cut from
// picture, From PNG, then a card per widget and the visualizer. No left palette.
// Enabling adds the element; an already-on card selects it (so a widget hidden
// under the inspector is still reachable). A search field appears only when the
// cards overflow the row.
Item {
    id: t

    // [{ id, label, icon, enabled, kind }]. kind: "widget" | "viz".
    property var items: []
    // Emitted for a card that is not yet on; the host enables the element.
    signal enable(string id)

    property string query: ""
    readonly property real cardW: 168
    readonly property real actW: 132
    readonly property real gap: 8
    // Decide search off the full catalogue so filtering never flips it.
    readonly property real fullW: 2 * (t.actW + t.gap) + (t.items || []).length * (t.cardW + t.gap)
    readonly property bool searchOn: t.fullW > t.width
    readonly property var shown: (t.items || []).filter(it =>
        t.query.length === 0 || ("" + it.label).toLowerCase().indexOf(t.query.toLowerCase()) >= 0)

    function _path(u) { return ("" + u).replace(/^file:\/\//, ""); }

    // Search field, only when the strip overflows.
    Rectangle {
        id: searchBox
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: t.searchOn ? 168 : 0
        height: 34
        visible: t.searchOn
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
                onTextChanged: t.query = text
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: "Search"
                    color: Theme.onSurfaceVariant
                    font: search.font
                }
            }
        }
    }

    Flickable {
        anchors.left: t.searchOn ? searchBox.right : parent.left
        anchors.leftMargin: t.searchOn ? 10 : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 50
        contentWidth: strip.width
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        Row {
            id: strip
            height: parent.height
            spacing: t.gap

            // Action cards.
            component ActionCard: Rectangle {
                id: ac
                property string icon: ""
                property string label: ""
                signal act()
                width: t.actW
                height: 48
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                radius: Theme.radiusWidget
                color: acMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08) : "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialIcon { anchors.verticalCenter: parent.verticalCenter; text: ac.icon; font.pixelSize: 18; color: Theme.onSurface }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ac.label
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 1
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea { id: acMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ac.act() }
            }

            ActionCard { icon: "content_cut"; label: "Cut\u2026"; onAct: cutDlg.open() }
            ActionCard { icon: "image"; label: "PNG\u2026"; onAct: pngDlg.open() }

            Repeater {
                model: t.shown
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: t.cardW
                    height: 48
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    radius: Theme.radiusWidget
                    color: cardMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06) : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.28)
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Rectangle {
                            width: 30; height: 30; radius: 15
                            anchors.verticalCenter: parent.verticalCenter
                            color: card.modelData.enabled ? Theme.primary : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: card.modelData.icon
                                font.pixelSize: 16
                                color: card.modelData.enabled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 30 - 8 - 52
                            text: card.modelData.label
                            elide: Text.ElideRight
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 1
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52; height: 26; radius: 13
                            color: card.modelData.enabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: card.modelData.enabled ? "On" : "Add"
                                color: card.modelData.enabled ? Theme.inkOn(Theme.primary, Theme.onPrimary) : Theme.onSurface
                                font.family: Theme.fontPrimary
                                font.pixelSize: Theme.fontSm - 2
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.modelData.enabled)
                                StageSession.select(card.modelData.id);
                            else
                                t.enable(card.modelData.id);
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
        onAccepted: StageBackend.cutLayer(t._path(cutDlg.selectedFile))
    }
    FileDialog {
        id: pngDlg
        title: "Add a PNG layer"
        nameFilters: ["PNG images (*.png)", "All files (*)"]
        onAccepted: StageBackend.addLayer(t._path(pngDlg.selectedFile))
    }
}
