pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."

// Appearance > Lighting: every RGB device on this machine, each showing only the
// controls it says it has. Nothing is scanned until lighting is switched on and
// nothing is written until a device is handed over, so a keyboard driven by its
// own software can sit here untouched. Effects are listed in two groups because
// they differ: the ones Ryoku paints work whatever the firmware ignores, the
// device's own keep running with Ryoku closed.
//
// The list is keyed so a reply refreshes values without rebuilding cards, and one
// command runs at a time: both keep the page still under the pointer.
Item {
    id: lt

    // devices by key, and the key order the list draws. `keys` changes only when
    // a device appears or goes away, which is what keeps the cards alive.
    property var byKey: ({})
    property var keys: []

    property bool available: true
    property bool lightingOn: false
    property bool busy: false
    property bool scanned: false
    property string error: ""
    property string accent: "#F25623"

    Component.onCompleted: lt.run(["state"])

    function applyReport(text) {
        var parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            lt.error = I18n.tr("Lighting control did not answer.");
            return;
        }
        if (!parsed)
            return;
        lt.available = parsed.available !== false;
        lt.lightingOn = parsed.enabled === true;
        lt.accent = parsed.accent || lt.accent;
        lt.error = parsed.error || "";

        var list = parsed.devices || [];
        var map = {};
        var ks = [];
        for (var i = 0; i < list.length; i++) {
            map[list[i].key] = list[i];
            ks.push(list[i].key);
        }
        lt.byKey = map;
        if (ks.join("\u0000") !== lt.keys.join("\u0000"))
            lt.keys = ks;
    }

    // ── one command at a time ───────────────────────────────────────────────
    property var queue: []
    function run(args) {
        lt.queue = lt.queue.concat([args]);
        lt.pump();
    }
    function pump() {
        if (cmdProc.running || lt.queue.length === 0)
            return;
        var next = lt.queue[0];
        lt.queue = lt.queue.slice(1);
        if (next[0] === "scan" || next[0] === "enable")
            lt.busy = true;
        cmdProc.command = ["ryoku-hub", "lighting"].concat(next);
        cmdProc.running = true;
    }
    Process {
        id: cmdProc
        stdout: StdioCollector { onStreamFinished: lt.applyReport(this.text) }
        onExited: (code, status) => {
            lt.busy = false;
            Qt.callLater(lt.pump);
            // lighting already on when the page opened: show what is actually
            // connected, since the user opted in long ago and expects to see it.
            if (lt.lightingOn && !lt.scanned) {
                lt.scanned = true;
                lt.scan();
            }
        }
    }

    function scan() { lt.busy = true; lt.run(["scan"]); }
    function setEnabled(on) {
        lt.error = "";
        lt.busy = true;
        lt.scanned = true;
        lt.run([on ? "enable" : "disable"]);
    }
    function act(cmd, key) { lt.error = ""; lt.run([cmd, key]); }

    // mirror a change locally first, so a switch or a chip answers the click
    // rather than the round trip. The reply then carries the same values.
    function mirror(key, obj) {
        var map = Object.assign({}, lt.byKey);
        map[key] = Object.assign({}, map[key] || {}, obj);
        lt.byKey = map;
    }
    function patch(key, obj) {
        lt.error = "";
        lt.mirror(key, obj);
        lt.run(["set", key, JSON.stringify(obj)]);
    }

    // a drag writes once it settles: a slider would otherwise send a device
    // write per pixel.
    property string pendingKey: ""
    property var pendingPatch: ({})
    function flushPending() {
        if (lt.pendingKey === "")
            return;
        var key = lt.pendingKey;
        var obj = lt.pendingPatch;
        lt.pendingKey = "";
        lt.pendingPatch = ({});
        lt.run(["set", key, JSON.stringify(obj)]);
    }
    function patchLater(key, obj) {
        if (lt.pendingKey !== "" && lt.pendingKey !== key)
            lt.flushPending();
        lt.pendingKey = key;
        lt.pendingPatch = Object.assign({}, lt.pendingPatch, obj);
        lt.mirror(key, obj);
        flush.restart();
    }
    Timer { id: flush; interval: 260; onTriggered: lt.flushPending() }

    // the mode the device is set to, as the device described it, so only the
    // knobs it actually has get drawn.
    function modeOf(d) {
        var want = d.mode || d.active || "";
        var modes = d.modes || [];
        for (var i = 0; i < modes.length; i++)
            if (modes[i].name === want)
                return modes[i];
        return null;
    }
    function fxOf(d) {
        var id = d.effect || "";
        var list = d.effects || [];
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id)
                return list[i];
        return null;
    }
    function colourSlots(m) {
        if (m === null)
            return 0;
        return m.colors > 0 ? Math.min(m.colors, 4) : (m.perLed ? 1 : 0);
    }

    // a chip: one effect, filled when it is the one running.
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal picked()

        implicitWidth: chipLabel.width + Tokens.s4
        implicitHeight: 26
        radius: Tokens.radius
        color: chip.on ? Tokens.bone : (ch.hovered ? Tokens.tint10 : "transparent")
        border.width: Tokens.border
        border.color: chip.on ? Tokens.bone : (ch.hovered ? Tokens.lineStrong : Tokens.line)
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: I18n.tr(chip.label)
            color: chip.on ? Tokens.inkOnBone : Tokens.ink
            font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
            font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
        }
        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.picked() }
    }

    // ── one device: its identity, then the controls it says it has ───────────
    component DeviceCard: SettingCard {
        id: card
        required property string devKey

        readonly property var dev: lt.byKey[card.devKey] || ({})
        readonly property bool managed: card.dev.managed === true
        readonly property bool online: card.dev.online === true
        readonly property bool fixed: card.dev.source === "fixed"
        readonly property var zones: card.dev.zones || []

        // what is driving the device: an effect Ryoku paints, or one of its own.
        readonly property bool painted: (card.dev.effect || "") !== ""
        readonly property var fx: lt.fxOf(card.dev)
        readonly property var mode: lt.modeOf(card.dev)

        // the controls to draw, from whichever of the two is running.
        readonly property int slots: card.painted ? 1 : lt.colourSlots(card.mode)
        readonly property bool hasBrightness: card.painted || (card.mode !== null && card.mode.brightness === true)
        readonly property bool hasSpeed: card.painted
                                        ? (card.fx !== null && card.fx.speed === true)
                                        : (card.mode !== null && card.mode.speed === true)
        readonly property var directions: (!card.painted && card.mode !== null) ? (card.mode.directions || []) : []
        readonly property bool canSave: !card.painted && card.mode !== null && card.mode.canSave === true
        readonly property bool perZone: !card.painted && card.zones.length > 1
                                        && card.mode !== null && card.mode.perLed === true
        readonly property int briShown: card.dev.brightness >= 0 ? card.dev.brightness
                                        : (card.painted ? 100 : (card.mode ? card.mode.briPct : 100))
        readonly property int speedShown: card.dev.speed >= 0 ? card.dev.speed
                                          : (card.painted ? 50 : (card.mode ? card.mode.speedPct : 50))
        readonly property int colWidth: Math.min(240, Math.max(160, Math.round(card.width * 0.34)))

        title: (card.dev.name || I18n.tr("DEVICE")).toUpperCase()

        Text {
            width: parent.width
            leftPadding: Tokens.s4; rightPadding: Tokens.s4
            topPadding: Tokens.s3; bottomPadding: Tokens.s2
            text: [card.dev.type || "", card.dev.vendor || "", card.dev.location || ""].filter(s => s !== "").join("  ·  ")
                  + (card.online ? "" : "  ·  " + I18n.tr("not connected"))
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
            elide: Text.ElideRight
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            divider: true
            label: I18n.tr("Ryoku controls this device")
            desc: card.managed
                  ? I18n.tr("Turning this off puts the device back to %1, the effect it was on before Ryoku touched it.").arg(card.dev.restore || I18n.tr("its own effect"))
                  : I18n.tr("Left off, Ryoku never writes to it: its own software, onboard profile or hardware switch stays in charge.")
            controlWidth: 54
            Sw {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                on: card.managed
                opacity: card.online ? 1 : 0.4
                onToggled: (v) => { if (card.online) lt.patch(card.devKey, { "managed": v }); }
            }
        }

        // Ryoku's own effects: drawn frame by frame, so they work even where the
        // firmware ignores half its own effect list.
        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && (card.dev.effects || []).length > 0
            divider: true
            block: true
            label: I18n.tr("Ryoku effects")
            desc: I18n.tr("Painted by Ryoku on this device's per-key mode, so they work whatever its firmware supports. They need Ryoku running.")
            Flow {
                anchors.left: parent.left; anchors.right: parent.right
                spacing: Tokens.s2
                Repeater {
                    model: card.dev.effects || []
                    delegate: Chip {
                        required property var modelData
                        label: I18n.tr(modelData.label)
                        on: card.dev.effect === modelData.id
                        onPicked: lt.patch(card.devKey, { "effect": modelData.id })
                    }
                }
            }
        }

        // the device's own effects, exactly as it reports them.
        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && (card.dev.modes || []).length > 0
            divider: true
            block: true
            label: I18n.tr("This device's effects")
            desc: I18n.tr("Run by the device itself, so they keep going with Ryoku closed. A device does not always implement every effect it lists; if one does nothing, that is its firmware, and a Ryoku effect above will work instead.")
            Flow {
                anchors.left: parent.left; anchors.right: parent.right
                spacing: Tokens.s2
                Repeater {
                    model: card.dev.modes || []
                    delegate: Chip {
                        required property var modelData
                        label: modelData.name
                        on: !card.painted && (card.dev.mode || card.dev.active) === modelData.name
                        onPicked: lt.patch(card.devKey, { "mode": modelData.name })
                    }
                }
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.slots > 0
            divider: true
            label: I18n.tr("Colour")
            desc: card.fixed
                  ? I18n.tr("A colour of your own, kept through wallpaper changes.")
                  : I18n.tr("Follows the desktop accent, so the device retints with the wallpaper. Now: %1").arg(lt.accent)
            controlWidth: 130
            Seg {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                options: ["WALLPAPER", "FIXED"]
                current: card.fixed ? "FIXED" : "WALLPAPER"
                onChose: (k) => lt.patch(card.devKey, { "source": k === "FIXED" ? "fixed" : "accent" })
            }
        }

        // one picker per colour the effect takes; a device with several zones on
        // a per-key mode of its own gets one per zone instead.
        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.fixed && card.slots > 0 && !card.perZone
            divider: true
            footH: 34 * card.slots + Tokens.s2 * Math.max(0, card.slots - 1)
            label: card.slots > 1 ? I18n.tr("Colours") : I18n.tr("Pick a colour")
            Column {
                id: colourCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.s2
                Repeater {
                    model: card.slots
                    delegate: ColorField {
                        required property int index
                        width: Math.min(260, colourCol.width)
                        value: (card.dev.colors || [])[index] || lt.accent
                        onChosen: (hex) => {
                            var cols = (card.dev.colors || []).slice();
                            while (cols.length < card.slots)
                                cols.push(lt.accent);
                            cols[index] = hex;
                            lt.patch(card.devKey, { "colors": cols });
                        }
                    }
                }
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.fixed && card.perZone
            divider: true
            footH: 34 * card.zones.length + Tokens.s2 * Math.max(0, card.zones.length - 1)
            label: I18n.tr("Zone colours")
            desc: I18n.tr("This device lights in parts; each one takes its own colour.")
            Column {
                id: zoneCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.s2
                Repeater {
                    model: card.zones
                    delegate: Row {
                        id: zoneRow
                        required property var modelData
                        spacing: Tokens.s3
                        Text {
                            width: 90
                            anchors.verticalCenter: parent.verticalCenter
                            text: zoneRow.modelData.name
                            color: Tokens.inkMuted
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            elide: Text.ElideRight
                        }
                        ColorField {
                            width: Math.min(200, Math.max(120, zoneCol.width - 110))
                            value: (card.dev.zoneColors || {})[zoneRow.modelData.name] || (card.dev.colors || [])[0] || lt.accent
                            onChosen: (hex) => {
                                var zc = Object.assign({}, card.dev.zoneColors || {});
                                zc[zoneRow.modelData.name] = hex;
                                lt.patch(card.devKey, { "zoneColors": zc });
                            }
                        }
                    }
                }
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.hasBrightness
            divider: true
            label: I18n.tr("Brightness"); unit: "%"
            desc: card.painted
                  ? I18n.tr("Dims the effect Ryoku draws.")
                  : I18n.tr("Scaled into the steps this device offers, not a number it has to fake.")
            value: String(card.briShown)
            controlWidth: card.colWidth
            Slid {
                anchors.fill: parent
                from: 0; to: 100
                value: card.briShown
                onModified: (v) => lt.patchLater(card.devKey, { "brightness": Math.round(v) })
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.hasSpeed
            divider: true
            label: I18n.tr("Speed"); unit: "%"
            desc: card.painted
                  ? I18n.tr("How fast Ryoku moves the effect.")
                  : I18n.tr("How fast the device runs the effect on its own.")
            value: String(card.speedShown)
            controlWidth: card.colWidth
            Slid {
                anchors.fill: parent
                from: 0; to: 100
                value: card.speedShown
                onModified: (v) => lt.patchLater(card.devKey, { "speed": Math.round(v) })
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed && card.directions.length > 0
            divider: true
            block: true
            label: I18n.tr("Direction")
            Seg {
                anchors.left: parent.left
                options: card.directions.map(d => d.toUpperCase())
                current: (card.dev.direction || "").toUpperCase()
                onChose: (k) => lt.patch(card.devKey, { "direction": k.charAt(0) + k.slice(1).toLowerCase() })
            }
        }

        SettingRow {
            anchors.left: parent.left; anchors.right: parent.right
            visible: card.managed
            divider: true
            footH: 32
            label: I18n.tr("This device's memory")
            desc: card.painted
                  ? I18n.tr("A Ryoku effect is drawn live, so there is nothing to store in the device. One of its own effects can be saved, if it offers that.")
                  : (card.canSave
                     ? I18n.tr("Store this look in the device so it holds with Ryoku closed. It replaces what is in the device's active profile slot.")
                     : I18n.tr("This device does not offer storing a look in its own memory, so Ryoku puts it back at every login instead."))
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: Tokens.s3
                Btn {
                    text: I18n.tr("SAVE TO DEVICE")
                    visible: card.canSave
                    armed: card.online
                    onAct: lt.act("save", card.devKey)
                }
                Btn {
                    text: I18n.tr("HAND BACK")
                    onAct: lt.act("release", card.devKey)
                }
            }
        }
    }

    // ── the tab itself ──────────────────────────────────────────────────────
    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height + Tokens.s5
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            width: view.width - Tokens.s3
            spacing: Tokens.s5

            SettingCard {
                width: col.width
                title: I18n.tr("DEVICE LIGHTING")

                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s2
                    text: I18n.tr("Keyboards, mice and other RGB hardware, through OpenRGB and native laptop providers. While this is off Ryoku never looks for a device and never writes to one, so hardware driven by its own software or a switch on the board is left alone. Turn it on and hand over the devices you want Ryoku to light, one at a time.")
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; wrapMode: Text.WordWrap
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Let Ryoku control lighting")
                    desc: !lt.available
                          ? I18n.tr("No supported lighting provider is installed, so no device can be reached.")
                          : I18n.tr("Your picks are kept in ~/.config/ryoku/lighting.json: an update, a shell restart or a reboot leaves them exactly as they are.")
                    controlWidth: 54
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: lt.lightingOn
                        opacity: lt.available ? 1 : 0.4
                        onToggled: (v) => { if (lt.available) lt.setEnabled(v); }
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    visible: lt.lightingOn
                    divider: true
                    footH: 32
                    label: I18n.tr("Connected devices")
                    desc: lt.busy
                          ? I18n.tr("Asking the lighting providers what is connected. The first scan can take a few seconds.")
                          : I18n.tr("%1 found. Rescan after plugging something in.").arg(lt.keys.filter(k => (lt.byKey[k] || {}).online === true).length)
                    Btn {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: lt.busy ? I18n.tr("SCANNING") : I18n.tr("RESCAN DEVICES")
                        armed: !lt.busy
                        onAct: lt.scan()
                    }
                }
            }

            Text {
                width: Math.min(col.width, 620)
                visible: lt.error !== ""
                text: lt.error
                color: Tokens.ink
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: lt.lightingOn ? lt.keys : []
                delegate: DeviceCard {
                    required property string modelData
                    width: col.width
                    devKey: modelData
                }
            }

            Text {
                width: Math.min(col.width, 620)
                visible: lt.lightingOn && lt.keys.length === 0 && !lt.busy
                text: I18n.tr("No lighting device answered. OpenRGB reaches USB keyboards, mice and headsets; supported ASUS laptops use asusd for their built-in Aura controller. Motherboard and memory lighting still needs the i2c-dev module loaded, which Ryoku leaves to you.")
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                width: Math.min(col.width, 620)
                visible: lt.lightingOn
                text: I18n.tr("Handing a device to Ryoku lets its provider talk to it. Hardware that keeps profiles in its own memory can be left showing Ryoku's look after you hand it back; Ryoku restores the effect it found, but only the device's own software can rebuild a profile you overwrote with Save to device.")
                color: Tokens.inkFaint
                font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                wrapMode: Text.WordWrap
            }
        }
    }
}
