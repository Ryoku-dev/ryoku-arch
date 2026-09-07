pragma ComponentBehavior: Bound

import QtQuick
import "../.." as Pill
import shell.services
import "../../../../components"
import "../../../notifications"
import Ryoku.Ui.Singletons

// Notification history panel (contract 07 sec 2.3/4.3): a DND toggle, a
// "Notification History" title and a "Clear all" action, an "Empty" placeholder,
// then every notification newest first as its own card. There is NO grouping by
// app: the list is flat, ordered strictly by recency. Urgency has no visual or
// timeout effect, and no app icon or image is drawn. Cards come from the shared
// NotificationCard; the model is the flat Notifs.history.
Item {
    id: root

    required property real s
    required property bool open
    signal requestClose()

    readonly property var notifs: root.open ? Notifs.history : []

    implicitWidth: 410 * s
    implicitHeight: 560 * s

    Column {
        id: col
        width: root.width
        spacing: 12 * root.s

        // Header: DND toggle, title (fills), clear all.
        Item {
            id: header
            width: parent.width
            height: Math.max(titleText.implicitHeight, clearBtn.implicitHeight, dndBtn.height)

            Rectangle {
                id: dndBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSm + Theme.paddingSm * 2
                height: width
                radius: Theme.radiusWidget
                color: dndHov.hovered
                    ? Qt.tint(Theme.surface, Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08))
                    : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: Flags.dnd ? "do_not_disturb_on" : "notifications"
                    font.pixelSize: Theme.iconSm
                    color: Flags.dnd ? Theme.primary : (dndHov.hovered ? Theme.onSurface : Theme.onSurfaceVariant)
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Flags.dnd = !Flags.dnd
                    HoverHandler { id: dndHov }
                }
            }

            Text {
                id: titleText
                anchors.left: dndBtn.right
                anchors.leftMargin: Theme.paddingSm
                anchors.right: clearBtn.left
                anchors.rightMargin: Theme.paddingSm
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Notification History")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontMd
                font.weight: Font.Bold
                elide: Text.ElideRight
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
                        Notifs.clearAll();
                        root.requestClose();
                    }
                }
            }
        }

        // Empty placeholder.
        Text {
            width: parent.width
            visible: root.notifs.length === 0
            text: I18n.tr("Empty")
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontMd
        }

    }

    ListView {
        id: notificationList
        anchors.top: col.bottom
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: 10 * root.s
        model: root.notifs
        reuseItems: true
        cacheBuffer: Math.max(0, height)
        boundsBehavior: Flickable.StopAtBounds

        delegate: NotificationCard {
            required property var modelData
            width: notificationList.width
            notif: modelData
            onActionInvoked: root.requestClose()
        }
    }
}
