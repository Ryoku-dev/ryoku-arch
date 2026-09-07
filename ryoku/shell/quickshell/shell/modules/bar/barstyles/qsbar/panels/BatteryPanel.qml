import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../RyokuPower.js" as RyokuPower
import Ryoku.Ui.Singletons

PanelWindow {
    id: batPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-battery"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    property int    percent: 0
    property string status:  "unknown"
    property string batteryId: ""
    property string healthText: ""
    property string sizeText: ""
    property string timeLabel: I18n.tr("Time left")
    property string timeText: ""
    property string powerRate: ""
    property int    cycles:   0
    readonly property string healthLabel: batteryId !== "" ? I18n.tr("Health (%1)").arg(batteryId) : I18n.tr("Health")
    readonly property bool charging: status === "charging"
    function refreshBatteryData() {
        if (!batData.running) batData.running = true
    }
    function statusTitle(s) {
        var t = String(s || "unknown")
        if (t === "charging") return I18n.tr("Charging")
        if (t === "discharging") return I18n.tr("Discharging")
        if (t === "fully-charged") return I18n.tr("Full")
        if (t === "empty") return I18n.tr("Empty")
        if (t === "pending-charge") return I18n.tr("Pending charge")
        if (t === "pending-discharge") return I18n.tr("Pending discharge")
        if (t === "unknown") return I18n.tr("Unknown")
        return t.length > 0 ? t.charAt(0).toUpperCase() + t.slice(1) : I18n.tr("Unknown")
    }

    property real reveal: root.batteryVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.batteryVisible ? 160 : 120
            easing.type: root.batteryVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.batteryVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.batteryVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: batPanel.root
            ownerActive: batPanel.root.batteryVisible
            targetX: batPanel.root.batteryBarX
            reveal: batPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.batteryBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - batPanel.reveal)
            : (barBottom + gap) - 2 * (1 - batPanel.reveal)
        opacity: batPanel.reveal
        focus: root.batteryVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.batteryVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Battery")
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                UiText {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.batteryVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 30
                UiText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: batPanel.percent + "%"
                    color: batPanel.charging ? root.indigo : root.seal
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * batPanel.percent / 100
                        height: parent.height; radius: 4
                        color: batPanel.charging ? root.indigo : root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Row {
                    width: parent.width
                    UiText { text: I18n.tr("Status"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText {
                        text: batPanel.statusTitle(batPanel.status)
                        color: batPanel.charging ? root.indigo : root.ink
                        font.family: root.mono; font.pixelSize: 11
                    }
                }
                Row {
                    width: parent.width
                    visible: batPanel.timeText !== ""
                    UiText { text: batPanel.timeLabel; color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: batPanel.timeText; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: batPanel.healthText !== ""
                    UiText { text: batPanel.healthLabel; color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: batPanel.healthText; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: batPanel.powerRate !== ""
                    UiText { text: batPanel.charging ? I18n.tr("Charge rate") : I18n.tr("Power draw"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: batPanel.powerRate + " W"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: batPanel.sizeText !== ""
                    UiText { text: I18n.tr("Battery size"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: batPanel.sizeText; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: batPanel.cycles > 0
                    UiText { text: I18n.tr("Charge cycles"); color: root.sumiHi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    UiText { text: String(batPanel.cycles); color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Rectangle {
                width: parent.width
                height: 28; radius: root.panelButtonRadius
                color: btopMa.containsMouse ? root.fillPrimaryHover : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText { anchors.centerIn: parent; text: I18n.tr("Open btop"); color: root.paper; font.family: root.mono; font.pixelSize: 11 }
                MouseArea {
                    id: btopMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.batteryVisible = false; btopRunner.running = false; btopRunner.running = true }
                }
            }
        }
    }

    Process {
        id: batData
        command: ["bash", "-c", RyokuPower.batteryDataCmd]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split("|")
                if (parts.length >= 9) {
                    batPanel.batteryId = parts[0] || ""
                    batPanel.percent = parseInt(parts[1]) || 0
                    batPanel.status = parts[2] || "unknown"
                    batPanel.timeLabel = parts[3] || I18n.tr("Time left")
                    batPanel.timeText = parts[4] || ""
                    batPanel.powerRate = parts[5] || ""
                    batPanel.sizeText = parts[6] || ""
                    batPanel.healthText = parts[7] || ""
                    batPanel.cycles = parseInt(parts[8]) || 0
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: root.batteryVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: batPanel.refreshBatteryData()
    }

    Process { id: btopRunner; command: ["bash", "-c", "kitty 'btop'"] }
}
