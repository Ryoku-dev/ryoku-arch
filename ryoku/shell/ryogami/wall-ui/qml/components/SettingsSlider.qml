import QtQuick
import ".."
import Ryoku.Ui.Singletons

// Ryoku slider: orthogonal, a neutral ink-tint track with an accent fill and an
// ink thumb; the label sits left, the signed value right. onChange fires while
// dragging (live preview), onCommit on release. Replaces skwd's skewed track
// that tinted the whole bar with surfaceVariant.
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
    property bool resettable: false
    property int defaultValue: 0

    readonly property color _ink:    colors ? colors.surfaceText : "#e0e2e8"
    readonly property color _inkDim: colors ? colors.surfaceVariantText : "#c2c7cf"
    readonly property color _accent: colors ? colors.primary : "#e2342a"
    readonly property color _line:   colors ? colors.outline : Qt.rgba(1, 1, 1, 0.22)

    width: parent ? parent.width : 0
    spacing: 5 * Config.uiScale
    opacity: enabled ? 1.0 : 0.4

    Item {
        width: parent.width
        height: 15 * Config.uiScale
        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(root.label)
            font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale; font.weight: Font.Medium
            color: root._inkDim
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * Config.uiScale
            Text {
                visible: root.resettable && root.enabled && root.value !== root.defaultValue
                text: "\u{f0099}"
                font.family: Style.fontFamilyNerdIcons; font.pixelSize: 12 * Config.uiScale
                color: _resetMouse.containsMouse ? root._accent : root._inkDim
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    id: _resetMouse
                    anchors.fill: parent; anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.value === root.defaultValue) return
                        root.value = root.defaultValue
                        if (root.onChange) root.onChange(root.value)
                        if (root.onCommit) root.onCommit(root.value)
                    }
                }
            }
            Text {
                text: (root.value > 0 ? "+" : "") + root.value
                font.family: Style.fontFamilyCode; font.pixelSize: 11 * Config.uiScale; font.weight: Font.Bold
                color: root._ink
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Item {
        id: track
        width: parent.width
        height: 14 * Config.uiScale
        readonly property real _range: Math.max(1, root.max - root.min)
        readonly property real _ratio: Math.max(0, Math.min(1, (root.value - root.min) / _range))
        readonly property real _fillW: Math.round(width * _ratio)

        Rectangle {
            anchors.fill: parent
            radius: Style.radiusSmall
            color: Qt.rgba(root._ink.r, root._ink.g, root._ink.b, 0.10)
            border.width: 1
            border.color: root._line
        }
        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: track._fillW
            radius: Style.radiusSmall
            color: root._accent
            visible: track._ratio > 0
        }
        Rectangle {
            width: 3
            height: parent.height + 6
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(track.width - width, track._fillW - width / 2))
            radius: 1
            color: root._ink
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: root.enabled
            preventStealing: true
            function _set(mx) {
                var c = Math.max(0, Math.min(track.width, mx))
                var r = track.width > 0 ? c / track.width : 0
                var v = Math.round(root.min + r * (root.max - root.min))
                if (v !== root.value) { root.value = v; if (root.onChange) root.onChange(v) }
            }
            onPressed: function(ev) { _set(ev.x) }
            onPositionChanged: function(ev) { if (pressed) _set(ev.x) }
            onReleased: function(ev) { _set(ev.x); if (root.onCommit) root.onCommit(root.value) }
            onWheel: function(ev) {
                var step = (ev.angleDelta.y > 0 ? 1 : -1) * Math.max(1, Math.round((root.max - root.min) / 50))
                var v = Math.max(root.min, Math.min(root.max, root.value + step))
                if (v !== root.value) { root.value = v; if (root.onChange) root.onChange(v); if (root.onCommit) root.onCommit(v) }
            }
        }
    }
}
