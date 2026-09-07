pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../.." as Pill
import shell.services
import "../../../../../components"
import ".." as Menus
import Ryoku.Ui.Singletons

Item {
    id: root

    property real s: 1
    property bool open: false
    property var navigate: null
    property var closePanel: null

    function awakeFor() {
        const since = Flags.keepAwakeSince;
        if (!since || since <= 0)
            return "";
        const mins = Math.floor((Date.now() - since) / 60000);
        if (mins < 1)
            return "";
        if (mins < 60)
            return " " + I18n.tr("for %1m").arg(mins);
        if (mins < 1440)
            return " " + I18n.tr("for %1h").arg(Math.floor(mins / 60));
        return " " + I18n.tr("for %1d").arg(Math.floor(mins / 1440));
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: root.open
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        height: headerColumn.implicitHeight

        Column {
            id: headerColumn
            width: parent.width
            spacing: 4

            Item {
                width: parent.width
                height: 44

                Text {
                    anchors.left: parent.left
                    anchors.right: sessionRow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                    font.family: Theme.fontPrimary
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Row {
                    id: sessionRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Menus.QsIconButton {
                        icon: "logout"
                        tip: I18n.tr("Log out")
                        tipBelow: true
                        onClicked: Hyprland.dispatch("hl.dsp.exit()")
                    }
                    Menus.QsIconButton {
                        icon: "lock"
                        tip: I18n.tr("Lock")
                        tipBelow: true
                        onClicked: {
                            Quickshell.execDetached(["ryoku-shell", "lock"]);
                            if (root.closePanel)
                                root.closePanel();
                        }
                    }
                    Menus.QsHoldButton {
                        icon: "restart_alt"
                        tip: I18n.tr("Click to reboot")
                        tipBelow: true
                        tipAlign: "right"
                        onActivated: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                    Menus.QsHoldButton {
                        icon: "power_settings_new"
                        tip: I18n.tr("Click to shut down")
                        tipBelow: true
                        tipAlign: "right"
                        onActivated: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }

            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.right: Battery.present ? batteryPill.left : parent.right
                    anchors.rightMargin: Battery.present ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.locale().toString(clock.date, "dddd") + ", " + Qt.formatDate(clock.date, "MMM d, yyyy")
                    color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurfaceVariant, 3.0)
                    font.family: Theme.fontPrimary
                    font.pixelSize: Theme.fontSm
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: batteryPill
                    visible: Battery.present
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: batteryRow.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.25)

                    Row {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 13
                            text: Battery.charging ? "bolt" : "battery_full"
                            color: Theme.inkOn(Theme.effectiveSurface, Battery.charging ? Theme.primary : Theme.onSurfaceVariant, 3.0)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Battery.pct + "%"
                            color: Theme.inkOn(Theme.effectiveSurface, Theme.onSurface)
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 2
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // Surface switch: sets which panel the bar's brand logo opens -- this
            // Super+Esc quick settings, or the bar-logo QS Bar Settings. The lit
            // segment is the current target; picking the other retargets the logo.
            Menus.QsSeg {
                width: parent.width
                options: [{ id: "studio", label: I18n.tr("QS BAR SETTINGS") }, { id: "quick", label: I18n.tr("QUICK SETTINGS") }]
                current: Config.launcherTarget === "quick" ? "quick" : "studio"
                onChose: (id) => Config.setLauncherTarget(id)
            }
        }
    }

    Flickable {
        id: homeFlick
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.bottom: powerDock.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        contentWidth: width
        contentHeight: controls.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: controls
            width: parent.width
            spacing: 12

            Menus.QsSection { width: parent.width; label: I18n.tr("Connect") }
            Grid {
                id: tileGrid
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                readonly property real tileWidth: (width - columnSpacing) / 2

                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: Network.kind === "ethernet" ? "lan" : "wifi"
                    label: I18n.tr("Wi-Fi")
                    sub: !Toggles.wifiOn ? I18n.tr("Off") : Network.activeSsid !== "" ? Network.activeSsid : I18n.tr("On")
                    on: Toggles.wifiOn
                    hasPage: true
                    pageTip: I18n.tr("Wi-Fi networks")
                    onToggled: Toggles.toggleWifi()
                    onPageRequested: if (root.navigate) root.navigate("network")
                }
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "bluetooth"
                    label: I18n.tr("Bluetooth")
                    sub: Toggles.btOn ? I18n.tr("On") : I18n.tr("Off")
                    on: Toggles.btOn
                    hasPage: true
                    pageTip: I18n.tr("Bluetooth devices")
                    onToggled: Toggles.toggleBt()
                    onPageRequested: if (root.navigate) root.navigate("bluetooth")
                }
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "flight"
                    label: I18n.tr("Airplane")
                    sub: Toggles.wifiOn ? I18n.tr("Off") : I18n.tr("On")
                    on: !Toggles.wifiOn
                    onToggled: Toggles.toggleWifi()
                }
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "bedtime"
                    label: I18n.tr("Night light")
                    sub: Toggles.nightOn ? I18n.tr("On") : I18n.tr("Off")
                    on: Toggles.nightOn
                    onToggled: Toggles.toggleNight()
                }
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "coffee"
                    label: I18n.tr("Keep awake")
                    sub: Toggles.keepAwake ? I18n.tr("On") + root.awakeFor() : I18n.tr("Off")
                    on: Toggles.keepAwake
                    onToggled: Toggles.toggleCaffeine()
                }
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "do_not_disturb_on"
                    label: I18n.tr("Do not disturb")
                    sub: Toggles.dnd ? I18n.tr("On") : I18n.tr("Off")
                    on: Toggles.dnd
                    onToggled: Toggles.toggleDnd()
                }
                // On AC only: every lever trades battery and heat for latency, so
                // start refuses on battery. Off must always work, or losing AC
                // would trap the user in Game Mode. AC is the real line-power
                // state (a full cell idling on AC still counts), so no battery
                // is always eligible.
                Menus.QsTile {
                    width: tileGrid.tileWidth
                    icon: "sports_esports"
                    label: I18n.tr("Gaming")
                    available: Toggles.gameMode || Battery.onAc
                    sub: !available ? I18n.tr("Needs AC")
                       : Toggles.gameMode ? I18n.tr("On") : I18n.tr("Off")
                    on: Toggles.gameMode
                    onToggled: Toggles.toggleGame()
                }
            }

            Menus.QsSection { width: parent.width; label: I18n.tr("Sound & display") }
            Column {
                width: parent.width
                spacing: 4

                Menus.QsSlider {
                    width: parent.width
                    icon: "speaker"
                    lit: root.open
                    value: Audio.sink ? Audio.sink.audio.volume : 0
                    muted: Audio.sink ? Audio.sink.audio.muted : false
                    valueLabel: !Audio.sink ? "" : (Audio.sink.audio.muted ? I18n.tr("off") : Math.round(Audio.sink.audio.volume * 100) + "%")
                    peakNode: Audio.sink
                    peakEnabled: root.open && !!Audio.sink
                    hasPage: true
                    onMoved: value => { if (Audio.sink) Audio.sink.audio.volume = value; }
                    onIconTapped: { if (Audio.sink) Audio.sink.audio.muted = !Audio.sink.audio.muted; }
                    onPageRequested: if (root.navigate) root.navigate("audio-out")
                }
                Menus.QsSlider {
                    width: parent.width
                    icon: "mic"
                    lit: root.open
                    value: Audio.source && Audio.source.audio ? Audio.source.audio.volume : 0
                    muted: Audio.source && Audio.source.audio ? Audio.source.audio.muted : false
                    valueLabel: !Audio.source || !Audio.source.audio ? "" : (Audio.source.audio.muted ? I18n.tr("off") : Math.round(Audio.source.audio.volume * 100) + "%")
                    peakNode: Audio.source
                    peakEnabled: root.open && !!Audio.source
                    hasPage: true
                    onMoved: value => { if (Audio.source && Audio.source.audio) Audio.source.audio.volume = value; }
                    onIconTapped: { if (Audio.source && Audio.source.audio) Audio.source.audio.muted = !Audio.source.audio.muted; }
                    onPageRequested: if (root.navigate) root.navigate("audio-in")
                }
                Pill.BrightnessControl {
                    width: parent.width
                    s: 1
                    active: root.open
                }
            }

            Menus.MediaHero {
                width: parent.width
                active: root.open
            }

            Menus.QsSection { width: parent.width; label: I18n.tr("Calendar") }
            Menus.QsCalendarEmbed {
                width: parent.width
                s: 1
                open: root.open
            }

            Menus.QsSection { width: parent.width; label: I18n.tr("System") }
            SysMonitor {
                width: parent.width
                s: 1
                active: root.open
            }
        }
    }

    Column {
        id: powerDock
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        spacing: 6

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
        }
        Menus.QsSection {
            visible: PowerProfiles.available
            width: parent.width
            label: I18n.tr("Power")
        }
        Menus.QsSeg {
            visible: PowerProfiles.available
            width: parent.width
            current: PowerProfiles.profile
            options: PowerProfiles.profiles.map(profile => ({
                id: profile,
                label: profile === "power-saver" ? I18n.tr("Saver") : profile.charAt(0).toUpperCase() + profile.slice(1)
            }))
            onChose: profile => PowerProfiles.setProfile(profile)
        }
    }
}
