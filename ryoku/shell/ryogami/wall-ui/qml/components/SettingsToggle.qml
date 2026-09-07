import QtQuick
import QtQuick.Shapes
import ".."
import Ryoku.Ui.Singletons

Item {
    id: root
    property var colors
    property string label: ""
    property bool checked: false
    property var onToggle

    width: parent ? parent.width : 0
    height: 28 * Config.uiScale

    property real _skew: 4

    Item {
        id: track
        width: 40 * Config.uiScale
        height: 20 * Config.uiScale
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        Shape {
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
            ShapePath {
                fillColor: root.checked
                    ? (root.colors ? root.colors.primary : Style.fallbackAccent)
                    : (root.colors ? Qt.rgba(root.colors.surfaceVariant.r, root.colors.surfaceVariant.g, root.colors.surfaceVariant.b, 0.6) : Qt.rgba(0.3, 0.3, 0.35, 0.6))
                strokeColor: root.checked
                    ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.8) : Style.fallbackAccent)
                    : (root.colors ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.3) : Qt.rgba(1, 1, 1, 0.1))
                strokeWidth: 1
                startX: root._skew; startY: 0
                PathLine { x: track.width;               y: 0 }
                PathLine { x: track.width - root._skew;  y: track.height }
                PathLine { x: 0;                          y: track.height }
                PathLine { x: root._skew;                y: 0 }
            }
        }

        Item {
            id: thumb
            width: 16 * Config.uiScale
            height: 14 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: Style.animFast; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.samples: 8
                layer.smooth: true
                ShapePath {
                    fillColor: root.checked
                        ? (root.colors ? root.colors.primaryText : "#000")
                        : (root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.7) : Qt.rgba(1, 1, 1, 0.5))
                    strokeWidth: 0
                    startX: root._skew * 0.6; startY: 0
                    PathLine { x: thumb.width;                     y: 0 }
                    PathLine { x: thumb.width - root._skew * 0.6;  y: thumb.height }
                    PathLine { x: 0;                                y: thumb.height }
                    PathLine { x: root._skew * 0.6;               y: 0 }
                }
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: track.right
        anchors.leftMargin: 8 * Config.uiScale
        text: I18n.tr(root.label)
        font.family: Style.fontFamily
        font.pixelSize: 11 * Config.uiScale
        font.weight: Font.Medium
        color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            if (root.onToggle) root.onToggle(!root.checked)
        }
    }
}
