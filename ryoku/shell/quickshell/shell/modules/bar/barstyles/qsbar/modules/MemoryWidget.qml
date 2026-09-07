import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root

    visible: implicitWidth > 0.5
    implicitWidth: root.modMemory ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modMemory ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    readonly property int percent: root.systemMemPercent
    readonly property real usedGiB: root.systemMemUsedGiB
    readonly property real totalGiB: root.systemMemTotalGiB
    readonly property string usedLabel: String(Math.round(usedGiB)).padStart(2, '0') + "G"
    readonly property string tooltipText: usedGiB.toFixed(1) + "/" + totalGiB.toFixed(0) + "G"
    readonly property color contentColor: root.widgetContentColor("G4", root.widgetIconColor)

    Row {
        id: row
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: -1
        spacing: 4

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16

            Canvas {
                id: memoryRing
                anchors.fill: parent

                property color tint: rootMod.contentColor
                property color base: rootMod.contentColor
                onTintChanged: requestPaint()
                onBaseChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width / 2
                    var cy = height / 2
                    var r = (width / 2) - 1.5
                    var ratio = Math.max(0, Math.min(1, rootMod.percent / 100))
                    var start = -Math.PI / 2
                    var end = start + Math.PI * 2 * ratio

                    ctx.lineWidth = 1.7
                    ctx.lineCap = "round"

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.strokeStyle = Qt.rgba(base.r, base.g, base.b, 0.18)
                    ctx.stroke()

                    if (ratio > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, start, end)
                        ctx.strokeStyle = tint
                        ctx.stroke()
                    }
                }

                Component.onCompleted: requestPaint()
                Connections {
                    target: rootMod
                    function onPercentChanged() { memoryRing.requestPaint() }
                }
            }
        }

        UiText {
            visible: !root.iconOnly("G4")
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.usedLabel
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
        onExited: { tip.hide() }
        onClicked: { tip.hide(); root.memVisible = !root.memVisible }
    }
}
