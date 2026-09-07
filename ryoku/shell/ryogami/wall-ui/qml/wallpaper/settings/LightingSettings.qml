import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

// Lighting: peripheral RGB (OpenRGB), folded from the Hub's Appearance > Lighting
// tab. Master switch plus per-device controls (managed, mode, colour source,
// brightness, speed, save, release), driven by `ryoku-hub lighting`. State comes
// from `lighting state`; per-device mode lists from `lighting scan`.
Column {
    id: root
    property var colors
    width: parent ? parent.width : 0
    spacing: 8

    property bool _enabled: false
    property bool _available: true
    property var _devices: []
    property var _caps: ({})

    Component.onCompleted: { stateProc.running = true; scanProc.running = true }

    Timer { id: refreshTimer; interval: 500; onTriggered: stateProc.running = true }

    property string _sBuf: ""
    Process {
        id: stateProc
        command: ["ryoku-hub", "lighting", "state"]
        stdout: SplitParser { splitMarker: ""; onRead: function(d) { root._sBuf += d } }
        onExited: {
            try {
                var st = JSON.parse(root._sBuf)
                root._enabled = !!st.enabled
                root._available = st.available !== false
                root._devices = st.devices || []
            } catch (e) {}
            root._sBuf = ""
        }
    }

    property string _cBuf: ""
    Process {
        id: scanProc
        command: ["ryoku-hub", "lighting", "scan"]
        stdout: SplitParser { splitMarker: ""; onRead: function(d) { root._cBuf += d } }
        onExited: {
            try {
                var sc = JSON.parse(root._cBuf)
                var caps = {}
                var devs = sc.devices || []
                for (var i = 0; i < devs.length; i++) {
                    var d = devs[i]
                    var modes = []
                    var modeDirs = {}
                    var ms = d.modes || []
                    for (var j = 0; j < ms.length; j++) {
                        modes.push(ms[j].name)
                        modeDirs[ms[j].name] = ms[j].directions || []
                    }
                    var effects = []
                    var fx = d.effects || []
                    for (var k = 0; k < fx.length; k++) effects.push({ id: fx[k].id, label: fx[k].label })
                    caps[d.key] = { modes: modes, modeDirs: modeDirs, effects: effects }
                }
                root._caps = caps
            } catch (e) {}
            root._cBuf = ""
        }
    }

    function _enable(on) { Quickshell.execDetached(["ryoku-hub", "lighting", on ? "enable" : "disable"]); root._enabled = on; refreshTimer.restart() }
    function _set(key, obj) { Quickshell.execDetached(["ryoku-hub", "lighting", "set", key, JSON.stringify(obj)]); refreshTimer.restart() }
    function _save(key) { Quickshell.execDetached(["ryoku-hub", "lighting", "save", key]) }
    function _release(key) { Quickshell.execDetached(["ryoku-hub", "lighting", "release", key]); refreshTimer.restart() }

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Lighting"); kana: "灯"
        width: parent.width

        RowToggle {
            colors: root.colors
            title: I18n.tr("Enable device lighting")
            description: I18n.tr("Drive keyboard and peripheral RGB through OpenRGB.")
            checked: root._enabled
            onToggle: function(v) { root._enable(v) }
        }
    }

    Repeater {
        model: root._devices

        SettingsCard {
            colors: root.colors
            title: modelData.name || modelData.key
            subtitle: I18n.tr("%1 · %2").arg(modelData.online ? I18n.tr("online") : I18n.tr("offline")).arg(modelData.managed ? I18n.tr("managed") : I18n.tr("free"))
            width: parent.width

            RowToggle {
                colors: root.colors
                title: I18n.tr("Managed")
                description: I18n.tr("Let Ryoku drive this device's colour.")
                checked: !!modelData.managed
                onToggle: function(v) { root._set(modelData.key, { managed: v }) }
            }

            Row {
                id: devGrid
                width: parent.width
                spacing: 12 * Config.uiScale
                z: 5
                readonly property var _dcaps: root._caps[modelData.key] || ({})
                readonly property bool _hasEffect: ((devGrid._dcaps.effects) || []).length > 0
                readonly property var _dirs: (devGrid._dcaps.modeDirs && devGrid._dcaps.modeDirs[modelData.mode]) || []
                readonly property bool _hasDir: devGrid._dirs.length > 0
                readonly property int _n: 1 + (devGrid._hasEffect ? 1 : 0) + (devGrid._hasDir ? 1 : 0)
                readonly property real cellW: (width - spacing * (devGrid._n - 1)) / devGrid._n
                readonly property bool _live: root._enabled && !!modelData.managed
                opacity: devGrid._live ? 1.0 : 0.5

                SettingsDropdown {
                    width: devGrid.cellW
                    colors: root.colors
                    label: I18n.tr("Mode")
                    value: modelData.mode || ""
                    model: {
                        var out = []
                        var ms = (devGrid._dcaps.modes) || []
                        for (var i = 0; i < ms.length; i++) out.push({ mode: ms[i], label: ms[i] })
                        return out
                    }
                    onSelect: function(v) { if (devGrid._live) root._set(modelData.key, { mode: v }) }
                }

                SettingsDropdown {
                    width: devGrid.cellW
                    visible: devGrid._hasEffect
                    colors: root.colors
                    label: I18n.tr("Effect")
                    value: modelData.effect || ""
                    model: {
                        var out = [{ mode: "", label: I18n.tr("None") }]
                        var fx = (devGrid._dcaps.effects) || []
                        for (var i = 0; i < fx.length; i++) out.push({ mode: fx[i].id, label: fx[i].label })
                        return out
                    }
                    onSelect: function(v) { if (devGrid._live) root._set(modelData.key, { effect: v }) }
                }

                SettingsDropdown {
                    width: devGrid.cellW
                    visible: devGrid._hasDir
                    colors: root.colors
                    label: I18n.tr("Direction")
                    value: modelData.direction || ""
                    model: {
                        var out = []
                        var ds = devGrid._dirs
                        for (var i = 0; i < ds.length; i++) out.push({ mode: ds[i], label: ds[i] })
                        return out
                    }
                    onSelect: function(v) { if (devGrid._live) root._set(modelData.key, { direction: v }) }
                }
            }

            RowDropdown {
                colors: root.colors
                title: I18n.tr("Colour source")
                description: I18n.tr("Follow the wallpaper accent, or hold a fixed colour.")
                value: modelData.source || "accent"
                model: [ { mode: "accent", label: I18n.tr("Accent") }, { mode: "fixed", label: I18n.tr("Fixed") } ]
                enabled: root._enabled && !!modelData.managed
                opacity: enabled ? 1.0 : 0.5
                onSelect: function(v) { root._set(modelData.key, { source: v }) }
            }

            RowInput {
                colors: root.colors
                title: I18n.tr("Brightness")
                description: I18n.tr("Device brightness.")
                value: modelData.brightness >= 0 ? modelData.brightness : 90
                min: 0; max: 100; suffix: "%"
                enabled: root._enabled && !!modelData.managed
                onCommit: function(v) { root._set(modelData.key, { brightness: v }) }
            }

            RowInput {
                colors: root.colors
                title: I18n.tr("Speed")
                description: I18n.tr("Animation speed for animated modes.")
                value: modelData.speed >= 0 ? modelData.speed : 60
                min: 0; max: 100; suffix: "%"
                enabled: root._enabled && !!modelData.managed
                onCommit: function(v) { root._set(modelData.key, { speed: v }) }
            }

            RowAction {
                colors: root.colors
                title: I18n.tr("Save to device")
                description: I18n.tr("Persist the current look to the device's own memory.")
                valueLabel: I18n.tr("SAVE")
                onClicked: root._save(modelData.key)
            }

            RowAction {
                colors: root.colors
                title: I18n.tr("Hand back")
                description: I18n.tr("Stop managing and leave the device to its own control.")
                valueLabel: I18n.tr("RELEASE")
                onClicked: root._release(modelData.key)
            }
        }
    }

    SettingsCard {
        visible: root._devices.length === 0
        colors: root.colors
        title: I18n.tr("No devices")
        width: parent.width
        subtitle: root._available
            ? I18n.tr("No RGB devices detected. Connect a device OpenRGB supports, then reopen.")
            : I18n.tr("OpenRGB is not available. Install and start it to control device lighting.")
    }
}
