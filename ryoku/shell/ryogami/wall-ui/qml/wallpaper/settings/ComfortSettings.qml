import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

// Comfort: screen backlight + warm-light (night light), folded from the Hub's
// Appearance > Comfort tab. Brightness rides brightnessctl; the warm screen
// rides the shipped ryoku-cmd-nightlight script (hyprsunset).
Column {
    id: root
    property var colors
    width: parent ? parent.width : 0
    spacing: 8

    property int _brightness: 100
    property bool _warm: false
    property int _temp: 4000
    readonly property string _nlScript: Quickshell.env("HOME") + "/.config/hypr/scripts/ryoku-cmd-nightlight"

    Component.onCompleted: { brProc.running = true; nlProc.running = true }

    property string _brBuf: ""
    Process {
        id: brProc
        command: ["brightnessctl", "-m"]
        stdout: SplitParser { splitMarker: ""; onRead: function(d) { root._brBuf += d } }
        onExited: {
            var line = (root._brBuf.trim().split("\n")[0]) || ""
            var parts = line.split(",")          // device,class,current,percent,max
            if (parts.length >= 4) {
                var p = parseInt(parts[3])
                if (!isNaN(p)) root._brightness = p
            }
            root._brBuf = ""
        }
    }

    property string _nlBuf: ""
    Process {
        id: nlProc
        command: [root._nlScript, "status"]
        stdout: SplitParser { splitMarker: ""; onRead: function(d) { root._nlBuf += d } }
        onExited: {
            var s = root._nlBuf.trim()
            root._warm = s !== "" && s.indexOf("off") < 0
            var t = parseInt(s.replace(/[^0-9]/g, ""))
            if (!isNaN(t) && t >= 2500 && t <= 6500) root._temp = t
            root._nlBuf = ""
        }
    }

    function _setBrightness(v) { Quickshell.execDetached(["brightnessctl", "set", v + "%"]) }
    function _nightlight(on) {
        if (on) Quickshell.execDetached([root._nlScript, "on", "" + root._temp])
        else Quickshell.execDetached([root._nlScript, "off"])
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Screen"); kana: "画面"
        width: parent.width

        RowInput {
            colors: root.colors
            title: I18n.tr("Brightness")
            description: I18n.tr("Display backlight level.")
            value: root._brightness
            min: 5; max: 100; suffix: "%"
            onCommit: function(v) { root._brightness = v; root._setBrightness(v) }
        }
    }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Warm light"); kana: "暖色"
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Warm screen")
            description: I18n.tr("Cut blue light with a night-light tint (hyprsunset).")
            checked: root._warm
            onToggle: function(v) { root._warm = v; root._nightlight(v) }
        }

        RowInput {
            colors: root.colors
            title: I18n.tr("Temperature")
            description: I18n.tr("Colour temperature in Kelvin. Lower is warmer.")
            value: root._temp
            min: 2500; max: 6500; suffix: "K"
            enabled: root._warm
            onCommit: function(v) { root._temp = v; if (root._warm) root._nightlight(true) }
        }
    }
}
