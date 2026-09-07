import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property var saveConfigKey
    property var notifyThemeChanged
    property var _theme: ({ themeApps: true, gtkTheme: "adw", gnomeAccent: false })
    property string _reveal: "random"
    property var _mat: ({ lightnessDark: 0, lightnessLight: 0, prefer: "saturation", sourceColorIndex: 0 })
    readonly property var _revealModel: [
        "random", "silk_fade", "diagonal_silk", "dream_curtain", "liquid_ribbon",
        "iris_open", "corner_bloom", "spotlight_rise", "wander_iris", "vignette_close",
        "celeste_veil", "comet_streak", "aurora_ripple", "starfall_bloom",
        "mosaic_swell", "ember_burn", "pond_wake", "glass_scatter", "signal_tear",
        "cathode_wink", "shutter_sweep", "wax_descent", "page_turn"
    ].map(function(p) {
        return { mode: p, label: p === "random" ? I18n.tr("Random")
            : p.replace(/_/g, " ").replace(/^./, function(c) { return c.toUpperCase() }) }
    })

    function _runHub(args) { Quickshell.execDetached(["ryoku-hub"].concat(args)) }
    function _matugenSet(patch) { Quickshell.execDetached(["ryoku-hub", "hypr", "matugen", "set", JSON.stringify(patch)]) }

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/ryoku/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(themeFile.text())
                root._theme = { themeApps: d.themeApps !== false, gtkTheme: d.gtkTheme || "adw", gnomeAccent: !!d.gnomeAccent }
            } catch (e) {}
        }
    }

    FileView {
        id: shellFile
        path: Quickshell.env("HOME") + "/.config/ryoku/shell.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(shellFile.text())
                var v = (d.wallpaper && d.wallpaper.transition_preset) || "random"
                root._reveal = ("" + v).length ? ("" + v) : "random"
            } catch (e) {}
        }
    }

    FileView {
        id: matugenFile
        path: Quickshell.env("HOME") + "/.config/ryoku/matugen.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var d = JSON.parse(matugenFile.text())
                root._mat = {
                    lightnessDark: typeof d.lightnessDark === "number" ? d.lightnessDark : 0,
                    lightnessLight: typeof d.lightnessLight === "number" ? d.lightnessLight : 0,
                    prefer: d.prefer || "saturation",
                    sourceColorIndex: typeof d.sourceColorIndex === "number" ? (d.sourceColorIndex | 0) : 0
                }
            } catch (e) {}
        }
    }

    width: parent ? parent.width : 0
    spacing: 8

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Theme")
        width: parent.width

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Scheme type")
            description: I18n.tr("Material 3 colour-generation algorithm.")
            value: Config.matugenScheme.replace("scheme-", "")
            model: [
                { mode: "content",     label: I18n.tr("Content") },
                { mode: "expressive",  label: I18n.tr("Expressive") },
                { mode: "fidelity",    label: I18n.tr("Fidelity") },
                { mode: "fruit-salad", label: I18n.tr("Fruit salad") },
                { mode: "monochrome",  label: I18n.tr("Monochrome") },
                { mode: "neutral",     label: I18n.tr("Neutral") },
                { mode: "rainbow",     label: I18n.tr("Rainbow") },
                { mode: "tonal-spot",  label: I18n.tr("Tonal spot") },
                { mode: "vibrant",     label: I18n.tr("Vibrant") }
            ]
            onSelect: function(v) {
                var full = "scheme-" + v
                if (root.saveConfigKey) root.saveConfigKey("matugen.schemeType", full)
                if (root.notifyThemeChanged) root.notifyThemeChanged(full, Config.matugenMode, root._mat.sourceColorIndex)
            }
        }

        RowTextInput {
            colors: root.colors
            title: I18n.tr("Contrast")
            description: I18n.tr("Matugen contrast. Range -1.0 to 1.0 (0 = standard, higher = more contrast).")
            value: Config.matugenContrast.toFixed(2)
            placeholder: "0.00"
            onCommit: function(v) {
                var n = parseFloat(v)
                if (isNaN(n)) n = 0
                n = Math.max(-1, Math.min(1, n))
                if (root.saveConfigKey) root.saveConfigKey("matugen.contrast", n)
                if (root.notifyThemeChanged) root.notifyThemeChanged(Config.matugenScheme, Config.matugenMode, root._mat.sourceColorIndex)
            }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Colour generation")
        kana: "生成"
        width: parent.width

        Column {
            width: parent.width
            spacing: 12 * Config.uiScale
            topPadding: 4 * Config.uiScale

            Row {
                id: genGrid1
                width: parent.width
                spacing: 12 * Config.uiScale
                z: 5
                readonly property real cellW: (width - spacing * 2) / 3

                SettingsDropdown {
                    width: genGrid1.cellW
                    colors: root.colors
                    label: I18n.tr("Mode")
                    value: Config.matugenMode
                    model: [
                        { mode: "dark",  label: I18n.tr("Dark") },
                        { mode: "light", label: I18n.tr("Light") },
                        { mode: "smart", label: I18n.tr("Smart") }
                    ]
                    onSelect: function(v) {
                        if (root.saveConfigKey) root.saveConfigKey("matugen.mode", v)
                        if (root.notifyThemeChanged) root.notifyThemeChanged(Config.matugenScheme, v, root._mat.sourceColorIndex)
                    }
                }

                SettingsDropdown {
                    width: genGrid1.cellW
                    colors: root.colors
                    label: I18n.tr("Source index")
                    value: String(root._mat.sourceColorIndex)
                    model: [
                        { mode: "0", label: I18n.tr("0 (Primary)") },
                        { mode: "1", label: "1" },
                        { mode: "2", label: "2" },
                        { mode: "3", label: "3" },
                        { mode: "4", label: "4" }
                    ]
                    onSelect: function(v) {
                        var idx = parseInt(v, 10) | 0
                        if (root.saveConfigKey) root.saveConfigKey("matugen.colorIndex", idx)
                        if (root.notifyThemeChanged) root.notifyThemeChanged(Config.matugenScheme, Config.matugenMode, idx)
                    }
                }

                SettingsDropdown {
                    width: genGrid1.cellW
                    colors: root.colors
                    label: I18n.tr("Preference")
                    value: root._mat.prefer
                    model: [
                        { mode: "darkness",            label: I18n.tr("Darkness") },
                        { mode: "lightness",           label: I18n.tr("Lightness") },
                        { mode: "saturation",          label: I18n.tr("Saturation") },
                        { mode: "less-saturation",     label: I18n.tr("Less saturation") },
                        { mode: "value",               label: I18n.tr("Value") },
                        { mode: "closest-to-fallback", label: I18n.tr("Closest to fallback") }
                    ]
                    onSelect: function(v) { root._matugenSet({ prefer: v }) }
                }
            }

            Row {
                id: genGrid2
                width: parent.width
                spacing: 12 * Config.uiScale
                readonly property real cellW: (width - spacing) / 2

                SettingsSlider {
                    width: genGrid2.cellW
                    colors: root.colors
                    label: I18n.tr("Lightness (dark)")
                    min: -100; max: 100
                    resettable: true; defaultValue: 0
                    value: Math.round(root._mat.lightnessDark * 100)
                    onCommit: function(v) { root._matugenSet({ lightnessDark: v / 100 }) }
                }

                SettingsSlider {
                    width: genGrid2.cellW
                    colors: root.colors
                    label: I18n.tr("Lightness (light)")
                    min: -100; max: 100
                    resettable: true; defaultValue: 0
                    value: Math.round(root._mat.lightnessLight * 100)
                    onCommit: function(v) { root._matugenSet({ lightnessLight: v / 100 }) }
                }
            }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("App theming")
        kana: "配色"
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Theme apps")
            description: I18n.tr("Recolour GTK and app themes to match the scheme.")
            checked: root._theme.themeApps
            onToggle: function(v) { root._theme.themeApps = v; root._runHub(["hypr", "theme-apps", v ? "on" : "off"]) }
        }

        RowDropdown {
            colors: root.colors
            title: I18n.tr("GTK theme")
            description: I18n.tr("Base GTK theme that apps build on.")
            value: root._theme.gtkTheme
            model: [ { mode: "adw", label: "Adw" }, { mode: "adwaita", label: "Adwaita" }, { mode: "system", label: I18n.tr("System") } ]
            onSelect: function(v) { root._theme.gtkTheme = v; root._runHub(["hypr", "gtk-theme", v]) }
        }

        RowToggle {
            colors: root.colors
            title: I18n.tr("GNOME accent")
            description: I18n.tr("Sync the GNOME accent colour to the scheme.")
            checked: root._theme.gnomeAccent
            onToggle: function(v) { root._theme.gnomeAccent = v; root._runHub(["hypr", "gnome-accent", v ? "on" : "off"]) }
        }

        RowAction {
            colors: root.colors
            title: I18n.tr("Ryoku signature")
            description: I18n.tr("Apply the Ryoku theme: frame bars, zero roundness, mono scheme.")
            valueLabel: I18n.tr("APPLY")
            onClicked: root._runHub(["hypr", "ryoku-theme"])
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Wallpaper")
        kana: "壁"
        width: parent.width

        RowDropdown {
            colors: root.colors
            title: I18n.tr("Reveal")
            description: I18n.tr("The transition played when the wallpaper changes.")
            value: root._reveal
            model: root._revealModel
            onSelect: function(v) {
                root._reveal = v
                Quickshell.execDetached(["ryoku-shell", "call", "settings.patch",
                    JSON.stringify({ path: "wallpaper.transition_preset", value: v })])
            }
        }
    }
}
