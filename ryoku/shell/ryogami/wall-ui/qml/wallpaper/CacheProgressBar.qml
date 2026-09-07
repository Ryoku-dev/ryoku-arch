import QtQuick
import ".."
import Ryoku.Ui.Singletons

Rectangle {
    id: root

    property var colors
    property bool cacheLoading: false
    property int cacheProgress: 0
    property int cacheTotal: 0

    width: 400
    height: 40
    radius: 20
    color: colors ? Qt.rgba(colors.surfaceContainer.r, colors.surfaceContainer.g, colors.surfaceContainer.b, 0.9) : Qt.rgba(0, 0, 0, 0.8)
    visible: cacheLoading
    opacity: cacheLoading ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.animNormal } }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 16
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.1)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: 2
            width: root.cacheTotal > 0
                ? parent.width * (root.cacheProgress / root.cacheTotal)
                : 0
            color: root.colors ? root.colors.primary : Style.fallbackAccent
            Behavior on width { NumberAnimation { duration: Style.animVeryFast; easing.type: Easing.OutCubic } }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -12
        text: root.cacheTotal > 0
            ? I18n.tr("PROCESSING WALLPAPERS... %1 / %2").arg(root.cacheProgress).arg(root.cacheTotal)
            : I18n.tr("PROCESSING EXISTING WALLPAPERS... PLEASE WAIT")
        color: root.colors ? root.colors.tertiary : "#8bceff"
        font.family: Style.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        font.letterSpacing: 0.5
    }
}
