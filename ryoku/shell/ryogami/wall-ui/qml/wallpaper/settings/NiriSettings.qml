import QtQuick
import "../.."
import "../../components"
import "../../services"
import Ryoku.Ui.Singletons

Flow {
    id: root
    property var colors
    property var saveConfigKey

    width: parent ? parent.width : 0
    spacing: 12

    property var _backdropThemes: []

    Component.onCompleted: {
        DaemonClient.call("effects.list", {}, function(result, err) {
            if (err || !result || !result.effects) return
            for (var i = 0; i < result.effects.length; i++) {
                var eff = result.effects[i]
                if (eff.id !== "theme" || !eff.params) continue
                for (var j = 0; j < eff.params.length; j++) {
                    if (eff.params[j].id === "theme") {
                        root._backdropThemes = eff.params[j].options || []
                        return
                    }
                }
            }
        })
    }

    readonly property string _layerRuleSnippet:
        "layer-rule {\n" +
        "    match namespace=\"^ryogami-paper-backdrop$\"\n" +
        "    place-within-backdrop true\n" +
        "}"

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Overview backdrop")
        subtitle: I18n.tr("Render the current wallpaper (optionally blurred) as the backdrop visible in niri's overview (Mod+O).")
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Show wallpaper in overview")
            description: I18n.tr("Serve a copy of the wallpaper as a layer-shell surface that niri places in the overview backdrop.")
            checked: Config.niriOverviewBackdrop
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.overviewBackdrop", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Blur the backdrop")
            description: I18n.tr("Apply a Gaussian blur to the overview backdrop. Turn off for a sharp backdrop.")
            checked: Config.niriOverviewBackdropBlurEnabled
            enabled: Config.niriOverviewBackdrop
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.overviewBackdropBlurEnabled", v) }
        }

        RowInput {
            colors: root.colors
            title: I18n.tr("Blur radius")
            description: I18n.tr("Gaussian blur radius applied to the copy. Higher is softer.")
            value: Config.niriOverviewBackdropBlur
            min: 1; max: 200
            enabled: Config.niriOverviewBackdrop && Config.niriOverviewBackdropBlurEnabled
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.overviewBackdropBlur", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Always use the current wallpaper")
            description: I18n.tr("Force the backdrop to track whatever wallpaper is applied, overriding any per-card backdrop you've set.")
            checked: Config.niriBackdropFollowWallpaper
            enabled: Config.niriOverviewBackdrop
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.backdropFollowWallpaper", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Auto-theme the backdrop")
            description: I18n.tr("Recolour the backdrop with a gowall theme palette.")
            checked: Config.niriBackdropAutoTheme
            enabled: Config.niriOverviewBackdrop
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.backdropAutoTheme", v) }
        }

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Backdrop theme")
            description: I18n.tr("Palette used when auto-theming the backdrop.")
            value: Config.niriBackdropTheme
            model: root._backdropThemes
            enabled: Config.niriOverviewBackdrop && Config.niriBackdropAutoTheme
            opacity: enabled ? 1.0 : 0.5
            onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.backdropTheme", v) }
        }

        RowInput {
            colors: root.colors
            title: I18n.tr("Backdrop dimming")
            description: I18n.tr("Darken the overview backdrop. 0 = none, 100 = black.")
            value: Config.niriBackdropDim
            min: 0; max: 100; suffix: "%"
            enabled: Config.niriOverviewBackdrop
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("niri.backdropDim", v) }
        }

        SettingsRow {
            colors: root.colors
            title: I18n.tr("Required niri layer-rule")
            description: I18n.tr("Paste this into your ~/.config/niri/config.kdl, then reload niri (e.g. niri msg action reload-config).")
        }

        Rectangle {
            width: parent.width - 28
            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
            height: snippetText.implicitHeight + 24
            radius: 6
            color: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.6) : Qt.rgba(0.1, 0.12, 0.18, 0.6)
            border.width: 1
            border.color: root.colors ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)

            TextEdit {
                id: snippetText
                anchors.fill: parent
                anchors.margins: 12
                text: root._layerRuleSnippet
                readOnly: true
                color: root.colors ? root.colors.surfaceText : "#fff"
                font.family: Style.fontFamilyCode
                font.pixelSize: 11 * Config.uiScale
                selectByMouse: true
                selectByKeyboard: true
                wrapMode: TextEdit.NoWrap
                textFormat: TextEdit.PlainText
                selectionColor: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.4) : Qt.rgba(0.5, 0.7, 1.0, 0.4)
            }
        }

        RowAction {
            colors: root.colors
            title: _refreshState._busy ? I18n.tr("Regenerating...") : I18n.tr("Regenerate backdrop now")
            description: I18n.tr("Re-blur the current wallpaper and respawn the backdrop renderer. Use this after toggling the feature on without applying a new wallpaper.")
            enabled: Config.niriOverviewBackdrop && !_refreshState._busy
            opacity: enabled ? 1.0 : 0.5
            onClicked: {
                _refreshState._busy = true
                DaemonClient.call("wall.refresh_overview_backdrop", {}, function(_r, _e) {
                    _refreshResetTimer.restart()
                })
            }

            QtObject {
                id: _refreshState
                property bool _busy: false
            }
            Timer {
                id: _refreshResetTimer
                interval: 3000
                onTriggered: _refreshState._busy = false
            }
        }

        RowAction {
            colors: root.colors
            title: _copyState._copied ? I18n.tr("Copied!") : I18n.tr("Copy layer-rule to clipboard")
            description: I18n.tr("Copies the snippet above so you can paste it directly into niri's config.")
            onClicked: {
                snippetText.selectAll()
                snippetText.copy()
                snippetText.deselect()
                _copyState._copied = true
                _copyResetTimer.restart()
            }

            QtObject {
                id: _copyState
                property bool _copied: false
            }
            Timer {
                id: _copyResetTimer
                interval: 1500
                onTriggered: _copyState._copied = false
            }
        }
    }
}
