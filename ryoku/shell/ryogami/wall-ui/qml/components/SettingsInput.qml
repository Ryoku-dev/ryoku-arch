import QtQuick
import ".."
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property string label: ""
    property string description: ""
    property real value: 0
    property real min: 0
    property real max: 1000
    property int decimals: 0
    property var onCommit

    width: parent ? parent.width : 0
    spacing: 2 * Config.uiScale

    Text {
        text: I18n.tr(root.label)
        font.family: Style.fontFamily
        font.pixelSize: 11 * Config.uiScale
        font.weight: Font.Medium
        color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
    }

    Text {
        visible: root.description.length > 0
        width: root.width
        text: root.description
        font.family: Style.fontFamily
        font.pixelSize: 10 * Config.uiScale
        color: root.colors
            ? Qt.rgba(root.colors.tertiary.r, root.colors.tertiary.g, root.colors.tertiary.b, 0.55)
            : Qt.rgba(1, 1, 1, 0.35)
        wrapMode: Text.WordWrap
    }

    Rectangle {
        width: parent.width
        height: 26 * Config.uiScale
        radius: 4
        color: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.6) : Qt.rgba(0.15, 0.15, 0.2, 0.6)
        border.width: inputField.activeFocus ? 1 : 0
        border.color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.5) : Qt.rgba(1, 1, 1, 0.3)

        TextInput {
            id: inputField
            anchors.fill: parent
            anchors.leftMargin: 8 * Config.uiScale
            anchors.rightMargin: 8 * Config.uiScale
            verticalAlignment: TextInput.AlignVCenter
            font.family: Style.fontFamilyCode
            font.pixelSize: 11 * Config.uiScale
            color: root.colors ? root.colors.tertiary : "#8bceff"
            clip: true
            selectByMouse: true
            text: root.decimals === 0 ? Math.round(root.value).toString() : root.value.toFixed(root.decimals)
            validator: DoubleValidator {
                bottom: root.min
                top: root.max
                decimals: root.decimals
                notation: DoubleValidator.StandardNotation
            }
            onTextEdited: {
                var n = parseFloat(text)
                if (!isNaN(n) && n >= root.min && n <= root.max && root.onCommit) {
                    if (root.decimals === 0) n = Math.round(n)
                    root.onCommit(n)
                }
            }
        }
    }
}
