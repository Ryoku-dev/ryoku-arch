import QtQuick
import Ryoku.Ui.Singletons
import "Singletons"
import "providers/actions/catalog.js" as Catalog

// Action-mode tab bar (shown when the query starts with "/"): All | System |
// Appearance | Tools | Media | Settings, the active tab underlined in vermilion,
// with a faint command-hint row for the package verbs. Tab/Shift+Tab cycle the
// active category; the actions provider reads it to narrow its list.
Item {
    id: root

    property real s: 1
    property int activeIndex: 0
    readonly property var categories: Catalog.CATEGORIES
    readonly property string activeCategory: categories[activeIndex]

    implicitHeight: tabRow.height + hints.height + 10 * s

    function cycle(delta) {
        var n = categories.length;
        root.activeIndex = (root.activeIndex + delta + n) % n;
    }

    Row {
        id: tabRow
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Metrics.gapTab * root.s
        height: 26 * root.s

        Repeater {
            model: root.categories.length
            delegate: Item {
                required property int index
                readonly property bool sel: index === root.activeIndex
                width: label.width
                height: tabRow.height

                Text {
                    id: label
                    anchors.top: parent.top
                    text: I18n.tr(root.categories[index])
                    color: parent.sel ? Theme.bright : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Metrics.fontSubtitle * root.s
                    font.weight: parent.sel ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                    anchors.top: label.bottom
                    anchors.topMargin: 4 * root.s
                    anchors.horizontalCenter: label.horizontalCenter
                    width: label.width
                    height: 2 * root.s
                    radius: Theme.radius
                    color: Theme.verm
                    visible: parent.sel
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeIndex = index
                }
            }
        }
    }

    Text {
        id: hints
        anchors.top: tabRow.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        text: "/file   /folder   /image   /video       >install <pkg>   >search <pkg>"
        color: Theme.faint
        font.family: Theme.mono
        font.pixelSize: Metrics.fontEyebrow * root.s
    }
}
