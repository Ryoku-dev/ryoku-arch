pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import "../../../components"
import Ryoku.Ui.Singletons

// Feature sidebar behind Super+S: a framed floating card with a left activity
// rail over pluggable pages (Usage, Tools). The Tools "Compress video" and
// "Install app" tools open an in-shell file picker that takes over the content
// area without ever closing the sidebar. Fixed reference px inside; the card
// hugs its content.
Item {
    id: root

    property real s: 1
    property bool open: false
    property string monitorName: ""
    property string surfaceId: ""
    // A deep-link fragment (stash#compress / stash#install) opens straight into
    // that picker.
    property string page: ""

    // "" | "compress" | "install": the in-shell file picker takes over content.
    property string picking: ""

    implicitWidth: 428 * root.s
    readonly property real contentH: root.picking !== "" ? picker.implicitHeight
        : (contentLoader.item ? contentLoader.item.implicitHeight : 420 * root.s)
    implicitHeight: Math.max(320 * root.s, Math.min(792 * root.s, root.contentH))

    // Adding a feature is one row here plus one branch in the Loader below.
    readonly property var tabs: [
        { id: "chat", icon: "forum", label: I18n.tr("Chat") },
        { id: "usage", icon: "insights", label: I18n.tr("Usage") },
        { id: "tools", icon: "download", label: I18n.tr("Tools") }
    ]
    property string activeTab: "chat"

    onPageChanged: root.applyPage()
    Component.onCompleted: root.applyPage()
    function applyPage() {
        if (root.page === "compress" || root.page === "install") {
            root.activeTab = "tools";
            root.picking = root.page;
        }
    }

    // ── frame ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusWidget
        color: "transparent"
        border.width: Theme.borderWidth
        border.color: Theme.outline
        SumiEdge { radius: Theme.radiusWidget }
    }

    // ── activity rail ──
    Item {
        id: rail
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 50 * root.s

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 12 * root.s
            anchors.bottomMargin: 12 * root.s
            width: 1
            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.35)
        }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 14 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4 * root.s

            Repeater {
                model: root.tabs
                delegate: Item {
                    id: tab
                    required property var modelData
                    readonly property bool on: root.activeTab === modelData.id && root.picking === ""
                    width: 44 * root.s
                    height: 48 * root.s

                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 36 * root.s
                        height: 36 * root.s
                        radius: width / 2
                        color: tab.on ? Theme.primary
                            : tapArea.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.09)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            font.pixelSize: 15 * root.s
                            text: tab.modelData.icon
                            fill: tab.on ? 1 : 0
                            color: tab.on ? Theme.inkOn(Theme.primary, Theme.onPrimary)
                                : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr(tab.modelData.label)
                        color: tab.on ? Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                            : Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                        font.family: Theme.fontPrimary
                        font.pixelSize: 7 * root.s
                        font.weight: tab.on ? Font.DemiBold : Font.Normal
                    }

                    scale: tapArea.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                    MouseArea {
                        id: tapArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.picking = ""; root.activeTab = tab.modelData.id; }
                    }
                }
            }
        }
    }

    // ── content ──
    Item {
        anchors.left: rail.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        clip: true

        Component { id: chatPage; PanelChat { s: root.s; open: root.open } }
        Component { id: usagePage; PanelOverview { s: root.s; open: root.open } }
        Component {
            id: toolsPage
            PanelTools { s: root.s; open: root.open; onPick: m => root.picking = m }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.picking === ""
            visible: root.picking === ""
            sourceComponent: root.activeTab === "chat" ? chatPage
                : root.activeTab === "usage" ? usagePage
                : root.activeTab === "tools" ? toolsPage : null
        }

        PanelPicker {
            id: picker
            anchors.fill: parent
            visible: root.picking !== ""
            s: root.s
            mode: root.picking === "install" ? "install" : "compress"
            onCancelled: root.picking = ""
            onConfirmed: paths => {
                if (root.picking === "install") Stash.install(paths);
                else Stash.compress(paths);
                root.picking = "";
            }
        }
    }
}
