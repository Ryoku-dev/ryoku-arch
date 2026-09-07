import QtQuick
import ".."
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property string label: ""
    property string value: ""
    property string placeholder: ""
    property var onCommit
    property var onFocused

    width: parent ? parent.width : 0
    spacing: 2 * Config.uiScale

    Text {
        text: I18n.tr(root.label)
        font.family: Style.fontFamily
        font.pixelSize: 11 * Config.uiScale
        font.weight: Font.Medium
        color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
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
            text: root.value

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                font: parent.font
                color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.3) : Qt.rgba(1, 1, 1, 0.2)
                text: root.placeholder
                visible: !inputField.text && !inputField.activeFocus
            }

            onActiveFocusChanged: {
                if (activeFocus && root.onFocused) root.onFocused()
                else if (!activeFocus) text = root.value
            }

            Connections {
                target: root
                function onValueChanged() {
                    if (!inputField.activeFocus) inputField.text = root.value
                }
            }

            onEditingFinished: {
                if (root.onCommit) root.onCommit(text)
            }
        }
    }
}
