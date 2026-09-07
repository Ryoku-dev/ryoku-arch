import QtQuick
import ".."
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property string label: ""
    property string value: ""
    property var model: []
    property var onSelect

    width: parent ? parent.width : 0
    spacing: 2 * Config.uiScale

    Text {
        text: I18n.tr(root.label)
        font.family: Style.fontFamily
        font.pixelSize: 11 * Config.uiScale
        font.weight: Font.Medium
        color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
    }

    Flow {
        width: parent.width
        spacing: 4 * Config.uiScale

        Repeater {
            model: root.model
            Item {
                width: _comboLabel.implicitWidth + 24 * Config.uiScale + 8 * Config.uiScale
                height: 26 * Config.uiScale
                z: _comboIsActive ? 10 : (_comboMouse.containsMouse ? 5 : 1)

                property bool _comboIsActive: root.value === modelData

                Canvas {
                    id: _comboCanvas
                    anchors.fill: parent

                    property color fillColor: parent._comboIsActive
                        ? (root.colors ? root.colors.primary : Style.fallbackAccent)
                        : (_comboMouse.containsMouse
                            ? (root.colors ? Qt.rgba(root.colors.surfaceVariant.r, root.colors.surfaceVariant.g, root.colors.surfaceVariant.b, 0.6) : Qt.rgba(1, 1, 1, 0.15))
                            : (root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.85) : Qt.rgba(0.1, 0.12, 0.18, 0.85)))
                    property color strokeColor: parent._comboIsActive
                        ? Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.6)
                        : (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08))

                    onFillColorChanged: requestPaint()
                    onStrokeColorChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var sk = 8
                        ctx.fillStyle = fillColor
                        ctx.beginPath()
                        ctx.moveTo(sk, 0)
                        ctx.lineTo(width, 0)
                        ctx.lineTo(width - sk, height)
                        ctx.lineTo(0, height)
                        ctx.closePath()
                        ctx.fill()
                        ctx.strokeStyle = strokeColor
                        ctx.lineWidth = 1
                        ctx.stroke()
                    }
                }

                Text {
                    id: _comboLabel
                    anchors.centerIn: parent
                    text: modelData
                    font.family: Style.fontFamily
                    font.pixelSize: 10 * Config.uiScale
                    font.weight: Font.Bold
                    font.letterSpacing: 0.5
                    color: parent._comboIsActive
                        ? (root.colors ? root.colors.primaryText : "#000")
                        : (root.colors ? root.colors.tertiary : "#8bceff")
                }

                MouseArea {
                    id: _comboMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.onSelect) root.onSelect(modelData) }
                }
            }
        }
    }
}
