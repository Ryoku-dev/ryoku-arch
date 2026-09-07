pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import shell.services
import "../stage"
import "../stage/Singletons" as Stage
import "../../components"

// Edit shell, Dock tab (docs/stage.md): Show, Position, Style, Behaviour and
// Surface groups over the Dock store, plus an Apps drop-down for the pinned list
// and a picker. Behaviour and Surface fold into drop-downs at 1366.
Item {
    id: tab
    anchors.fill: parent

    property Item overlay: null
    property real dropY: 0
    property string monitor: ""
    property bool narrow: false

    onVisibleChanged: if (tab.visible && Stage.StageSession.selected !== "dock") Stage.StageSession.select("dock")

    function setDock(key, value) { Dock.setCfg(key, value); Stage.StageSession.markDirty(); }
    function dockOn(key, fb) { return Dock.cfg(key, fb) === true; }

    readonly property var pins: Dock.pinnedOrStarter()
    function movePin(i, dir) {
        const a = tab.pins.slice();
        const j = i + dir;
        if (j < 0 || j >= a.length) return;
        const t = a[i]; a[i] = a[j]; a[j] = t;
        Dock.setPinned(a); Stage.StageSession.markDirty();
    }
    function removePin(cls) {
        const a = [];
        for (const c of tab.pins) if (c !== cls) a.push(c);
        Dock.setPinned(a); Stage.StageSession.markDirty();
    }
    function addPin(cls) {
        if (tab.pins.indexOf(cls) < 0) { Dock.setPinned(tab.pins.concat(cls)); Stage.StageSession.markDirty(); }
    }
    // Installed apps not already pinned, as { cls, name } sorted by name.
    readonly property var appPool: {
        const src = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const e = src[i];
            if (!e || e.noDisplay) continue;
            const cls = e.id ? String(e.id) : String(e.name || "");
            if (cls === "" || tab.pins.indexOf(cls) >= 0) continue;
            out.push({ cls: cls, name: e.name || cls });
        }
        out.sort((a, b) => String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase()));
        return out;
    }
    function appName(cls) { const e = DesktopEntries.heuristicLookup(cls); return (e && e.name) ? e.name : cls; }

    component MiniBtn: Rectangle {
        id: mb
        property string icon: ""
        property bool enabledAct: true
        signal act()
        width: 24; height: 24; radius: 6
        opacity: mb.enabledAct ? 1 : 0.3
        color: mbMa.containsMouse && mb.enabledAct ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        MaterialIcon { anchors.centerIn: parent; text: mb.icon; font.pixelSize: 16; color: Theme.onSurfaceVariant }
        MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (mb.enabledAct) mb.act() }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RibbonGroup {
            caption: "Show"
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Dock"; checked: tab.dockOn("enabled", false)
                onToggled: tab.setDock("enabled", !tab.dockOn("enabled", false))
            }
        }
        RibbonGroup {
            caption: "Position"
            StageSeg {
                width: 320
                anchors.verticalCenter: parent.verticalCenter
                options: [
                    { id: "auto", label: "Auto" }, { id: "top", label: "Top" },
                    { id: "bottom", label: "Bottom" }, { id: "left", label: "Left" },
                    { id: "right", label: "Right" }
                ]
                current: Dock.cfg("edge", "auto")
                onChose: id => tab.setDock("edge", id)
            }
        }
        RibbonGroup {
            caption: "Style"
            StageSeg {
                width: 340
                anchors.verticalCenter: parent.verticalCenter
                options: [
                    { id: "ledger", label: "Ledger" }, { id: "islands", label: "Islands" },
                    { id: "rail", label: "Rail" }, { id: "seal", label: "Seal" },
                    { id: "tanzaku", label: "Tanzaku" }
                ]
                current: Dock.cfg("style", "islands")
                onChose: id => tab.setDock("style", id)
            }
        }

        RibbonGroup {
            caption: "Behaviour"
            visible: !tab.narrow
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Auto-hide"; checked: tab.dockOn("autohide", true); onToggled: tab.setDock("autohide", !tab.dockOn("autohide", true)) }
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Magnify"; checked: tab.dockOn("magnify", true); onToggled: tab.setDock("magnify", !tab.dockOn("magnify", true)) }
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Media chip"; checked: tab.dockOn("media", false); onToggled: tab.setDock("media", !tab.dockOn("media", false)) }
            }
        }
        RibbonDropdown {
            visible: tab.narrow
            overlay: tab.overlay; dropY: tab.dropY
            key: "behaviour"; label: "Behaviour"; icon: "tune"; panelW: 240
            StageSwitch { label: "Auto-hide"; checked: tab.dockOn("autohide", true); onToggled: tab.setDock("autohide", !tab.dockOn("autohide", true)) }
            StageSwitch { label: "Magnify"; checked: tab.dockOn("magnify", true); onToggled: tab.setDock("magnify", !tab.dockOn("magnify", true)) }
            StageSwitch { label: "Media chip"; checked: tab.dockOn("media", false); onToggled: tab.setDock("media", !tab.dockOn("media", false)) }
        }

        RibbonGroup {
            caption: "Surface"
            visible: !tab.narrow
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Frost"; checked: tab.dockOn("frost", true); onToggled: tab.setDock("frost", !tab.dockOn("frost", true)) }
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Shadow"; checked: tab.dockOn("shadow", true); onToggled: tab.setDock("shadow", !tab.dockOn("shadow", true)) }
                StageSwitch { anchors.verticalCenter: parent.verticalCenter; label: "Labels"; checked: tab.dockOn("labels", true); onToggled: tab.setDock("labels", !tab.dockOn("labels", true)) }
            }
        }
        RibbonDropdown {
            visible: tab.narrow
            overlay: tab.overlay; dropY: tab.dropY
            key: "surface"; label: "Surface"; icon: "layers"; panelW: 220
            StageSwitch { label: "Frost"; checked: tab.dockOn("frost", true); onToggled: tab.setDock("frost", !tab.dockOn("frost", true)) }
            StageSwitch { label: "Shadow"; checked: tab.dockOn("shadow", true); onToggled: tab.setDock("shadow", !tab.dockOn("shadow", true)) }
            StageSwitch { label: "Labels"; checked: tab.dockOn("labels", true); onToggled: tab.setDock("labels", !tab.dockOn("labels", true)) }
        }

        RibbonDropdown {
            overlay: tab.overlay; dropY: tab.dropY
            key: "apps"; label: "Apps"; icon: "apps"; panelW: 340

            Text {
                text: "Pinned"
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
                font.weight: Font.DemiBold
            }
            Repeater {
                model: tab.pins
                delegate: Rectangle {
                    id: pinRow
                    required property string modelData
                    required property int index
                    width: parent.width
                    height: 36
                    radius: 6
                    color: pinMa.hovered ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05) : "transparent"
                    HoverHandler { id: pinMa }
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: pinCtl.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            source: Dock.iconFor(pinRow.modelData)
                            visible: source !== ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28
                            elide: Text.ElideRight
                            text: tab.appName(pinRow.modelData)
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 2
                        }
                    }
                    Row {
                        id: pinCtl
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        MiniBtn { icon: "keyboard_arrow_up"; enabledAct: pinRow.index > 0; onAct: tab.movePin(pinRow.index, -1) }
                        MiniBtn { icon: "keyboard_arrow_down"; enabledAct: pinRow.index < tab.pins.length - 1; onAct: tab.movePin(pinRow.index, 1) }
                        MiniBtn { icon: "close"; onAct: tab.removePin(pinRow.modelData) }
                    }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12) }
            Text {
                text: "Pin an app"
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
                font.weight: Font.DemiBold
            }
            Repeater {
                model: tab.appPool
                delegate: Rectangle {
                    id: appRow
                    required property var modelData
                    width: parent.width
                    height: 34
                    radius: 6
                    color: appMa.containsMouse ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05) : "transparent"
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            source: Dock.iconFor(appRow.modelData.cls)
                            visible: source !== ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26
                            elide: Text.ElideRight
                            text: appRow.modelData.name
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 2
                        }
                    }
                    MaterialIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "add"
                        font.pixelSize: 17
                        color: Theme.onSurfaceVariant
                    }
                    MouseArea {
                        id: appMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tab.addPin(appRow.modelData.cls)
                    }
                }
            }
        }
    }
}
