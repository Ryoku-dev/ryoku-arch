import QtQuick
import Quickshell
import Quickshell.Services.UPower
import shell.services
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root

    // event-driven UPower data - updates instantly on plug / unplug
    readonly property var dev: UPower.displayDevice
    readonly property bool hasBattery: dev !== null && dev.isLaptopBattery
    readonly property int percent: {
        if (!dev) return 0
        var p = dev.percentage
        // robust to either 0..1 or 0..100 reporting
        return Math.round(p <= 1.0 ? p * 100 : p)
    }
    readonly property int devState: dev ? dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: devState === UPowerDeviceState.Charging
    readonly property bool full:     devState === UPowerDeviceState.FullyCharged
    readonly property bool low:      hasBattery && !charging && !full && percent <= 20

    // live time estimates from UPower (seconds); 0 when unknown / not applicable
    readonly property real timeToEmpty: dev ? dev.timeToEmpty : 0
    readonly property real timeToFull:  dev ? dev.timeToFull  : 0
    readonly property string timeText:  charging ? fmtDuration(timeToFull) : fmtDuration(timeToEmpty)
    function fmtDuration(s) {
        if (!s || s <= 0) return ""
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        return h > 0 ? (h + "h " + m + "m") : (m + "m")
    }

    readonly property string statusText:
        full ? I18n.tr("Full")
        : charging ? I18n.tr("Charging")
        : devState === UPowerDeviceState.Discharging ? I18n.tr("Discharging")
        : I18n.tr("On battery")
    readonly property string tooltipText: timeText
        ? I18n.tr("%1 · %2% · %3").arg(statusText).arg(percent).arg(timeText)
        : I18n.tr("%1 · %2%").arg(statusText).arg(percent)
    readonly property color contentColor: root.widgetContentColor("G12", root.ink)

    // colour shared by the drawn battery body, fill and nub
    readonly property color battColor:
        root.widgetHasFill("G12") ? contentColor
        : ((charging || full) ? root.indigo : root.seal)

    // Both gates: the toggle only matters where a laptop battery is reported.
    readonly property bool shown: hasBattery && root.modBattery
    implicitWidth:  shown ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    visible: shown


    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        // drawn landscape battery - body + stepless fill + terminal nub
        Item {
            id: batt
            width: 19
            height: 10
            anchors.verticalCenter: parent.verticalCenter

            readonly property real ratio: Math.max(0, Math.min(1, rootMod.percent / 100))

            // low-battery warning: the icon slowly pulses below 20% (not while charging)
            property real pulse: 1.0
            opacity: rootMod.low ? pulse : 1.0
            SequentialAnimation {
                running: rootMod.visible && rootMod.low   // defensive: never animate while hidden / batteryless
                loops: Animation.Infinite
                NumberAnimation { target: batt; property: "pulse"; from: 1.0; to: 0.3; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { target: batt; property: "pulse"; from: 0.3; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
            }

            Rectangle {
                id: body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 9
                radius: 2.5
                color: "transparent"
                border.width: 1.2
                border.color: rootMod.battColor
                Behavior on border.color { ColorAnimation { duration: 200 } }

                // faint indigo wash so a charging cell reads "active" at any level
                Rectangle {
                    visible: rootMod.charging
                    anchors.fill: parent
                    anchors.margins: 1.8
                    radius: 1.2
                    color: Qt.rgba(rootMod.battColor.r, rootMod.battColor.g, rootMod.battColor.b, 0.28)
                }

                Rectangle {
                    id: fill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1.8
                    width: Math.max(batt.ratio > 0 ? 1.5 : 0, (parent.width - 3.6) * batt.ratio)
                    radius: 1.2
                    clip: true
                    color: rootMod.battColor
                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }

                    // font-free charging shimmer that sweeps across the fill. The
                    // indigo body, the wash and the bolt already say "charging"; the
                    // sweep is ambient motion, and every frame of it is a compositor
                    // frame off a full-screen layer, so it follows the same rule as
                    // the bar's silent drift: Performance only (Perf.ambientMotion),
                    // and a sweep every few seconds rather than back to back.
                    Rectangle {
                        visible: rootMod.charging && !rootMod.full && Perf.ambientMotion
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 6
                        radius: parent.radius
                        color: Qt.rgba(1, 1, 1, 0.18)
                        property real pos: 0
                        x: (parent.width + width) * pos - width
                        SequentialAnimation on pos {
                            running: rootMod.charging && !rootMod.full && Perf.ambientMotion
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 3500 }
                        }
                    }
                }

                // charging bolt overlay - clear "is charging" cue
                Canvas {
                    id: bolt
                    visible: rootMod.charging || rootMod.full
                    anchors.centerIn: parent
                    width: 6
                    height: 8
                    property color boltColor: root.widgetHasFill("G12")
                        ? root.widgetAssignedColor("G12")
                        : root.paper
                    onBoltColorChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.beginPath()
                        ctx.moveTo(width * 0.55, 0)
                        ctx.lineTo(width * 0.12, height * 0.55)
                        ctx.lineTo(width * 0.45, height * 0.55)
                        ctx.lineTo(width * 0.38, height)
                        ctx.lineTo(width * 0.88, height * 0.45)
                        ctx.lineTo(width * 0.55, height * 0.45)
                        ctx.closePath()
                        ctx.fillStyle = bolt.boltColor
                        ctx.fill()
                    }
                    Component.onCompleted: requestPaint()
                }
            }

            // terminal nub (positive pole)
            Rectangle {
                anchors.left: body.right
                anchors.leftMargin: -0.5
                anchors.verticalCenter: parent.verticalCenter
                width: 2.5
                height: 5
                radius: 1.2
                color: rootMod.battColor
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        UiText {
            visible: !root.iconOnly("G12")
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.percent + "%"
            color: rootMod.battColor
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: { if (rootMod.hasBattery) tip.show() }
        onExited:  { tip.hide() }
        onClicked: { tip.hide(); root.batteryVisible = !root.batteryVisible }
    }
}
