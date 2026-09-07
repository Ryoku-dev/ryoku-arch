import QtQuick
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

Flow {
    id: root
    property var colors
    property var saveConfigKey

    width: parent ? parent.width : 0
    spacing: 12

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Directories")
        width: parent.width

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Wallpaper directory")
            description: I18n.tr("Folder Ryogami scans for image and video wallpapers. Restart required after change.")
            value: Config.wallpaperDir
            placeholder: I18n.tr("~/Pictures/Wallpapers")
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("paths.wallpaper", v) }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Video directory")
            description: I18n.tr("Separate folder for video wallpapers. Defaults to the wallpaper directory.")
            value: Config.videoDir
            placeholder: I18n.tr("(same as wallpaper directory)")
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("paths.videoWallpaper", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Steam")
        width: parent.width

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Workshop directory")
            description: I18n.tr("Where Steam stores Workshop content.")
            value: Config.weDir
            placeholder: I18n.tr("Steam Workshop content path")
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("paths.steamWorkshop", v) }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("WE assets directory")
            description: I18n.tr("Wallpaper Engine assets path.")
            value: Config.weAssetsDir
            placeholder: I18n.tr("Wallpaper Engine assets path")
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("paths.steamWeAssets", v) }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Steam directory")
            description: I18n.tr("Steam install root.")
            value: Config.steamDir
            placeholder: I18n.tr("Steam install path")
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("paths.steam", v) }
        }
    }
}
