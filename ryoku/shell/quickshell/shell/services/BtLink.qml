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


    // Getting a device onto the machine, end to end: pair if it is not paired,
    // trust it, connect it, and recover the one state that used to be a dead
    // end. Device1.Pair and Device1.Connect register no agent, so BlueZ has
    // nobody to answer its authorisation request with; every step here runs
    // through a bluetoothctl that brings one.
    //
    // Three things this fixes over calling Pair/Connect directly:
    //
    //   - A bond BlueZ holds but the device has forgotten is a dead end. Several
    //     failed attempts, or a pairing made under another OS on the same
    //     machine, leave keys on this side only: `pair` then returns
    //     AlreadyExists at once and `connect` fails at once, which is why the
    //     mouse in #144/#156 started failing FASTER after each try rather than
    //     differently. Nothing in the UI ever cleared it. When a connection
    //     will not come up on an existing bond, remove it and bond again from
    //     scratch, once.
    //   - A bond needs the device visible, and the popout's scan stops itself
    //     after 30 s, so a pair started from a stale list had nothing to talk
    //     to. Each pair attempt holds its own scan.
    //   - A HID device very often refuses the first connect straight after
    //     bonding and takes the second, so connect is retried rather than
    //     reported as a failure.
    //
    // The exit code carries what happened: 0 connected, 1 pairing failed, 2
    // paired but never connected, 3 no usable adapter. Its stdout is the reason
    // to show the user, and it is never filtered away to nothing: the keyword
    // pass picks the interesting line out of bluetoothctl's chatter, but a miss
    // falls through to the last real line of output instead of to silence,
    // which is what left every failure showing the same generic advice.
    function linkCommand(mac) {
        const m = String(mac || "");
        const script = `
mac="$1"

reason() {
    local out=$1 line
    line=$(grep -iE 'Failed|not available|no default controller|not ready|error|refused|timed out|Authentication|Protocol|Blocked|rfkill' <<<"$out" | tail -1)
    [ -n "$line" ] || line=$(grep -v '^[[:space:]]*$' <<<"$out" | tail -1)
    printf '%s\\n' "$line"
}

# every call carries an agent: without one BlueZ auto-rejects its own
# authorisation request and the step fails for no reason the user can see.
btc() { local t=$1; shift; bluetoothctl --agent NoInputNoOutput --timeout "$t" "$@" 2>&1; }

sout=$(bluetoothctl show 2>&1)
if grep -qiE 'No default controller available' <<<"$sout"; then
    printf '%s\\n' "No Bluetooth controller is available (is the adapter blocked by rfkill?)"
    exit 3
fi
if grep -qiE '^[[:space:]]*Powered:[[:space:]]*no' <<<"$sout"; then
    bluetoothctl power on >/dev/null 2>&1
fi

paired=0
grep -qiE '^[[:space:]]*Paired:[[:space:]]*yes' <<<"$(bluetoothctl info "$mac" 2>&1)" && paired=1

# hold a scan for the attempt: BlueZ will not bond with a device it cannot
# currently see, and the picker's own scan times out on its own.
do_pair() {
    bluetoothctl --timeout 25 scan on >/dev/null 2>&1 &
    local sc=$!
    sleep 2
    local out
    out=$(btc 25 pair "$mac")
    kill "$sc" 2>/dev/null
    wait "$sc" 2>/dev/null
    printf '%s\\n' "$out"
}
paired_ok() { grep -qiE 'Pairing successful|already[ -]?paired|Paired: yes|AlreadyExists' <<<"$1"; }

# a HID device commonly refuses the first connect after bonding.
connect_try() {
    local out i
    for i in 1 2 3; do
        out=$(btc 20 connect "$mac")
        if grep -qiE 'Connection successful|Connected: yes|already connected' <<<"$out"; then
            return 0
        fi
        sleep 2
    done
    printf '%s\\n' "$out"
    return 1
}

if [ "$paired" = 0 ]; then
    pout=$(do_pair)
    paired_ok "$pout" || { reason "$pout"; exit 1; }
fi
btc 10 trust "$mac" >/dev/null 2>&1
cout=$(connect_try) && exit 0

# The bond does not carry a connection. Clear it and bond again from scratch,
# once: this is the state no amount of retrying recovers from.
bluetoothctl remove "$mac" >/dev/null 2>&1
sleep 1
pout=$(do_pair)
paired_ok "$pout" || { reason "$pout"; exit 1; }
btc 10 trust "$mac" >/dev/null 2>&1
cout=$(connect_try) && exit 0
reason "$cout"
exit 2
`;
        return ["bash", "-c", script, "bash", m];
    }
}
