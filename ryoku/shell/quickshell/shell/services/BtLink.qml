pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Ryoku.Ui.Singletons

// Bluetooth link state the popout reads but that must outlive it: a popout is a
// Loader that unmounts on close, so a "connected for 2h" duration cannot live
// there. This singleton is always resident, watches every device's connected
// edge, and stamps the moment each link came up, so the duration is real no
// matter when the popout opens. It also owns the shared device presentation
// helpers (class glyph, battery normalisation, display name) so the hero, the
// chips and the detail panel read one source instead of three copies.
Singleton {
    id: root

    // { address: epochMs } when the link came up. Reassigned wholesale on every
    // change so bindings that read it re-evaluate.
    property var since: ({})

    // A 1 Hz clock, live only while a popout watches, so a resting shell never
    // ticks. durationFor() reads it so "connected for" counts up on screen.
    property int watchers: 0
    property double nowMs: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.watchers > 0
        onTriggered: root.nowMs = Date.now()
    }
    function watch(on) { root.watchers = Math.max(0, root.watchers + (on ? 1 : -1)); if (on) root.nowMs = Date.now(); }

    function stamp(addr, on) {
        if (!addr)
            return;
        const next = Object.assign({}, root.since);
        if (on) {
            if (next[addr] === undefined) next[addr] = Date.now();
        } else {
            delete next[addr];
        }
        root.since = next;
    }

    // ms this device has been connected, or -1 if not tracked.
    function durationFor(addr) {
        if (!addr || root.since[addr] === undefined)
            return -1;
        return Math.max(0, root.nowMs - root.since[addr]);
    }
    // "2h 14m" / "6m" / "just now" from a duration in ms.
    function durationText(ms) {
        if (ms < 0)
            return "";
        const s = Math.floor(ms / 1000);
        if (s < 45)
            return I18n.tr("just now");
        const m = Math.floor(s / 60);
        if (m < 60)
            return I18n.tr("%1m").arg(m);
        const h = Math.floor(m / 60);
        return I18n.tr("%1h %2m").arg(h).arg(m % 60);
    }

    // Stamp every device's connected edge, and any device that is already up when
    // the shell starts (approximate, but the only honest value available).
    Instantiator {
        model: Bluetooth.devices
        delegate: QtObject {
            required property var modelData
            readonly property bool conn: modelData ? modelData.connected : false
            onConnChanged: root.stamp(modelData ? modelData.address : "", conn)
            Component.onCompleted: if (conn) root.stamp(modelData.address, true)
        }
    }

    // --- shared presentation --------------------------------------------------

    // BlueZ freedesktop icon hint -> a GlyphIcon name (the shell's baked vector
    // set), falling back to the plain bluetooth rune.
    function glyphFor(d) {
        const ic = (d && d.icon ? String(d.icon) : "").toLowerCase();
        if (ic.indexOf("headset") >= 0 || ic.indexOf("headphone") >= 0) return "headphones";
        if (ic.indexOf("mouse") >= 0) return "mouse";
        if (ic.indexOf("keyboard") >= 0) return "keyboard";
        if (ic.indexOf("gaming") >= 0 || ic.indexOf("joypad") >= 0) return "gamepad";
        if (ic.indexOf("phone") >= 0) return "phone";
        if (ic.indexOf("watch") >= 0) return "watch";
        if (ic.indexOf("audio") >= 0 || ic.indexOf("speaker") >= 0) return "speaker";
        if (ic.indexOf("computer") >= 0 || ic.indexOf("laptop") >= 0) return "monitor";
        if (ic.indexOf("input") >= 0) return "keyboard";
        return "bluetooth";
    }
    function typeLabel(d) {
        const ic = (d && d.icon ? String(d.icon) : "").toLowerCase();
        if (ic.indexOf("headset") >= 0 || ic.indexOf("headphone") >= 0) return I18n.tr("Headphones");
        if (ic.indexOf("mouse") >= 0) return I18n.tr("Mouse");
        if (ic.indexOf("keyboard") >= 0) return I18n.tr("Keyboard");
        if (ic.indexOf("gaming") >= 0 || ic.indexOf("joypad") >= 0) return I18n.tr("Controller");
        if (ic.indexOf("phone") >= 0) return I18n.tr("Phone");
        if (ic.indexOf("watch") >= 0) return I18n.tr("Watch");
        if (ic.indexOf("audio") >= 0 || ic.indexOf("speaker") >= 0) return I18n.tr("Speaker");
        if (ic.indexOf("computer") >= 0 || ic.indexOf("laptop") >= 0) return I18n.tr("Computer");
        return I18n.tr("Device");
    }

    // BlueZ reports battery as 0..1 or 0..100 depending on the transport.
    function batteryLevel(d) {
        if (!d || !d.batteryAvailable || d.battery === undefined || d.battery === null)
            return -1;
        let b = d.battery;
        if (b <= 0)
            return -1;
        if (b <= 1)
            b = b * 100;
        return Math.round(b);
    }

    function label(d) {
        if (!d)
            return I18n.tr("Unknown");
        return (d.name && d.name.length) ? d.name
            : (d.deviceName && d.deviceName.length) ? d.deviceName
            : (d.address || I18n.tr("Unknown"));
    }


    // Device1.Pair registers no agent, so BlueZ cannot authorise a bond; this
    // bluetoothctl brings its own for the call. Its exit code is unreliable,
    // so success is read from the output. Exit 0 paired+connected, 1 pair
    // failed, 2 connect failed, 3 no usable adapter.
    //
    // The failure line is never filtered away. Matching a keyword list first
    // and printing nothing when nothing matched is how a real cause ("No
    // default controller available", an org.bluez.Error the list never named)
    // became a blank string, and the popout then showed its own generic
    // "put the device in pairing mode" text for every failure. The keyword
    // pass still runs, because it picks the one interesting line out of
    // bluetoothctl's chatter, but its miss falls through to the last non-empty
    // line of real output instead of to silence.
    function pairCommand(mac) {
        const m = String(mac || "");
        const script = `
mac="$1"
# the interesting line if one matches, else whatever the tool actually said.
reason() {
    local out=$1 line
    line=$(grep -iE 'Failed|not available|no default controller|not ready|error|refused|timed out|Authentication|Protocol|Blocked|rfkill' <<<"$out" | tail -1)
    [ -n "$line" ] || line=$(grep -v '^[[:space:]]*$' <<<"$out" | tail -1)
    printf '%s\\n' "$line"
}
# An unpowered or absent controller fails every pair instantly, which reads as
# "it broke faster than before". Name it instead of blaming the device.
sout=$(bluetoothctl show 2>&1)
if grep -qiE 'No default controller available' <<<"$sout"; then
    printf '%s\\n' "No Bluetooth controller is available (is the adapter blocked by rfkill?)"
    exit 3
fi
if grep -qiE '^[[:space:]]*Powered:[[:space:]]*no' <<<"$sout"; then
    bluetoothctl power on >/dev/null 2>&1
fi
pout=$(bluetoothctl --agent NoInputNoOutput --timeout 25 pair "$mac" 2>&1)
if grep -qiE 'Pairing successful|already[ -]?paired|Paired: yes|AlreadyExists' <<<"$pout"; then
    bluetoothctl trust "$mac" >/dev/null 2>&1
    cout=$(bluetoothctl --timeout 20 connect "$mac" 2>&1)
    if grep -qiE 'Connection successful|Connected: yes|already connected' <<<"$cout"; then
        exit 0
    fi
    reason "$cout"
    exit 2
fi
reason "$pout"
exit 1
`;
        return ["bash", "-c", script, "bash", m];
    }
}
