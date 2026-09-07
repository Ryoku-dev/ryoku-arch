import QtQuick
import QtQuick.Controls
import ".."
import Ryoku.Ui.Singletons

Item {
    id: dropdown

    property var colors
    property string label: ""
    property string value: ""
    property string displayValue: ""
    property var model: []
    property int skew: 8

    signal selected(string key)

    width: _btnLabel.implicitWidth + _arrow.implicitWidth + 28 * Config.uiScale + skew
    height: 24 * Config.uiScale
    z: _popupOpen ? 100 : (isHovered ? 5 : 1)

    readonly property bool isHovered: _mouse.containsMouse
    property bool _popupOpen: false

    Canvas {
        id: _canvas
        anchors.fill: parent

        property color fillColor: dropdown._popupOpen
            ? (dropdown.colors ? dropdown.colors.primary : Style.fallbackAccent)
            : (dropdown.value !== ""
                ? (dropdown.colors ? Qt.rgba(dropdown.colors.primary.r, dropdown.colors.primary.g, dropdown.colors.primary.b, 0.3) : Qt.rgba(1, 1, 1, 0.2))
                : (dropdown.isHovered
                    ? (dropdown.colors ? Qt.rgba(dropdown.colors.surfaceVariant.r, dropdown.colors.surfaceVariant.g, dropdown.colors.surfaceVariant.b, 0.6) : Qt.rgba(1, 1, 1, 0.15))
                    : (dropdown.colors ? Qt.rgba(dropdown.colors.surfaceContainer.r, dropdown.colors.surfaceContainer.g, dropdown.colors.surfaceContainer.b, 0.85) : Qt.rgba(0.1, 0.12, 0.18, 0.85))))
        property color strokeColor: dropdown.colors ? Qt.rgba(dropdown.colors.primary.r, dropdown.colors.primary.g, dropdown.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08)

        onFillColorChanged: requestPaint()
        onStrokeColorChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var sk = dropdown.skew
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
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: _btnLabel
            text: dropdown.displayValue || dropdown.label
            font.family: Style.fontFamily
            font.pixelSize: 10 * Config.uiScale
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            color: dropdown._popupOpen
                ? (dropdown.colors ? dropdown.colors.primaryText : "#000")
                : (dropdown.colors ? dropdown.colors.tertiary : "#8bceff")
        }

        Text {
            id: _arrow
            text: dropdown._popupOpen ? "▲" : "▼"
            font.pixelSize: 7 * Config.uiScale
            color: _btnLabel.color
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: _mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: _popup.open()
    }

    Popup {
        id: _popup
        x: 0
        y: dropdown.height + 4
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onOpenedChanged: dropdown._popupOpen = opened

        background: Rectangle {
            radius: 4
            color: dropdown.colors ? Qt.rgba(dropdown.colors.surface.r, dropdown.colors.surface.g, dropdown.colors.surface.b, 0.95) : Qt.rgba(0.1, 0.12, 0.18, 0.95)
            border.width: 1
            border.color: dropdown.colors ? Qt.rgba(dropdown.colors.primary.r, dropdown.colors.primary.g, dropdown.colors.primary.b, 0.2) : Qt.rgba(1, 1, 1, 0.1)
        }

        contentItem: Column {
            spacing: 1

            Repeater {
                model: dropdown.model

                Rectangle {
                    width: Math.max(_itemLabel.implicitWidth + 20 * Config.uiScale, 80 * Config.uiScale)
                    height: 22 * Config.uiScale
                    radius: 2
                    color: _itemIsActive
                        ? (dropdown.colors ? Qt.rgba(dropdown.colors.primary.r, dropdown.colors.primary.g, dropdown.colors.primary.b, 0.25) : Qt.rgba(1, 1, 1, 0.15))
                        : (_itemMouse.containsMouse
                            ? (dropdown.colors ? Qt.rgba(dropdown.colors.surfaceVariant.r, dropdown.colors.surfaceVariant.g, dropdown.colors.surfaceVariant.b, 0.4) : Qt.rgba(1, 1, 1, 0.08))
                            : "transparent")

                    property bool _itemIsActive: dropdown.value === modelData.key

                    Text {
                        id: _itemLabel
                        anchors.centerIn: parent
                        text: I18n.tr(modelData.label)
                        font.family: Style.fontFamily
                        font.pixelSize: 10 * Config.uiScale
                        font.weight: parent._itemIsActive ? Font.Bold : Font.Medium
                        font.letterSpacing: 0.3
                        color: parent._itemIsActive
                            ? (dropdown.colors ? dropdown.colors.primary : Style.fallbackAccent)
                            : (dropdown.colors ? dropdown.colors.surfaceText : "#e0e0e0")
                    }

                    MouseArea {
                        id: _itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dropdown.selected(modelData.key)
                            _popup.close()
                        }
                    }
                }
            }
        }
    }
}
