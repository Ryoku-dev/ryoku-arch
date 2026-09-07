pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import ".." as Menus
import Ryoku.Ui.Singletons

Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: content
            width: parent.width
            spacing: 12

            Menus.QsSection {
                width: parent.width
                label: I18n.tr("Media")
            }

            Menus.MediaHero {
                width: parent.width
                active: root.open
            }

            Text {
                visible: Media.player === null
                width: parent.width
                topPadding: 24
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Nothing is playing")
                color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm
            }
        }
    }
}
