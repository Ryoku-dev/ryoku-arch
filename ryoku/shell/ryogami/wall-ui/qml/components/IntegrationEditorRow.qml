import QtQuick
import ".."
import "../components"
import Ryoku.Ui.Singletons

Item {
    id: row

    property var colors
    property string entryName: ""
    property string template: ""
    property string output: ""
    property string reload: ""

    property bool _expanded: false

    signal saveField(string field, var value)
    signal removeRequested()

    width: parent ? parent.width : 0
    height: _expanded ? _card.implicitHeight : _collapsedRow.height
    Behavior on height { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }
    clip: true

    Rectangle {
        id: _collapsedRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44 * Config.uiScale
        radius: 6
        z: 1
        opacity: row._expanded ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.animFast; easing.type: Easing.OutCubic } }

        color: !row._expanded && _rowMouse.containsMouse
            ? (row.colors ? Qt.rgba(row.colors.surfaceVariant.r, row.colors.surfaceVariant.g, row.colors.surfaceVariant.b, 0.35) : Qt.rgba(1, 1, 1, 0.05))
            : "transparent"

        Rectangle {
            id: _iconBadge
            width: 30 * Config.uiScale; height: 30 * Config.uiScale; radius: 5
            anchors.left: parent.left
            anchors.leftMargin: 10 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            color: row.colors ? Qt.rgba(row.colors.surfaceContainer.r, row.colors.surfaceContainer.g, row.colors.surfaceContainer.b, 0.6) : Qt.rgba(0.1, 0.12, 0.18, 0.6)
            border.width: 1
            border.color: row.colors ? Qt.rgba(row.colors.outline.r, row.colors.outline.g, row.colors.outline.b, 0.15) : Qt.rgba(1, 1, 1, 0.06)

            Text {
                anchors.centerIn: parent
                text: row.entryName.length > 0 ? row.entryName.charAt(0).toUpperCase() : "?"
                font.family: Style.fontFamily
                font.pixelSize: 14 * Config.uiScale
                font.weight: Font.Medium
                color: row.colors ? Qt.rgba(row.colors.surfaceText.r, row.colors.surfaceText.g, row.colors.surfaceText.b, 0.45) : Qt.rgba(1, 1, 1, 0.35)
            }
        }

        Text {
            id: _nameText
            anchors.left: _iconBadge.right
            anchors.leftMargin: 12 * Config.uiScale
            anchors.right: _badges.left
            anchors.rightMargin: 10 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.entryName !== ""
                ? (row.output !== "" ? (row.entryName + "  ·  " + row.output) : row.entryName)
                : I18n.tr("(unnamed)")
            font.family: Style.fontFamily
            font.pixelSize: 13 * Config.uiScale
            font.weight: Font.Medium
            color: row.colors ? row.colors.surfaceText : "#fff"
        }

        Row {
            id: _badges
            anchors.right: _chevron.left
            anchors.rightMargin: 10 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                visible: row.template !== ""
                text: I18n.tr("template")
                font.family: Style.fontFamilyCode
                font.pixelSize: 9 * Config.uiScale
                color: row.colors ? row.colors.tertiary : "#8bceff"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: row.reload !== ""
                text: I18n.tr("reload")
                font.family: Style.fontFamilyCode
                font.pixelSize: 9 * Config.uiScale
                color: row.colors ? row.colors.primary : "#ffb4ab"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            id: _chevron
            anchors.right: parent.right
            anchors.rightMargin: 12 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            text: "▶"
            font.family: Style.fontFamily
            font.pixelSize: 10 * Config.uiScale
            color: row.colors ? Qt.rgba(row.colors.surfaceText.r, row.colors.surfaceText.g, row.colors.surfaceText.b, 0.4) : Qt.rgba(1, 1, 1, 0.3)
        }

        MouseArea {
            id: _rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row._expanded = !row._expanded
        }
    }

    SettingsCard {
        id: _card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        colors: row.colors
        title: row.entryName !== "" ? row.entryName : I18n.tr("(unnamed)")
        subtitle: row.output
        opacity: row._expanded ? 1 : 0
        enabled: row._expanded
        Behavior on opacity { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }

        titleAction: Rectangle {
            width: 28 * Config.uiScale; height: 22 * Config.uiScale; radius: 4
            color: _closeMouse.containsMouse
                ? (row.colors ? Qt.rgba(row.colors.surfaceVariant.r, row.colors.surfaceVariant.g, row.colors.surfaceVariant.b, 0.4) : Qt.rgba(1, 1, 1, 0.06))
                : "transparent"

            Text {
                anchors.centerIn: parent
                text: "▼"
                font.family: Style.fontFamily
                font.pixelSize: 10 * Config.uiScale
                color: row.colors ? row.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
            }
            MouseArea {
                id: _closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row._expanded = false
            }
        }

        RowTextInput {
            colors: row.colors
            title: I18n.tr("Name")
            description: I18n.tr("Stable identifier for this integration.")
            value: row.entryName
            placeholder: "kitty"
            onCommit: function(v) { row.saveField("name", v) }
        }

        RowTextInput {
            colors: row.colors
            title: I18n.tr("Template")
            description: I18n.tr("Template file rendered by Matugen.")
            value: row.template
            placeholder: I18n.tr("kitty.toml")
            onCommit: function(v) { row.saveField("template", v) }
        }

        RowTextInput {
            colors: row.colors
            title: I18n.tr("Output")
            description: I18n.tr("Path where the rendered output is written.")
            value: row.output
            placeholder: I18n.tr("~/.config/kitty/colors.toml")
            onCommit: function(v) { row.saveField("output", v) }
        }

        RowTextInput {
            colors: row.colors
            title: I18n.tr("Reload")
            description: I18n.tr("Optional shell command to run after the output is written.")
            value: row.reload
            placeholder: I18n.tr("kill -SIGUSR1 $(pgrep kitty)")
            onCommit: function(v) { row.saveField("reload", v) }
        }

        RowAction {
            colors: row.colors
            title: I18n.tr("Remove integration")
            description: I18n.tr("Delete this entry from the integrations list.")
            onClicked: row.removeRequested()
        }
    }
}
