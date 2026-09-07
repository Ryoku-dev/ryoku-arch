pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import "../../shared/Singletons"
import Ryoku.Ui.Singletons

// Live Bluetooth bubbles for the palette: one compact card per CONNECTED
// device, floating detached under the launcher window, the Android quick-pair
// tile reduced to Ryoku's brutalist grammar. Device name up top, a big
// Material-style class glyph on the left (BlueZ classifies the device --
// headset, mouse, keyboard, pad, phone -- and the shipped Nerd Font embeds the
// Material Design Icons set, so the pictograms come from an asset pack we
// already ship), and the battery reading large in the corner when the device
// reports one. Corners are deliberately square. Nothing connected renders
// nothing at all: the cards only exist while a link is live. Purely a glance
// surface; pairing and toggling belong to the pill link and Hub Connections.
// Backed by Quickshell.Bluetooth, so cards appear, drop, and re-battery
// themselves live without polling.
Flow {
    id: root

    property real s: 1

    spacing: 8 * s
    visible: connected.length > 0

    readonly property var connected: {
        if (typeof Bluetooth === "undefined" || !Bluetooth || !Bluetooth.devices)
            return [];
        var vals = Bluetooth.devices.values, out = [];
        for (var i = 0; i < vals.length; i++)
            if (vals[i] && vals[i].connected)
                out.push(vals[i]);
        return out;
    }

    // BlueZ's freedesktop icon name -> a Material Design Icons glyph from the
    // shipped Nerd Font (nf-md-*, the Android pictogram set).
    function glyphFor(d) {
        var ic = (d && d.icon) ? String(d.icon) : "";
        if (ic.indexOf("headset") !== -1 || ic.indexOf("headphone") !== -1)
            return "\u{F02CB}";   // headphones
        if (ic.indexOf("mouse") !== -1) return "\u{F037D}";
        if (ic.indexOf("keyboard") !== -1) return "\u{F030C}";
        if (ic.indexOf("gaming") !== -1) return "\u{F0296}";   // gamepad
        if (ic.indexOf("phone") !== -1) return "\u{F011C}";    // cellphone
        if (ic.indexOf("watch") !== -1) return "\u{F0565}";
        if (ic.indexOf("audio") !== -1) return "\u{F04C3}";    // speaker
        if (ic.indexOf("computer") !== -1) return "\u{F0379}"; // monitor
        return "\u{F00AF}";                                    // bluetooth rune
    }

    // Generated device portraits share the launcher art catalogue; missing art
    // falls back to the glyph.
    function artFor(d) {
        var ic = (d && d.icon) ? String(d.icon) : "";
        var cat = "";
        if (ic.indexOf("headset") !== -1 || ic.indexOf("headphone") !== -1)
            cat = "headphones";
        else if (ic.indexOf("mouse") !== -1) cat = "mouse";
        else if (ic.indexOf("keyboard") !== -1) cat = "keyboard";
        else if (ic.indexOf("gaming") !== -1) cat = "gamepad";
        else if (ic.indexOf("phone") !== -1) cat = "phone";
        else if (ic.indexOf("watch") !== -1) cat = "watch";
        else if (ic.indexOf("audio") !== -1) cat = "speaker";
        else if (ic.indexOf("computer") !== -1) cat = "computer";
        else cat = "generic";
        return Qt.resolvedUrl("../../shared/art/bt/" + cat + ".png");
    }

    // BlueZ reports battery as 0..1 or 0..100 depending on the transport.
    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    Repeater {
        model: root.connected

        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property int battery: root.batteryLevel(modelData)

            width: 172 * root.s
            height: 124 * root.s
            color: Theme.cardTop
            border.width: 1
            border.color: Theme.border
            clip: true

            // the device portrait fills the card like the rest card's hero
            // art; a scrim keeps the name and battery readable over it.
            Image {
                id: portrait
                anchors.fill: parent
                anchors.margins: 1
                source: root.artFor(card.modelData)
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Math.round(344 * root.s)
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: portrait.visible
                color: "#000000"
                opacity: 0.22
            }

            // swallow clicks so tapping the bubble doesn't hit the click-out
            // scrim behind it and close the palette.
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            // lit top edge, the recessed-card cue shared with the rest card.
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                height: 1
                color: Theme.sheen
            }

            Text {
                anchors.top: parent.top
                anchors.topMargin: 12 * root.s
                anchors.left: parent.left
                anchors.leftMargin: 13 * root.s
                anchors.right: parent.right
                anchors.rightMargin: 13 * root.s
                text: card.modelData
                    ? (card.modelData.deviceName || card.modelData.name || card.modelData.address || I18n.tr("Unknown"))
                    : I18n.tr("Unknown")
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // the class pictogram, big like a device portrait; stands in
            // whenever the class has no shipped art.
            Text {
                visible: !portrait.visible
                anchors.left: parent.left
                anchors.leftMargin: 13 * root.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8 * root.s
                text: root.glyphFor(card.modelData)
                color: Theme.vermLit
                font.family: Theme.mono
                font.pixelSize: 44 * root.s
            }

            // the battery reading, big in the corner like a dashboard dial.
            Text {
                visible: card.battery >= 0
                anchors.right: parent.right
                anchors.rightMargin: 13 * root.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8 * root.s
                text: card.battery + "%"
                color: card.battery <= 20 ? Theme.verm : Theme.vermLit
                font.family: Theme.mono
                font.pixelSize: 26 * root.s
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }

            // no battery channel: a quiet link mark holds the corner instead.
            Text {
                visible: card.battery < 0
                anchors.right: parent.right
                anchors.rightMargin: 13 * root.s
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12 * root.s
                text: I18n.tr("connected")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Medium
            }
        }
    }
}
