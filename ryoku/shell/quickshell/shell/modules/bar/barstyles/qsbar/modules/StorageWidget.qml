import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G18", root.widgetIconColor)

    readonly property int percent: root.storagePercent
    readonly property string tooltipText: I18n.tr("Root filesystem · %1% · %2/%3 GiB")
        .arg(percent).arg(root.storageUsedGiB.toFixed(1)).arg(root.storageTotalGiB.toFixed(1))

    visible: implicitWidth > 0.5
    implicitWidth: root.modStorage && root.storageAvailable ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modStorage && root.storageAvailable ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            width: 15
            text: "󰋊"
            color: rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
        }

        UiText {
            visible: !root.iconOnly("G18")
            anchors.verticalCenter: parent.verticalCenter
            text: String(Math.min(100, rootMod.percent)).padStart(2, "0") + "%"
            color: rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: tip.hide()
        onClicked: { tip.hide(); root.storageVisible = !root.storageVisible }
    }
}
