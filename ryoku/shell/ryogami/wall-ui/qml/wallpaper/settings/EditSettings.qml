import QtQuick
import ".."
import "../.."
import "../../components"
import "../../services"
import Ryoku.Ui.Singletons

// The Edit / Transform tab: everything that reworks the focused wallpaper in
// one place. A shared preview on top, a Grade · Effects · Upscale sub-nav, then
// only the active group's controls. Grade is a live imagemagick grade
// (grade.preview / grade.commit), Effects is the gowall recolour engine
// (effects.list / preview / commit / discard), Upscale is a waifu2x job
// (upscale.start / status / cancel). sourcePath is the focused wallpaper.
Column {
    id: root
    property var colors
    property string sourcePath: ""

    property string _group: "grade"

    // grade
    property int _brightness: 0
    property int _contrast: 0
    property int _saturation: 0
    property int _warmth: 0
    property bool _vignette: false
    property bool _negate: false
    property string _gradePath: ""
    property bool _committing: false
    property bool _desktopView: false

    // effects
    property var _effects: []
    property string _effectId: ""
    property var _paramValues: ({})
    property string _fxPath: ""
    property string _fxStatus: ""
    property bool _fxPendingApply: false

    // upscale
    property int _upScale: 2
    property var _up: ({ running: false, phase: "", progress: 0, total: 0, verdict: null })

    property int _previewVer: 0

    readonly property bool _dirty: _brightness !== 0 || _contrast !== 0 || _saturation !== 0 || _warmth !== 0 || _vignette || _negate
    readonly property color _ink:    colors ? colors.surfaceText : "#e0e2e8"
    readonly property color _inkDim: colors ? colors.surfaceVariantText : "#c2c7cf"
    readonly property color _line:   colors ? colors.outline : Qt.rgba(1, 1, 1, 0.22)
    readonly property bool _isVideo: {
        var p = ("" + root.sourcePath).toLowerCase()
        return p.endsWith(".mp4") || p.endsWith(".webm") || p.endsWith(".mkv") || p.endsWith(".mov") || p.endsWith(".m4v") || p.endsWith(".avi")
    }

    // whichever transformed frame the active group is previewing
    readonly property string _shownPath: _group === "grade" ? _gradePath : (_group === "effects" ? _fxPath : "")

    readonly property var _selectedEffect: {
        for (var i = 0; i < _effects.length; i++)
            if (_effects[i].id === _effectId) return _effects[i]
        return null
    }
    readonly property var _categoryOrder: ["Colour", "Tone", "Stylize", "Distort", "Adjust", "Transform"]

    Component.onCompleted: {
        DaemonClient.paletteFrameStatus()
        DaemonClient.call("effects.list", {}, function(res, err) {
            if (!err && res && res.effects) {
                root._effects = res.effects
                if (root._effects.length > 0) {
                    root._effectId = root._effects[0].id
                    root._resetParams()
                }
            }
        })
    }

    width: parent ? parent.width : 0
    spacing: 12

    onSourcePathChanged: root._reset()
    function _selectGroup(g) {
        root._group = g
        if (g === "effects" && root._effects.length > 0 && root._fxPath.length === 0)
            root._scheduleFxPreview()
    }
    function _reset() {
        _brightness = 0; _contrast = 0; _saturation = 0; _warmth = 0; _vignette = false; _negate = false; _gradePath = ""
        root._discardFx()
    }

    // grade
    Timer { id: debounce; interval: 220; onTriggered: root._doPreview() }
    function _schedulePreview() { if (root.sourcePath) debounce.restart() }
    function _doPreview() {
        DaemonClient.call("grade.preview", {
            input: root.sourcePath, brightness: root._brightness, contrast: root._contrast,
            saturation: root._saturation, warmth: root._warmth, vignette: root._vignette, negate: root._negate
        }, function(res, err) { if (!err && res && res.output) { root._gradePath = res.output; root._previewVer++ } })
    }
    function _apply() {
        if (!root.sourcePath || root._committing) return
        root._committing = true
        DaemonClient.call("grade.commit", {
            input: root.sourcePath, brightness: root._brightness, contrast: root._contrast,
            saturation: root._saturation, warmth: root._warmth, vignette: root._vignette, negate: root._negate
        }, function(res, err) { root._committing = false; if (!err) root._reset() })
    }

    // effects
    function _hex(c) {
        if (typeof c === "string") return c
        function pair(f) { var s = Math.round(f * 255).toString(16); return s.length === 1 ? "0" + s : s }
        return "#" + pair(c.r) + pair(c.g) + pair(c.b)
    }
    function _resetParams() {
        var v = {}
        var eff = _selectedEffect
        if (eff && eff.params)
            for (var i = 0; i < eff.params.length; i++) v[eff.params[i].id] = eff.params[i]["default"]
        _paramValues = v
    }
    function _setParam(id, value) {
        var v = {}
        for (var k in _paramValues) v[k] = _paramValues[k]
        v[id] = value
        _paramValues = v
        _scheduleFxPreview()
    }
    function _effectModel() {
        var out = []
        for (var i = 0; i < _effects.length; i++)
            out.push({ mode: _effects[i].id, label: _effects[i].label, category: _effects[i].category || "", _i: i })
        var order = _categoryOrder
        out.sort(function(a, b) {
            var ca = order.indexOf(a.category); if (ca < 0) ca = 999
            var cb = order.indexOf(b.category); if (cb < 0) cb = 999
            if (ca !== cb) return ca - cb
            return a._i - b._i
        })
        return out
    }
    function _outboundParams() {
        var out = {}
        for (var k in _paramValues) {
            var v = _paramValues[k]
            if (typeof v === "object" && v !== null && "r" in v && "g" in v && "b" in v) out[k] = _hex(v)
            else out[k] = v
        }
        return out
    }
    Timer { id: fxDebounce; interval: 350; onTriggered: root._launchFxPreview() }
    function _scheduleFxPreview() { if (root.sourcePath && root._selectedEffect) fxDebounce.restart() }
    function _launchFxPreview() {
        if (!root.sourcePath || !root._selectedEffect) return
        if (root._fxPath.length > 0) { EffectsService.discard(root._fxPath); root._fxPath = "" }
        root._fxStatus = ""
        EffectsService.preview(root._effectId, root.sourcePath, root._outboundParams())
    }
    function _discardFx() {
        if (root._fxPath.length > 0) { EffectsService.discard(root._fxPath); root._fxPath = "" }
    }
    function _applyFx() {
        if (root._fxPath.length === 0 || EffectsService.busy) return
        root._fxPendingApply = true
        EffectsService.commit(root._fxPath, root.sourcePath, root._effectId, root._outboundParams())
    }

    Connections {
        target: EffectsService
        function onPreviewed(p) { root._fxPath = p; root._previewVer++; root._fxStatus = "" }
        function onCommitted(p) {
            root._fxPath = ""
            if (root._fxPendingApply) { root._fxPendingApply = false; DaemonClient.applyStatic(p, [], []) }
            root._fxStatus = I18n.tr("Saved to %1").arg(p)
        }
        function onFailed(error) { root._fxPendingApply = false; root._fxStatus = I18n.tr("Failed: %1").arg(error) }
    }

    // upscale
    Timer { id: upPoll; interval: 500; repeat: true; running: root._up.running; onTriggered: root._pollUpscale() }
    function _startUpscale() {
        if (!root.sourcePath) return
        DaemonClient.call("upscale.start", { input: root.sourcePath, scale: root._upScale }, function(res, err) {
            if (!err) root._up = { running: true, phase: "starting", progress: 0, total: 0, verdict: null }
        })
    }
    function _pollUpscale() { DaemonClient.call("upscale.status", {}, function(res, err) { if (!err && res) root._up = res }) }
    function _cancelUpscale() { DaemonClient.call("upscale.cancel", {}, function() {}) }

    // shared preview
    Rectangle {
        width: parent.width
        height: 300 * Config.uiScale
        radius: Style.radiusMedium
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1; border.color: root._line
        clip: true
        Image {
            anchors.fill: parent; anchors.margins: 1
            visible: !root._desktopView
            source: root._shownPath ? ("file://" + root._shownPath + "?v=" + root._previewVer)
                   : (root.sourcePath ? ("file://" + root.sourcePath) : "")
            fillMode: Image.PreserveAspectFit
            asynchronous: true; cache: false; smooth: true; mipmap: true
            sourceSize: Qt.size(1200, 700)
        }
        MockDesktop {
            anchors.fill: parent; anchors.margins: 1
            visible: root._desktopView && !!root.sourcePath && !root._isVideo
            pv: palPreview
            wallpaper: root._shownPath ? root._shownPath : root.sourcePath
        }
        Text {
            visible: !root.sourcePath
            anchors.centerIn: parent
            text: I18n.tr("no wallpaper focused")
            font.family: Style.fontFamily; font.pixelSize: 12; color: root._inkDim
        }
        Rectangle {
            visible: root._group === "effects" && EffectsService.busy
            anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
            width: busyLabel.implicitWidth + 12; height: busyLabel.implicitHeight + 6
            radius: Style.radiusSmall
            color: Qt.rgba(0, 0, 0, 0.6)
            Text {
                id: busyLabel
                anchors.centerIn: parent
                text: I18n.tr("RENDERING")
                font.family: Style.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1
                color: "white"
            }
        }
        Rectangle {
            visible: !!root.sourcePath && !root._isVideo
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
            width: toggleRow.width + 12; height: toggleRow.height + 8
            radius: Style.radiusSmall
            color: Qt.rgba(0, 0, 0, 0.45)
            Row {
                id: toggleRow
                anchors.centerIn: parent
                spacing: 6
                FilterButton {
                    colors: root.colors; icon: "\u{f02e9}"; tooltip: I18n.tr("Wallpaper")
                    isActive: !root._desktopView
                    onClicked: root._desktopView = false
                }
                FilterButton {
                    colors: root.colors; icon: "\u{f0379}"; tooltip: I18n.tr("Desktop preview")
                    isActive: root._desktopView
                    onClicked: root._desktopView = true
                }
            }
        }
        PalettePreview {
            id: palPreview
            visible: false
            source: root._isVideo ? "" : (root._shownPath ? root._shownPath : root.sourcePath)
        }
    }

    // Grade · Effects · Upscale sub-nav
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacingSmall
        Repeater {
            model: [
                { key: "grade",   label: "GRADE" },
                { key: "effects", label: "EFFECTS" },
                { key: "upscale", label: "UPSCALE" }
            ]
            FilterButton {
                colors: root.colors
                label: I18n.tr(modelData.label)
                register: false
                height: 26
                isActive: root._group === modelData.key
                onClicked: root._selectGroup(modelData.key)
            }
        }
    }

    // GRADE
    SettingsCard {
        visible: root._group === "grade"
        colors: root.colors
        title: I18n.tr("Grade"); kana: "色"
        width: parent.width

        Column {
            width: parent.width
            spacing: Style.spacingMedium

            SettingsSlider { colors: root.colors; label: I18n.tr("Brightness"); value: root._brightness; min: -50; max: 50; resettable: true; onChange: function(v){ root._brightness = v; root._schedulePreview() } }
            SettingsSlider { colors: root.colors; label: I18n.tr("Contrast");   value: root._contrast;   min: -50; max: 50; resettable: true; onChange: function(v){ root._contrast = v; root._schedulePreview() } }
            SettingsSlider { colors: root.colors; label: I18n.tr("Saturation"); value: root._saturation; min: -100; max: 100; resettable: true; onChange: function(v){ root._saturation = v; root._schedulePreview() } }
            SettingsSlider { colors: root.colors; label: I18n.tr("Warmth");     value: root._warmth;     min: -100; max: 100; resettable: true; onChange: function(v){ root._warmth = v; root._schedulePreview() } }

            RowToggle { colors: root.colors; title: I18n.tr("Vignette"); description: I18n.tr("Darken the frame edges."); checked: root._vignette; onToggle: function(v){ root._vignette = v; root._schedulePreview() } }
            RowToggle { colors: root.colors; title: I18n.tr("Negate"); description: I18n.tr("Invert the colours. Baked in on Apply."); checked: root._negate; onToggle: function(v){ root._negate = v; root._schedulePreview() } }

            Item {
                width: parent.width; height: 32
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    FilterButton { colors: root.colors; label: I18n.tr("RESET"); register: false; onClicked: root._reset() }
                    FilterButton { colors: root.colors; label: root._committing ? I18n.tr("APPLYING\u2026") : I18n.tr("APPLY GRADE"); register: false; hasActiveColor: root._dirty && !root._committing; activeColor: root.colors ? root.colors.primary : Style.fallbackAccent; isActive: root._dirty && !root._committing; onClicked: root._apply() }
                }
            }
        }
    }

    // EFFECTS
    SettingsCard {
        visible: root._group === "effects"
        colors: root.colors
        title: I18n.tr("Effects"); kana: "彩"
        subtitle: root._selectedEffect ? root._selectedEffect.description : I18n.tr("gowall recolour and stylise the focused wallpaper.")
        width: parent.width

        Column {
            width: parent.width
            spacing: Style.spacingMedium

            RowDropdown {
                colors: root.colors
                title: I18n.tr("Effect")
                value: root._effectId
                model: root._effectModel()
                onSelect: function(v) { root._effectId = v; root._resetParams(); root._scheduleFxPreview() }
            }

            Repeater {
                model: root._selectedEffect ? root._selectedEffect.params : []
                delegate: Loader {
                    required property var modelData
                    property var pData: modelData
                    width: parent ? parent.width : 0
                    sourceComponent: {
                        switch (modelData.type) {
                            case "integer":  return _intComp
                            case "number":   return _numComp
                            case "dropdown": return _ddComp
                            case "color":    return _colorComp
                        }
                        return null
                    }
                }
            }

            Item {
                width: parent.width; height: 32
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - fxBtns.width - 12
                    elide: Text.ElideRight
                    visible: root._fxStatus.length > 0
                    text: root._fxStatus
                    font.family: Style.fontFamily; font.pixelSize: 10; color: root._inkDim
                }
                Row {
                    id: fxBtns
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    FilterButton { colors: root.colors; label: EffectsService.busy ? I18n.tr("PREVIEWING\u2026") : I18n.tr("PREVIEW"); register: false; onClicked: root._launchFxPreview() }
                    FilterButton { colors: root.colors; label: I18n.tr("DISCARD"); register: false; enabled: root._fxPath.length > 0; opacity: enabled ? 1 : 0.4; onClicked: root._discardFx() }
                    FilterButton { colors: root.colors; label: I18n.tr("APPLY"); register: false; hasActiveColor: root._fxPath.length > 0 && !EffectsService.busy; activeColor: root.colors ? root.colors.primary : Style.fallbackAccent; isActive: root._fxPath.length > 0 && !EffectsService.busy; enabled: root._fxPath.length > 0 && !EffectsService.busy; opacity: enabled ? 1 : 0.4; onClicked: root._applyFx() }
                }
            }

            Text {
                width: parent.width
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                text: I18n.tr("Theme changing is a Rust implementation of <a href=\"https://github.com/Achno/gowall\">gowall</a> by Achno.")
                font.family: Style.fontFamily; font.pixelSize: 10
                color: Qt.rgba(root._inkDim.r, root._inkDim.g, root._inkDim.b, 0.75)
                linkColor: root.colors ? root.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0)
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    // UPSCALE
    SettingsCard {
        visible: root._group === "upscale"
        colors: root.colors
        title: I18n.tr("Upscale"); kana: "拡大"
        width: parent.width

        Item {
            width: parent.width; height: 40
            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("Scale"); font.family: Style.fontFamily; font.pixelSize: 12; font.weight: Font.Medium; color: root._ink }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: [2, 4]
                    FilterButton { colors: root.colors; label: modelData + "x"; register: false; isActive: root._upScale === modelData; onClicked: root._upScale = modelData }
                }
            }
        }

        Item {
            width: parent.width; height: 44
            Rectangle {
                visible: root._up.running
                anchors { left: parent.left; right: upBtn.left; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                height: 6; radius: 3
                color: Qt.rgba(root._ink.r, root._ink.g, root._ink.b, 0.12)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * ((root._up.total > 0) ? Math.max(0, Math.min(1, root._up.progress / root._up.total)) : 0.15)
                    radius: 3
                    color: root.colors ? root.colors.primary : Style.fallbackAccent
                    Behavior on width { NumberAnimation { duration: Style.animFast } }
                }
            }
            Text {
                visible: !root._up.running
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width - upBtn.width - 12
                elide: Text.ElideRight
                text: (root._up.verdict && root._up.verdict.why) ? root._up.verdict.why : I18n.tr("waifu2x-ncnn-vulkan. Writes an upscaled copy beside the original.")
                font.family: Style.fontFamily; font.pixelSize: 10; color: root._inkDim
            }
            Text {
                visible: root._up.running
                anchors { right: upBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: (root._up.phase || "working") + (root._up.total > 0 ? ("  " + root._up.progress + "/" + root._up.total) : "")
                font.family: Style.fontFamilyCode; font.pixelSize: 9; color: root._inkDim
            }
            FilterButton {
                id: upBtn
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                colors: root.colors
                label: root._up.running ? I18n.tr("CANCEL") : I18n.tr("UPSCALE")
                register: false
                hasActiveColor: true
                activeColor: root._up.running ? (root.colors ? root.colors.error : "#e2342a") : (root.colors ? root.colors.primary : Style.fallbackAccent)
                isActive: true
                onClicked: root._up.running ? root._cancelUpscale() : root._startUpscale()
            }
        }
    }

    // video palette-frame picker stays with Grade
    SettingsCard {
        visible: root._group === "grade" && root._isVideo
        colors: root.colors
        title: I18n.tr("Palette frame"); kana: "採色"
        width: parent.width

        RowInput {
            colors: root.colors
            title: I18n.tr("Sample second")
            description: I18n.tr("Which second of a video clip matugen samples for the colour scheme. Re-derives the palette from that frame.")
            value: Math.round(DaemonClient.paletteFrame)
            min: 0; max: 20; suffix: "s"
            onCommit: function(v) { DaemonClient.setPaletteFrame(v) }
        }
    }

    Component {
        id: _intComp
        RowInput {
            readonly property var pd: parent ? parent.pData : null
            colors: root.colors
            title: pd ? I18n.tr(pd.label) : ""
            value: pd && root._paramValues[pd.id] !== undefined ? root._paramValues[pd.id] : (pd ? (pd["default"] || 0) : 0)
            min: pd && pd.min !== undefined ? pd.min : 0
            max: pd && pd.max !== undefined ? pd.max : 9999
            onCommit: function(v) { if (pd) root._setParam(pd.id, v) }
        }
    }
    Component {
        id: _numComp
        RowInput {
            readonly property var pd: parent ? parent.pData : null
            colors: root.colors
            title: pd ? I18n.tr(pd.label) : ""
            value: pd && root._paramValues[pd.id] !== undefined ? root._paramValues[pd.id] : (pd ? (pd["default"] || 0) : 0)
            min: pd && pd.min !== undefined ? pd.min : 0
            max: pd && pd.max !== undefined ? pd.max : 9999
            decimals: pd && pd.decimals !== undefined ? pd.decimals : 2
            onCommit: function(v) { if (pd) root._setParam(pd.id, v) }
        }
    }
    Component {
        id: _ddComp
        RowDropdown {
            readonly property var pd: parent ? parent.pData : null
            colors: root.colors
            title: pd ? I18n.tr(pd.label) : ""
            value: pd && root._paramValues[pd.id] !== undefined ? root._paramValues[pd.id] : (pd ? (pd["default"] || "") : "")
            model: pd && pd.options ? pd.options : []
            onSelect: function(v) { if (pd) root._setParam(pd.id, v) }
        }
    }
    Component {
        id: _colorComp
        RowColor {
            readonly property var pd: parent ? parent.pData : null
            colors: root.colors
            title: pd ? I18n.tr(pd.label) : ""
            value: {
                if (!pd) return "#000000"
                var v = root._paramValues[pd.id]
                if (v === undefined) return pd["default"] || "#000000"
                return v
            }
            onCommit: function(c) { if (pd) root._setParam(pd.id, c) }
        }
    }
}
