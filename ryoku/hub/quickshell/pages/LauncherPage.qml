pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."

Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    readonly property var keys: [
        "variant", "radius", "bgBlur", "weatherUnit", "heroImage",
        "heroStrength", "heroPosX", "heroPosY", "showWeather", "showGreeting",
        "resultSettleMs", "horizonMode", "horizonColor"
    ]
    readonly property var factory: ({
            "variant": "hero", "radius": 16, "bgBlur": 2, "weatherUnit": "auto", "heroImage": "",
            "heroStrength": 0.6, "heroPosX": 0.5, "heroPosY": 0.5,
            "showWeather": true, "showGreeting": true, "resultSettleMs": 360,
            "horizonMode": "auto", "horizonColor": "#ffc777"
        })
    readonly property string launcherRoot: {
        var shellDir = String(Quickshell.env("RYOKU_SHELL_DIR") || "");
        if (shellDir.length > 0)
            return shellDir + "/quickshell/shell/modules/launcher";
        // Deployed Hub QML loads from a qrc namespace, so Qt.resolvedUrl gives no
        // usable file path; read the launcher the shell installs beside us.
        var cfg = String(Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"));
        return cfg + "/quickshell/shell/modules/launcher";
    }
    property var catalog: ({ version: 0, fallback: "", variants: [] })

    property var draft: pg.clone(pg.factory)
    property var committed: pg.clone(pg.factory)
    property bool loaded: false

    function clone(o) {
        var r = {};
        for (var k in o)
            r[k] = o[k];
        return r;
    }
    function catalogVariants() {
        return pg.catalog && Array.isArray(pg.catalog.variants)
            ? pg.catalog.variants : [];
    }
    function variantEntry(id) {
        var variants = pg.catalogVariants();
        var requested = String(id || "");
        for (var i = 0; i < variants.length; i++)
            if (String(variants[i].id || "") === requested)
                return variants[i];
        var defaultId = String(pg.catalog && pg.catalog.default || "");
        for (var j = 0; j < variants.length; j++)
            if (String(variants[j].id || "") === defaultId)
                return variants[j];
        return variants.length > 0 ? variants[0]
            : ({ id: "", name: "", description: "", preview: "", capabilities: [] });
    }
    function variantNames() {
        return pg.catalogVariants().map(function (entry) {
            return String(entry.name || "");
        });
    }
    function idForVariantName(name) {
        var variants = pg.catalogVariants();
        var requested = String(name || "");
        for (var i = 0; i < variants.length; i++)
            if (String(variants[i].name || "") === requested)
                return String(variants[i].id || "");
        return String(pg.draft.variant || "");
    }
    function activeCapabilities() {
        var capabilities = pg.variantEntry(pg.draft.variant).capabilities;
        return Array.isArray(capabilities) ? capabilities : [];
    }
    function supports(capability) {
        return pg.activeCapabilities().indexOf(capability) !== -1;
    }
    function same(a, b) { return String(a) === String(b); }
    function basename(p) { return ("" + p).replace(/^.*\//, ""); }

    readonly property int dirtyCount: {
        if (!pg.loaded)
            return 0;
        var n = 0;
        for (var i = 0; i < pg.keys.length; i++)
            if (!pg.same(pg.draft[pg.keys[i]], pg.committed[pg.keys[i]]))
                n++;
        return n;
    }
    readonly property bool dirty: pg.dirtyCount > 0

    function edit(k, v) {
        var d = pg.clone(pg.draft);
        d[k] = v;
        pg.draft = d;
    }
    function adopt() {
        var d = {}, c = {};
        for (var i = 0; i < pg.keys.length; i++) {
            var k = pg.keys[i];
            d[k] = cfgA[k];
            c[k] = cfgA[k];
        }
        pg.draft = d;
        pg.committed = c;
    }
    function adoptExternal() {
        var d = {}, c = {};
        for (var i = 0; i < pg.keys.length; i++) {
            var k = pg.keys[i];
            if (pg.same(pg.draft[k], pg.committed[k])) {
                d[k] = cfgA[k];
                c[k] = cfgA[k];
            } else {
                d[k] = pg.draft[k];
                c[k] = cfgA[k];
            }
        }
        pg.draft = d;
        pg.committed = c;
    }
    function save() {
        for (var i = 0; i < pg.keys.length; i++)
            cfgA[pg.keys[i]] = pg.draft[pg.keys[i]];
        cfg.writeAdapter();
        pg.committed = pg.clone(pg.draft);
    }
    function revert() { pg.draft = pg.clone(pg.committed); }
    function resetDefaults() { pg.draft = pg.clone(pg.factory); }

    function unitLabel(k) { return k === "C" ? "\u00b0C" : k === "F" ? "\u00b0F" : "Auto"; }
    function unitKey(l) { return l === "\u00b0C" ? "C" : l === "\u00b0F" ? "F" : "auto"; }
    function horizonModeLabel(k) { return k === "fixed" ? "Fixed" : k === "off" ? "Off" : "Palette"; }
    function horizonModeKey(l) { return l === "Fixed" ? "fixed" : l === "Off" ? "off" : "auto"; }


    FileView {
        id: catalogFile
        path: pg.launcherRoot + "/catalog.json"
        blockLoading: true
        printErrors: true
        onLoaded: pg.catalog = JSON.parse(text())
    }

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/launcher.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: { if (!pg.loaded) { pg.adopt(); pg.loaded = true; } else pg.adoptExternal(); }
        onLoadFailed: { if (!pg.loaded) { pg.adopt(); pg.loaded = true; } }

        JsonAdapter {
            id: cfgA
            property string variant: "hero"
            property real radius: 16
            property int bgBlur: 2
            property string weatherUnit: "auto"
            property string heroImage: ""
            property real heroStrength: 0.6
            property real heroPosX: 0.5
            property real heroPosY: 0.5
            property bool showWeather: true
            property bool showGreeting: true
            property int resultSettleMs: 360
            property string horizonMode: "auto"
            property string horizonColor: "#ffc777"
        }
    }


    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s6
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "\u529b"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("DESKTOP"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("App Launcher"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 760)
            text: I18n.tr("Tune the command palette you open with Super+Space: its corners, local frost, and the hero's greeting, weather and image. Nothing is written until you save.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s1
        kana: "ランチャー"
        index: "003"; label: I18n.tr("PALETTE")
    }

    Preview {
        id: preview
        anchors { left: parent.left; right: parent.right; top: head.bottom }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s5
        height: 226
        label: {
            var name = String(pg.variantEntry(pg.draft.variant).name || I18n.tr("Launcher"));
            return I18n.tr("%1 PREVIEW").arg(name.toUpperCase());
        }
        tag: variantPreview.item
            ? (variantPreview.item.implicitWidth + " × " + variantPreview.item.implicitHeight)
            : ""
        live: true

        Item {
            id: previewStage
            anchors.fill: parent
            clip: true

            Loader {
                id: variantPreview
                anchors.centerIn: parent
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0
                scale: item && item.implicitWidth > 0 && item.implicitHeight > 0
                    ? Math.min(0.72, Math.min(
                        (previewStage.width - 24) / item.implicitWidth,
                        (previewStage.height - 12) / item.implicitHeight))
                    : 1
                source: {
                    var file = String(pg.variantEntry(pg.draft.variant).preview || "");
                    return file.length > 0
                        ? "file://" + pg.launcherRoot + "/" + file : "";
                }
                onLoaded: {
                    item.settings = Qt.binding(function () { return pg.draft; });
                    item.editRequested.connect(function (key, value) {
                        pg.edit(key, value);
                    });
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors {
            left: parent.left; right: parent.right
            top: preview.bottom; bottom: bar.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
            topMargin: Tokens.s5; bottomMargin: Tokens.s4
        }
        contentWidth: width
        contentHeight: col.height + Tokens.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            width: flick.width - Tokens.s3
            spacing: Tokens.s5

            SettingCard {
                width: col.width
                title: I18n.tr("LAUNCHER")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Style")
                    desc: String(pg.variantEntry(pg.draft.variant).description || "")
                    def: String(pg.variantEntry(pg.committed.variant).name || "")
                    changed: !pg.same(pg.draft.variant, pg.committed.variant)
                    source: "launcher.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: pg.variantNames()
                        current: String(pg.variantEntry(pg.draft.variant).name || "")
                        onChose: name => pg.edit("variant", pg.idForVariantName(name))
                    }
                }
            }

            SettingCard {
                width: col.width
                title: I18n.tr("PALETTE")
                visible: pg.supports("shape") || pg.supports("background")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    visible: pg.supports("shape")
                    label: I18n.tr("Corner radius")
                    desc: I18n.tr("Rounds the palette window corners; inner cards follow 4 px tighter.")
                    unit: "px"
                    value: String(pg.draft.radius)
                    def: String(pg.committed.radius)
                    changed: !pg.same(pg.draft.radius, pg.committed.radius)
                    source: "launcher.json"
                    controlWidth: 58
                    Step {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        value: Number(pg.draft.radius) || 0
                        from: 0; to: 28
                        onModified: (v) => pg.edit("radius", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    visible: pg.supports("background")
                    divider: pg.supports("shape")
                    label: I18n.tr("Backdrop frost")
                    desc: I18n.tr("Blurs the frozen desktop visible through the result drawer. 0 keeps the drawer solid.")
                    unit: "px"
                    value: String(pg.draft.bgBlur)
                    def: String(pg.committed.bgBlur)
                    changed: !pg.same(pg.draft.bgBlur, pg.committed.bgBlur)
                    source: "launcher.json"
                    controlWidth: 58
                    Step {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        value: Number(pg.draft.bgBlur) || 0
                        from: 0; to: 30
                        onModified: (v) => pg.edit("bgBlur", v)
                    }
                }
            }

            SettingCard {
                width: col.width
                title: I18n.tr("RESULT MOTION")
                visible: pg.supports("results")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Type settle")
                    desc: I18n.tr("Waits for a pause before the finished result deck fades in. Higher values feel calmer; lower values respond sooner.")
                    unit: "ms"
                    value: String(pg.draft.resultSettleMs)
                    def: String(pg.committed.resultSettleMs)
                    changed: !pg.same(pg.draft.resultSettleMs, pg.committed.resultSettleMs)
                    source: "launcher.json"
                    controlWidth: 58
                    Step {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        value: Number(pg.draft.resultSettleMs) || 360
                        from: 120; to: 700
                        onModified: (v) => pg.edit("resultSettleMs", v)
                    }
                }
            }

            SettingCard {
                width: col.width
                title: I18n.tr("HERO")
                visible: pg.supports("hero")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Show greeting")
                    desc: I18n.tr("Time-of-day greeting above the hero clock.")
                    def: pg.committed.showGreeting ? I18n.tr("ON") : I18n.tr("OFF")
                    changed: !pg.same(pg.draft.showGreeting, pg.committed.showGreeting)
                    source: "launcher.json"
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.draft.showGreeting
                        onToggled: (v) => pg.edit("showGreeting", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Show weather")
                    desc: I18n.tr("Current conditions and temperature on the hero; off shows the date.")
                    def: pg.committed.showWeather ? I18n.tr("ON") : I18n.tr("OFF")
                    changed: !pg.same(pg.draft.showWeather, pg.committed.showWeather)
                    source: "launcher.json"
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.draft.showWeather
                        onToggled: (v) => pg.edit("showWeather", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    block: true
                    label: I18n.tr("Weather units")
                    desc: I18n.tr("Temperature scale on the hero; Auto follows your locale.")
                    def: I18n.tr(pg.unitLabel(pg.committed.weatherUnit))
                    changed: !pg.same(pg.draft.weatherUnit, pg.committed.weatherUnit)
                    source: "launcher.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["Auto", "\u00b0C", "\u00b0F"]
                        current: pg.unitLabel(pg.draft.weatherUnit)
                        onChose: (l) => pg.edit("weatherUnit", pg.unitKey(l))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    block: true
                    label: I18n.tr("Solar line")
                    desc: I18n.tr("The warm line under the clock. Palette follows the wallpaper, Fixed uses a colour you pick, Off hides it.")
                    def: I18n.tr(pg.horizonModeLabel(pg.committed.horizonMode))
                    changed: !pg.same(pg.draft.horizonMode, pg.committed.horizonMode)
                    source: "launcher.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["Palette", "Fixed", "Off"]
                        current: pg.horizonModeLabel(pg.draft.horizonMode)
                        onChose: (l) => pg.edit("horizonMode", pg.horizonModeKey(l))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    visible: pg.draft.horizonMode === "fixed"
                    divider: true
                    block: true
                    label: I18n.tr("Line colour")
                    desc: I18n.tr("Colour of the solar line and its marker when Solar line is set to Fixed.")
                    def: String(pg.committed.horizonColor)
                    changed: !pg.same(pg.draft.horizonColor, pg.committed.horizonColor)
                    source: "launcher.json"
                    ColorField {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(260, parent.width)
                        value: String(pg.draft.horizonColor)
                        onChosen: (v) => pg.edit("horizonColor", v)
                    }
                }
            }

            SettingCard {
                id: heroImgCard
                width: col.width
                title: I18n.tr("HERO IMAGE")
                visible: pg.supports("hero")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    footH: 32
                    label: I18n.tr("Image")
                    desc: I18n.tr("A landscape PNG or JPG, ideally 1600 px wide or more. It is cropped to a wide banner and dimmed; drag the preview to pick the part that shows.")
                    changed: !pg.same(pg.draft.heroImage, pg.committed.heroImage)
                    source: "launcher.json"
                    Item {
                        anchors.fill: parent
                        Text {
                            anchors.left: parent.left
                            anchors.right: heroActs.left
                            anchors.rightMargin: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideMiddle
                            text: (pg.draft.heroImage || "").length > 0 ? pg.basename(pg.draft.heroImage) : I18n.tr("Shipped art")
                            color: (pg.draft.heroImage || "").length > 0 ? Tokens.inkDim : Tokens.inkFaint
                            font.family: (pg.draft.heroImage || "").length > 0 ? Tokens.mono : Tokens.ui
                            font.pixelSize: (pg.draft.heroImage || "").length > 0 ? 12 : Tokens.fSmall
                        }
                        Row {
                            id: heroActs
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s2
                            Btn {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("CHANGE")
                                onAct: pg.openPicker()
                            }
                            Btn {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: (pg.draft.heroImage || "").length > 0
                                text: I18n.tr("USE SHIPPED ART")
                                onAct: pg.edit("heroImage", "")
                            }
                        }
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Strength")
                    desc: I18n.tr("How visible the hero image is; 0 hides it completely.")
                    unit: "%"
                    value: String(Math.round((Number(pg.draft.heroStrength) || 0) * 100))
                    def: String(Math.round((Number(pg.committed.heroStrength) || 0) * 100))
                    changed: !pg.same(pg.draft.heroStrength, pg.committed.heroStrength)
                    source: "launcher.json"
                    controlWidth: Math.min(240, Math.max(160, Math.round(heroImgCard.width * 0.34)))
                    Slid {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        value: Math.round((Number(pg.draft.heroStrength) || 0) * 100)
                        from: 0; to: 100
                        onModified: (v) => pg.edit("heroStrength", v / 100)
                    }
                }
            }
        }
    }

    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 60
        color: "transparent"
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1; color: Tokens.line
        }

        Marginalia {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            kana: "起動"
            index: "SUPER"; label: I18n.tr("SPACE")
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3

            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                antialiasing: false
                color: pg.dirty ? Tokens.ink : "transparent"
                border.width: pg.dirty ? 0 : Tokens.border
                border.color: Tokens.inkFaint

                SequentialAnimation on opacity {
                    running: pg.dirty
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    onStopped: dot.opacity = 1
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pg.dirty
                    ? (pg.dirtyCount === 1
                        ? I18n.tr("%1 CHANGE \u00b7 PREVIEWING \u00b7 NOT SAVED").arg(pg.dirtyCount)
                        : I18n.tr("%1 CHANGES \u00b7 PREVIEWING \u00b7 NOT SAVED").arg(pg.dirtyCount))
                    : I18n.tr("SAVED \u00b7 LIVE ON YOUR DESKTOP")
                color: pg.dirty ? Tokens.ink : Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3

            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("RESET TO DEFAULTS")
                onAct: pg.resetDefaults()
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 20; color: Tokens.line
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("REVERT")
                armed: pg.dirty
                onAct: pg.revert()
            }
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("SAVE")
                primary: true
                armed: pg.dirty
                onAct: pg.save()
            }
        }
    }

    property bool pickerOpen: false
    readonly property string home: Quickshell.env("HOME") || ""
    property url pickerFolder: "file://" + pg.home + "/Pictures"
    function openPicker() {
        pg.pickerFolder = "file://" + pg.home + "/Pictures";
        pg.pickerOpen = true;
    }
    function gotoDir(sub) { pg.pickerFolder = "file://" + pg.home + (sub.length ? "/" + sub : ""); }

    Item {
        id: pickerLayer
        anchors.fill: parent
        visible: pg.pickerOpen
        z: 100

        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: pg.pickerOpen = false }

        FolderListModel {
            id: fm
            folder: pg.pickerFolder
            showDirs: true
            showDirsFirst: true
            showDotAndDotDot: false
            showHidden: false
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.bmp"]
            sortField: FolderListModel.Name
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 900)
            height: Math.min(parent.height - 60, 560)
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineStrong
            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                id: ptitle
                anchors { left: parent.left; top: parent.top; margins: Tokens.s4 }
                text: I18n.tr("CHOOSE A HERO IMAGE")
                color: Tokens.ink; font.family: Tokens.ui
                font.pixelSize: 10; font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
            }
            Text {
                anchors.left: ptitle.left
                anchors.top: ptitle.bottom
                anchors.topMargin: Tokens.s1
                anchors.right: pclose.left
                anchors.rightMargin: Tokens.s3
                elide: Text.ElideLeft
                text: ("" + pg.pickerFolder).replace("file://", "").replace(pg.home, "~")
                color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: 11
            }
            IconBtn {
                id: pclose
                anchors { right: parent.right; top: parent.top; margins: Tokens.s3 }
                glyph: "\u2715"
                onAct: pg.pickerOpen = false
            }

            Row {
                id: pnav
                anchors { left: parent.left; right: parent.right; top: ptitle.bottom }
                anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4; anchors.topMargin: Tokens.s5
                spacing: Tokens.s2

                Btn { text: I18n.tr("\u2191 UP"); onAct: pg.pickerFolder = fm.parentFolder }
                Btn { text: I18n.tr("HOME"); onAct: pg.gotoDir("") }
                Btn { text: I18n.tr("PICTURES"); onAct: pg.gotoDir("Pictures") }
                Btn { text: I18n.tr("DOWNLOADS"); onAct: pg.gotoDir("Downloads") }
                Btn { text: I18n.tr("STORE"); onAct: pg.gotoDir("Pictures/ryoku-launchers") }
            }

            GridView {
                id: grid
                anchors {
                    left: parent.left; right: parent.right
                    top: pnav.bottom; bottom: pfoot.top
                    leftMargin: Tokens.s3; rightMargin: Tokens.s3
                    topMargin: Tokens.s3; bottomMargin: Tokens.s2
                }
                clip: true
                readonly property int cols: Math.max(3, Math.floor(width / 190))
                cellWidth: Math.floor(width / cols)
                cellHeight: Math.round(cellWidth * 0.72)
                cacheBuffer: 1200
                boundsBehavior: Flickable.StopAtBounds
                model: fm
                ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    id: tile
                    required property string fileName
                    required property url fileUrl
                    required property bool fileIsDir
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: Tokens.radius
                        color: tile.fileIsDir && th.hovered ? Tokens.bone : (th.hovered ? Tokens.tint5 : "transparent")
                        border.width: Tokens.border
                        border.color: th.hovered ? (tile.fileIsDir ? Tokens.bone : Tokens.ink) : Tokens.line
                        clip: true
                        Behavior on color { ColorAnimation { duration: Tokens.snap } }
                        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                        Column {
                            visible: tile.fileIsDir
                            anchors.centerIn: parent
                            width: parent.width - Tokens.s5
                            spacing: Tokens.s2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: I18n.tr("DIR")
                                color: th.hovered ? Tokens.inkOnBone : Tokens.inkMuted
                                font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                                font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: tile.fileName
                                color: th.hovered ? Tokens.inkOnBone : Tokens.inkDim
                                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            }
                        }

                        Image {
                            visible: !tile.fileIsDir
                            anchors.fill: parent
                            anchors.margins: 1
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(Math.ceil(parent.width * 1.4), Math.ceil(parent.height * 1.4))
                            source: tile.fileIsDir ? "" : tile.fileUrl
                        }

                        Rectangle {
                            visible: !tile.fileIsDir && th.hovered
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 20
                            color: Tokens.paperLift
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.s2
                                anchors.rightMargin: Tokens.s2
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                                text: tile.fileName
                                color: Tokens.inkDim; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                            }
                        }

                        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (tile.fileIsDir) {
                                    pg.pickerFolder = tile.fileUrl;
                                } else {
                                    pg.edit("heroImage", "" + tile.fileUrl);
                                    pg.pickerOpen = false;
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: grid
                visible: fm.status === FolderListModel.Ready && fm.count === 0
                text: I18n.tr("NO IMAGES OR FOLDERS HERE")
                color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 12; font.letterSpacing: 2
            }

            Item {
                id: pfoot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 52
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1; color: Tokens.lineSoft
                }
                Btn {
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.s4
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("CANCEL")
                    onAct: pg.pickerOpen = false
                }
            }
        }
    }
}
