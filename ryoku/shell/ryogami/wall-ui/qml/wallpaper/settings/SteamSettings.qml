import QtQuick
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

Flow {
    id: root
    property var colors
    property var saveField
    property var saveConfigKey

    width: parent ? parent.width : 0
    spacing: 12

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Grid")
        width: (parent.width - parent.spacing) / 2

        RowInput {
            colors: root.colors
            title: I18n.tr("Columns")
            description: I18n.tr("Number of thumbnails per row.")
            value: Config.steamColumns
            min: 2; max: 12
            onCommit: function(v) { if (root.saveField) root.saveField("steamColumns", v) }
        }

        RowInput {
            colors: root.colors
            title: I18n.tr("Rows")
            description: I18n.tr("Number of rows visible at once.")
            value: Config.steamRows
            min: 1; max: 10
            onCommit: function(v) { if (root.saveField) root.saveField("steamRows", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Thumbnail")
        width: (parent.width - parent.spacing) / 2

        RowInput {
            colors: root.colors
            title: I18n.tr("Width")
            description: I18n.tr("Thumbnail width in pixels.")
            value: Config.steamThumbWidth
            min: 100; max: 600
            onCommit: function(v) { if (root.saveField) root.saveField("steamThumbWidth", v) }
        }

        RowInput {
            colors: root.colors
            title: I18n.tr("Height")
            description: I18n.tr("Thumbnail height in pixels.")
            value: Config.steamThumbHeight
            min: 60; max: 600
            onCommit: function(v) { if (root.saveField) root.saveField("steamThumbHeight", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Download backend")
        width: parent.width

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Backend")
            description: I18n.tr("Two ways to set up Steam Workshop:\n- API key + steamcmd (recommended): add a Steam Web API key and set the backend to steamcmd. Browsing and downloads both work, no running Steam needed.\n- Steam Client: leave defaults and keep Steam running. Native client support on NixOS and Flatpak Steam is WIP - use the API key + steamcmd setup there.\n\nSwitching backend takes effect after the daemon restarts.")
            value: Config.steamBackend
            model: [
                { mode: "steamcmd", label: I18n.tr("steamcmd + API key (recommended)") },
                { mode: "steam",    label: I18n.tr("Steam Client") }
            ]
            onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("steam.backend", v) }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Username")
            description: I18n.tr("Only used by the steamcmd backend.")
            value: Config.steamUsername
            placeholder: I18n.tr("Steam username (for steamcmd)")
            enabled: Config.steamBackend === "steamcmd"
            opacity: enabled ? 1.0 : 0.5
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("steam.username", v) }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("API key")
            description: I18n.tr("Only used by the steamcmd backend, for browsing the Workshop catalogue inside ryogami-wall. The Steam Client backend gets browse access for free from the running Steam session.")
            value: Config.steamApiKey
            placeholder: I18n.tr("Steam API key")
            enabled: Config.steamBackend === "steamcmd"
            opacity: enabled ? 1.0 : 0.5
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("steam.apiKey", v) }
        }
    }
}
