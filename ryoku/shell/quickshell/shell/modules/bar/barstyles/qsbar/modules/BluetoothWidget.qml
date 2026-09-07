import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "../IconMap.js" as IconMap
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G15", root.ink)

    // BlueZ over D-Bus; a bluetoothctl poll here leaked a process per tick (#143).
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool hasAdapter: adapter !== null
    readonly property bool btOn: hasAdapter && adapter.enabled
    readonly property int numConnected: {
        if (!btOn || !Bluetooth.devices)
            return 0
        var vals = Bluetooth.devices.values
        var n = 0
        for (var i = 0; i < vals.length; i++)
            if (vals[i] && vals[i].connected)
                n++
        return n
    }
    readonly property bool connected: numConnected > 0

    readonly property string iconN: !btOn
        ? "bluetooth_disabled"
        : (connected ? "bluetooth_connected" : "bluetooth")

    readonly property string tooltipText: connected
        ? I18n.tr("Bluetooth · %1 connected").arg(numConnected)
        : (btOn ? I18n.tr("Bluetooth on") : I18n.tr("Bluetooth off"))

    // The widget's own toggle is authoritative, and a machine with no controller
    // keeps a clean bar either way.
    readonly property bool shown: root.modBluetooth && hasAdapter
    visible: implicitWidth > 0.5
    implicitWidth: shown ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: shown ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        IconText {
            anchors.verticalCenter: parent.verticalCenter
            text: IconMap.icon(rootMod.iconN)
            color: rootMod.connected
                ? (root.widgetHasFill("G15") ? rootMod.contentColor : root.seal)
                : Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, rootMod.btOn ? 0.7 : 0.3)
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.connected && !root.iconOnly("G15")
            text: String(rootMod.numConnected)
            color: root.widgetHasFill("G15") ? rootMod.contentColor : root.seal
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    Process { id: clickRunner; command: ["bash", "-c", root.launchBtCmd] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited: { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { clickRunner.running = false; clickRunner.running = true }
            else root.bluetoothVisible = !root.bluetoothVisible
        }
    }
}
