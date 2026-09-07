import QtQuick
import QtQuick.Shapes
import ".."
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property string label: ""
    property int value: 0
    property int min: 0
    property int max: 100
    property var onCommit
    property var onChange
    property bool enabled: true

    width: parent ? parent.width : 0
    spacing: 4 * Config.uiScale
    opacity: enabled ? 1.0 : 0.4

    Row {
        width: parent.width
        spacing: 8 * Config.uiScale

        Text {
            text: I18n.tr(root.label)
            anchors.verticalCenter: parent.verticalCenter
            font.family: Style.fontFamily
            font.pixelSize: 11 * Config.uiScale
            font.weight: Font.Medium
            color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
        }

        Item { width: parent.width - _label.width - _value.width - 16; height: 1; visible: false }

        Text {
            id: _label
            text: ""
            visible: false
            font.family: Style.fontFamily
            font.pixelSize: 11 * Config.uiScale
        }

        Text {
            id: _value
            text: root.value
            anchors.right: parent.right
            font.family: Style.fontFamilyCode
            font.pixelSize: 11 * Config.uiScale
            font.weight: Font.Bold
            color: root.colors ? root.colors.primary : Qt.rgba(1, 1, 1, 0.7)
        }
    }

    Item {
        id: track
        width: parent.width
        height: 18 * Config.uiScale

        readonly property real _skew: 4
        readonly property real _range: Math.max(1, root.max - root.min)
        readonly property real _ratio: Math.max(0, Math.min(1, (root.value - root.min) / _range))
        readonly property real _fillWidth: Math.round(width * _ratio)

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.colors
                    ? Qt.rgba(root.colors.surfaceVariant.r, root.colors.surfaceVariant.g, root.colors.surfaceVariant.b, 0.6)
                    : Qt.rgba(0.3, 0.3, 0.35, 0.6)
                strokeColor: root.colors
                    ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.3)
                    : Qt.rgba(1, 1, 1, 0.1)
                strokeWidth: 1
                startX: track._skew; startY: 0
                PathLine { x: track.width;             y: 0 }
                PathLine { x: track.width - track._skew; y: track.height }
                PathLine { x: 0;                        y: track.height }
                PathLine { x: track._skew;             y: 0 }
            }
        }

        Shape {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(track._skew * 2 + 1, track._fillWidth)
            visible: track._ratio > 0
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.colors ? root.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0)
                strokeWidth: 0
                startX: track._skew; startY: 0
                PathLine { x: parent.width;             y: 0 }
                PathLine { x: parent.width - track._skew; y: track.height }
                PathLine { x: 0;                         y: track.height }
                PathLine { x: track._skew;              y: 0 }
            }
        }

        Item {
            id: thumb
            width: 8 * Config.uiScale
            height: track.height + 6
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(track.width - width, track._fillWidth - width / 2))

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.samples: 4
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: root.colors ? root.colors.primaryText : "#000"
                    strokeColor: root.colors ? root.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0)
                    strokeWidth: 1
                    startX: track._skew * 0.6; startY: 0
                    PathLine { x: thumb.width;                       y: 0 }
                    PathLine { x: thumb.width - track._skew * 0.6;   y: thumb.height }
                    PathLine { x: 0;                                  y: thumb.height }
                    PathLine { x: track._skew * 0.6;                 y: 0 }
                }
            }
        }

        MouseArea {
            id: _ma
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: root.enabled
            preventStealing: true

            function _setFromX(mx) {
                var clamped = Math.max(0, Math.min(track.width, mx))
                var ratio = track.width > 0 ? clamped / track.width : 0
                var v = Math.round(root.min + ratio * (root.max - root.min))
                if (v !== root.value) {
                    root.value = v
                    if (root.onChange) root.onChange(v)
                }
            }

            onPressed: function(ev) { _setFromX(ev.x + 4) }
            onPositionChanged: function(ev) { if (pressed) _setFromX(ev.x + 4) }
            onReleased: function(ev) {
                _setFromX(ev.x + 4)
                if (root.onCommit) root.onCommit(root.value)
            }
            onWheel: function(ev) {
                var step = (ev.angleDelta.y > 0 ? 1 : -1) * Math.max(1, Math.round((root.max - root.min) / 50))
                var v = Math.max(root.min, Math.min(root.max, root.value + step))
                if (v !== root.value) {
                    root.value = v
                    if (root.onChange) root.onChange(v)
                    if (root.onCommit) root.onCommit(v)
                }
            }
        }
    }
}
