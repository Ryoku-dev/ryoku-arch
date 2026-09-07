import QtQuick
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property var saveConfigKey

    width: parent ? parent.width : 0
    spacing: 8

    function _entryCmd(e)  { return (typeof e === "string") ? e : (e ? (e.command || "") : "") }
    function _entryType(e) { return (typeof e === "string") ? "all" : (e && e.type ? e.type : "all") }

    function _snapshotCmds() {
        var cmds = []
        for (var i = 0; i < postCmdRepeater.count; i++) {
            var item = postCmdRepeater.itemAt(i)
            if (!item) continue
            cmds.push({ command: item.cmdText, type: item.entryType || "all" })
        }
        return cmds
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Behaviour")

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable internal wallpaper application")
            description: I18n.tr("When enabled, Ryogami will not apply wallpapers itself. Use the post-processing commands below to drive your own setter.")
            checked: Config.pickOnlyMode
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("pickOnlyMode", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Run on startup restore")
            description: I18n.tr("Re-run the post-processing commands when the daemon restores the last wallpaper at startup.")
            checked: Config.postProcessOnRestore
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("postProcessOnRestore", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Commands")
        subtitle: I18n.tr("Shell commands to run after every wallpaper change. The pills filter by type ALL fires for every change.\nPlaceholders: %path% = wallpaper file or WE folder · %thumb% = always an image · %type% = image/video/we · %name% = basename")

        Repeater {
            id: postCmdRepeater
            model: Config.postProcessing

            Item {
                id: postRow
                width: parent ? parent.width : 0
                height: typeRow.height + cmdRow.height + 10

                property string entryType: root._entryType(modelData)
                property string cmdText: cmdInput.text

                Row {
                    id: typeRow
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    spacing: 4
                    Repeater {
                        model: [
                            { key: "all",    label: "ALL" },
                            { key: "static", label: "IMG" },
                            { key: "video",  label: "VID" },
                            { key: "we",     label: "WE" }
                        ]
                        Rectangle {
                            width: 36 * Config.uiScale
                            height: 22 * Config.uiScale
                            radius: 4
                            color: postRow.entryType === modelData.key
                                ? (root.colors ? root.colors.primary : "#7986cb")
                                : (root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.6) : Qt.rgba(0.15, 0.15, 0.2, 0.6))
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr(modelData.label)
                                font.family: Style.fontFamily
                                font.pixelSize: 10 * Config.uiScale
                                font.weight: Font.Bold
                                font.letterSpacing: 0.5
                                color: postRow.entryType === modelData.key
                                    ? (root.colors ? root.colors.primaryText : "#ffffff")
                                    : (root.colors ? root.colors.surfaceText : "#ffffff")
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    postRow.entryType = modelData.key
                                    if (root.saveConfigKey) root.saveConfigKey("postProcessing", root._snapshotCmds())
                                }
                            }
                        }
                    }
                }

                Row {
                    id: cmdRow
                    anchors.top: typeRow.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 6

                    Rectangle {
                        width: parent.width - removeBtn.width - parent.spacing
                        height: 26
                        radius: 4
                        color: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.6) : Qt.rgba(0.15, 0.15, 0.2, 0.6)
                        border.width: cmdInput.activeFocus ? 1 : 0
                        border.color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.5) : Qt.rgba(1, 1, 1, 0.3)

                        TextInput {
                            id: cmdInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Style.fontFamilyCode
                            font.pixelSize: 11 * Config.uiScale
                            color: root.colors ? root.colors.tertiary : "#8bceff"
                            clip: true
                            selectByMouse: true
                            text: root._entryCmd(modelData)

                            onEditingFinished: {
                                if (root.saveConfigKey) root.saveConfigKey("postProcessing", root._snapshotCmds())
                            }
                        }
                    }

                    Rectangle {
                        id: removeBtn
                        width: 26; height: 26; radius: 4
                        color: removeMa.containsMouse
                            ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.25) : Qt.rgba(1, 0.3, 0.3, 0.25))
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Style.fontFamily
                            font.pixelSize: 13 * Config.uiScale
                            font.weight: Font.Bold
                            color: root.colors ? root.colors.primary : Qt.rgba(1, 0.3, 0.3, 0.8)
                        }

                        MouseArea {
                            id: removeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var cmds = root._snapshotCmds()
                                cmds.splice(index, 1)
                                if (root.saveConfigKey) root.saveConfigKey("postProcessing", cmds)
                            }
                        }
                    }
                }
            }
        }

        RowAction {
            colors: root.colors
            title: I18n.tr("Add command")
            description: I18n.tr("Append a new empty command row.")
            onClicked: {
                var cmds = root._snapshotCmds()
                cmds.push({ command: "", type: "all" })
                if (root.saveConfigKey) root.saveConfigKey("postProcessing", cmds)
            }
        }
    }
}
