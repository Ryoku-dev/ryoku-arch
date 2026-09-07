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
        title: I18n.tr("Rendering")
        subtitle: I18n.tr("Defaults applied when linux-wallpaperengine renders a scene/web Workshop wallpaper.")
        width: parent.width

        RowInput {
            colors: root.colors
            title: I18n.tr("FPS cap")
            description: I18n.tr("Maximum frames per second. Lower values reduce CPU/GPU load.")
            value: Config.weRenderFps
            min: 1; max: 240
            onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.fps", v) }
        }

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Default scaling")
            description: I18n.tr("How a scene fits each monitor.")
            value: Config.weRenderScaling
            model: [
                { mode: "default", label: I18n.tr("Default") },
                { mode: "fill",    label: I18n.tr("Fill") },
                { mode: "fit",     label: I18n.tr("Fit") },
                { mode: "stretch", label: I18n.tr("Stretch") }
            ]
            onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.scaling", v) }
        }

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Default clamp")
            description: I18n.tr("How textures wrap at edges.")
            value: Config.weRenderClamp
            model: [
                { mode: "border", label: I18n.tr("Border") },
                { mode: "repeat", label: I18n.tr("Repeat") },
                { mode: "mirror", label: I18n.tr("Mirror") }
            ]
            onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.clamp", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Pause behaviour")
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Don't pause on fullscreen")
            description: I18n.tr("Keep the wallpaper running even when another window is fullscreen.")
            checked: Config.weRenderNoFullscreenPause
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.noFullscreenPause", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Only pause when fullscreen is active")
            description: I18n.tr("Wayland only. Pause only when a fullscreen window is the active one (not just present). Ignored if 'Don't pause on fullscreen' is on.")
            checked: Config.weRenderFullscreenPauseOnlyActive
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.fullscreenPauseOnlyActive", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Audio")
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable auto-mute")
            description: I18n.tr("Don't auto-mute the wallpaper when another app plays audio.")
            checked: Config.weRenderNoautomute
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.noautomute", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable audio processing")
            description: I18n.tr("Skip processing audio for audio-reactive wallpapers.")
            checked: Config.weRenderNoAudioProcessing
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.noAudioProcessing", v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Effects")
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable particles")
            description: I18n.tr("Skip particle effects on scenes that use them.")
            checked: Config.weRenderDisableParticles
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.disableParticles", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable mouse interaction")
            description: I18n.tr("Scenes can't react to mouse position when on.")
            checked: Config.weRenderDisableMouse
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.disableMouse", v) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("Disable parallax")
            description: I18n.tr("Skip parallax depth effect on supporting scenes.")
            checked: Config.weRenderDisableParallax
            onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("weRender.disableParallax", v) }
        }
    }
}
