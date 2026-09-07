pragma ComponentBehavior: Bound

import QtQuick
import "../.." as Pill
import shell.services
import "../../../../components"
import Ryoku.Ui.Singletons

// Clipboard history panel (contract 07 sec 2.2/4.2): a "Clipboard History"
// header with a "Clear all" action, an "Empty" placeholder when there is no
// history, then the entries newest first. Each entry is a bordered surface tile
// titled "#{id}" that renders by kind -- a two-line text preview, a framed
// thumbnail for images, or "{mime}  ({size})" for anything else -- with a trash
// button in its top-right corner. A body tap re-sets the Wayland selection and
// promotes the entry to the front; there is no synthetic paste and no search
// field. All state comes from the daemon `clipboard` topic (Clipboard.qml); QML
// runs no external history tool.
Item {
    id: root

    required property real s
    required property bool open
    // The panel's available height (from MenuColumn via MenuWidgetHost); 0 falls
    // back to the resting height. Without it a tall history clips at the bottom.
    property real avail: 0
    signal requestClose()

    readonly property var entries: root.open ? Clipboard.entries : []

    implicitWidth: 410 * s
    implicitHeight: avail > 0 ? avail : 560 * s

    // Reference format_size: "{n} B" below 1 KiB, "{:.1} KB" below 1 MiB, else
    // "{:.1} MB" (contract 07 sec 2.2).
    function humanSize(bytes) {
        if (bytes < 1024)
            return bytes + " B";
        if (bytes < 1048576)
            return (bytes / 1024).toFixed(1) + " KB";
        return (bytes / 1048576).toFixed(1) + " MB";
    }

    Column {
        id: col
        width: root.width
        spacing: 12 * root.s

        Item {
            id: header
            width: parent.width
            height: Math.max(titleText.implicitHeight, clearBtn.implicitHeight)

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Clipboard History")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontMd
                font.weight: Font.Bold
            }
            Text {
                id: clearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Clear all")
                color: clearHov.hovered ? Theme.primary : Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
                HoverHandler { id: clearHov; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        Clipboard.clear();
                        root.requestClose();
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.entries.length === 0
            text: I18n.tr("Empty")
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontMd
        }

    }

    ListView {
        id: clipboardList
        anchors.top: col.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 10 * root.s
        model: root.entries
        reuseItems: true
        cacheBuffer: Math.max(0, height)
        boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: entry
                required property var modelData

                readonly property string kind: entry.modelData.kind
                readonly property int entryId: entry.modelData.id

                width: clipboardList.width
                radius: Theme.radiusWidget
                border.width: Theme.borderWidth
                border.color: Theme.outline
                color: body.containsMouse
                    ? Qt.tint(Theme.surface, Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08))
                    : Theme.surface
                implicitHeight: entryCol.implicitHeight + Theme.paddingMd * 2

                Behavior on color { ColorAnimation { duration: Motion.rowFade; easing.type: Motion.easeType; easing.bezierCurve: Motion.easeCurve } }

                MouseArea {
                    id: body
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.copy(entry.entryId)
                }

                Column {
                    id: entryCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.paddingMd
                    spacing: Theme.paddingMd

                    // "#{id}" title; the trash button overlays this row's right.
                    Item {
                        width: parent.width
                        height: titleRow.implicitHeight

                        Text {
                            id: titleRow
                            anchors.left: parent.left
                            anchors.right: trash.left
                            anchors.rightMargin: Theme.paddingSm
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + entry.entryId
                            color: Theme.onSurfaceVariant
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: trash
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSm + Theme.paddingSm * 2
                            height: width
                            radius: Theme.radiusWidget
                            color: trashHov.hovered
                                ? Qt.tint(Theme.surface, Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08))
                                : "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "delete"
                                font.pixelSize: Theme.iconSm
                                color: trashHov.hovered ? Theme.error : Theme.onSurfaceVariant
                            }

                            MouseArea {
                                id: trashArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Clipboard.del(entry.entryId)
                                HoverHandler { id: trashHov }
                            }
                        }
                    }

                    // Text preview: two ellipsised lines, wrapping mid-word.
                    Text {
                        width: parent.width
                        visible: entry.kind === "text"
                        text: entry.modelData.preview || ""
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.Bold
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // Image preview: a framed, cover-fit thumbnail from the
                    // daemon-persisted PNG.
                    Rectangle {
                        width: parent.width
                        height: 200 * root.s
                        visible: entry.kind === "image"
                        radius: Theme.radiusWidget
                        border.width: Theme.borderWidth
                        border.color: Theme.outline
                        color: "transparent"
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: Theme.borderWidth
                            source: entry.kind === "image" && entry.modelData.thumb ? "file://" + entry.modelData.thumb : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }
                    }

                    // Binary preview: the mime and a human-readable size.
                    Text {
                        width: parent.width
                        visible: entry.kind !== "text" && entry.kind !== "image"
                        text: (entry.modelData.mime || "") + "  (" + root.humanSize(entry.modelData.size || 0) + ")"
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                }
            }
        }
}
