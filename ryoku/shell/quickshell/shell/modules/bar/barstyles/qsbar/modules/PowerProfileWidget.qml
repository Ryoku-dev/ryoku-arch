import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root

    property string profile: root.powerProfileCurrent

    readonly property bool isPowerSaver:  profile === "power-saver"
    readonly property bool isBalanced:    profile === "balanced"
    readonly property bool isPerformance: profile === "performance"

    readonly property string profileIcon: {
        if (isPowerSaver)  return "\uF06C"
        if (isPerformance) return "\uF0E7"
        return "\uF24E"
    }

    readonly property color profileColor: {
        if (root.widgetHasFill("G14")) return root.widgetContrastColor("G14")
        if (isPowerSaver)  return root.indigo
        if (isPerformance) return root.seal
        return root.seal
    }

    readonly property string tooltipText: {
        if (isPowerSaver)  return I18n.tr("Power Saver")
        if (isPerformance) return I18n.tr("Performance")
        return I18n.tr("Balanced")
    }

    visible: implicitWidth > 0.5
    implicitWidth: root.modPower ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modPower ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.profileIcon
            renderType: Text.QtRendering
            color: rootMod.profileColor
            font.family: root.mono
            font.pixelSize: rootMod.isBalanced ? 13 : 14
            Behavior on color { ColorAnimation { duration: 200 } }
        }

    }

    Process {
        id: profileProc
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || echo balanced"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim()
                if (p) { rootMod.profile = p; root.powerProfileCurrent = p }
            }
        }
    }

    Timer {
        interval: 5000; running: root.modPower || root.powerProfileVisible; repeat: true; triggeredOnStart: true
        onTriggered: { profileProc.running = false; profileProc.running = true }
    }

    Process {
        id: setProfileProc
        command: ["bash", "-c", "powerprofilesctl set balanced"]
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited: { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) {
                var order = ["power-saver", "balanced", "performance"]
                var avail = root.powerProfileAvailable
                var cycle = (avail && avail.length > 0)
                    ? order.filter(function(k) { return avail.indexOf(k) !== -1 })
                    : order
                if (cycle.length === 0) cycle = order
                var idx = cycle.indexOf(root.powerProfileCurrent)
                var next = cycle[(Math.max(0, idx) + 1) % cycle.length]
                setProfileProc.command = ["bash", "-c", "powerprofilesctl set " + next]
                setProfileProc.running = false; setProfileProc.running = true
                root.powerProfileCurrent = next
            } else {
                root.powerProfileVisible = !root.powerProfileVisible
            }
        }
    }
}
