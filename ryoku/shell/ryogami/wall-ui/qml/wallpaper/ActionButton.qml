import QtQuick
import ".."
import Ryoku.Ui.Singletons

Item {
    id: btn

    property var colors
    property string icon: ""
    property string label: ""
    property int skew: 5
    property bool danger: false
    property string tooltip: ""

    signal clicked()

    height: 30
    implicitWidth: _contentRow.implicitWidth + 20 + skew
    implicitHeight: 30
    readonly property bool isHovered: _mouse.containsMouse

    Canvas {
        id: _canvas
        anchors.fill: parent

        property color fillColor: btn.isHovered
            ? (btn.danger
                ? Qt.rgba(1, 0.3, 0.3, 0.25)
                : (btn.colors ? Qt.rgba(btn.colors.surfaceVariant.r, btn.colors.surfaceVariant.g, btn.colors.surfaceVariant.b, 0.5) : Qt.rgba(1, 1, 1, 0.15)))
            : (btn.colors ? Qt.rgba(btn.colors.surfaceContainer.r, btn.colors.surfaceContainer.g, btn.colors.surfaceContainer.b, 0.7) : Qt.rgba(0.1, 0.12, 0.18, 0.7))
        property color strokeColor: btn.isHovered
            ? (btn.danger
                ? Qt.rgba(1, 0.3, 0.3, 0.4)
                : (btn.colors ? Qt.rgba(btn.colors.primary.r, btn.colors.primary.g, btn.colors.primary.b, 0.4) : Qt.rgba(1, 1, 1, 0.2)))
            : (btn.colors ? Qt.rgba(btn.colors.outline.r, btn.colors.outline.g, btn.colors.outline.b, 0.2) : Qt.rgba(1, 1, 1, 0.08))

        onFillColorChanged: requestPaint()
        onStrokeColorChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var sk = btn.skew
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

    Row {
        id: _contentRow
        anchors.centerIn: parent; spacing: 6
        Text {
            text: btn.icon
            font.family: Style.fontFamilyNerdIcons; font.pixelSize: 12
            color: btn.danger && btn.isHovered
                ? (btn.colors ? btn.colors.error : "#e2342a")
                : (btn.colors ? btn.colors.tertiary : "#8bceff")
            Behavior on color { ColorAnimation { duration: Style.animVeryFast } }
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: I18n.tr(btn.label)
            font.family: Style.fontFamily; font.pixelSize: 11
            font.weight: Font.Bold; font.letterSpacing: 0.5
            color: btn.danger && btn.isHovered
                ? (btn.colors ? btn.colors.error : "#e2342a")
                : (btn.colors ? btn.colors.tertiary : "#8bceff")
            Behavior on color { ColorAnimation { duration: Style.animVeryFast } }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: _mouse
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    StyledToolTip {
        visible: btn.tooltip !== "" && _mouse.containsMouse
        text: btn.tooltip
        delay: Style.tooltipDelay
        colors: btn.colors
    }
}
