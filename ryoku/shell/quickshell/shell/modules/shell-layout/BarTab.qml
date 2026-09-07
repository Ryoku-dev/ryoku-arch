pragma ComponentBehavior: Bound
import QtQuick
import shell.services
import "Singletons"
import "../stage"
import "../stage/Singletons" as Stage
import "../bar/barstyles/qsbar/core" as QsCore
import "../../components"

// Edit shell, Bar tab (docs/stage.md): Position, Behaviour, Form, Size and
// Surface as labelled ribbon groups over the qsbar object seam, plus a Modules
// drop-down that edits the three lanes of qsbar.layout. At 1366 the Surface group
// folds into a drop-down rather than shrinking; Modules is always a drop-down.
Item {
    id: tab
    anchors.fill: parent

    property Item overlay: null
    property real dropY: 0
    property string monitor: ""
    property bool narrow: false

    // The built-in widget catalogue (id -> label) that qsbar.layout is written
    // in, loaded from the same widgets.json the bar itself reads.
    QsCore.BarCatalog { id: barCat }

    readonly property var lanes: Layout.barLayout()
    readonly property var placed: tab.lanes.left.concat(tab.lanes.center, tab.lanes.right)
    readonly property var available: {
        const out = [];
        const ents = barCat.entries || [];
        for (let i = 0; i < ents.length; i++)
            if (ents[i].id && tab.placed.indexOf(ents[i].id) < 0)
                out.push(ents[i].id);
        return out;
    }
    function labelOf(id) { const e = barCat.byId(id); return (e && e.label) ? e.label : id; }

    function _lanesCopy() {
        const L = tab.lanes;
        return { version: 1, left: L.left.slice(), center: L.center.slice(), right: L.right.slice() };
    }
    function moveIn(section, idx, dir) {
        const L = tab._lanesCopy();
        const a = L[section];
        const j = idx + dir;
        if (j < 0 || j >= a.length) return;
        const t = a[idx]; a[idx] = a[j]; a[j] = t;
        Layout.setBarLayout(L);
    }
    function removeFrom(section, idx) {
        const L = tab._lanesCopy();
        L[section].splice(idx, 1);
        Layout.setBarLayout(L);
    }
    function addTo(section, id) {
        const L = tab._lanesCopy();
        for (const s of ["left", "center", "right"]) {
            const k = L[s].indexOf(id);
            if (k >= 0) L[s].splice(k, 1);
        }
        L[section].push(id);
        Layout.setBarLayout(L);
    }

    onVisibleChanged: if (tab.visible && Stage.StageSession.selected !== "bar") Stage.StageSession.select("bar")

    // A compact glyph button used in the module rows.
    component MiniBtn: Rectangle {
        id: mb
        property string icon: ""
        property string text_: ""
        property bool enabledAct: true
        signal act()
        width: mb.text_.length > 0 ? 22 : 24
        height: 24
        radius: 6
        opacity: mb.enabledAct ? 1 : 0.3
        color: mbMa.containsMouse && mb.enabledAct ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.1) : "transparent"
        MaterialIcon {
            anchors.centerIn: parent
            visible: mb.icon.length > 0
            text: mb.icon
            font.pixelSize: 16
            color: Theme.onSurfaceVariant
        }
        Text {
            anchors.centerIn: parent
            visible: mb.text_.length > 0
            text: mb.text_
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: Theme.fontSm - 3
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: mbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (mb.enabledAct) mb.act()
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RibbonGroup {
            caption: "Position"
            StageSeg {
                width: 128
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "top", label: "Top" }, { id: "bottom", label: "Bottom" }]
                current: Layout.barGet("barPosition", "top")
                onChose: id => Layout.setBar("barPosition", id)
            }
        }
        RibbonGroup {
            caption: "Behaviour"
            StageSwitch {
                anchors.verticalCenter: parent.verticalCenter
                label: "Auto-hide"
                checked: Layout.barGet("barAutoHide", false) === true
                onToggled: Layout.setBar("barAutoHide", !(Layout.barGet("barAutoHide", false) === true))
            }
        }
        RibbonGroup {
            caption: "Form"
            StageSeg {
                width: 300
                anchors.verticalCenter: parent.verticalCenter
                options: [
                    { id: "islands", label: "Islands" }, { id: "full", label: "Full" },
                    { id: "fit", label: "Fit" }, { id: "dock", label: "Dock" },
                    { id: "notch", label: "Notch" }
                ]
                current: Layout.barGet("barShellStyle", "full")
                onChose: id => Layout.setBar("barShellStyle", id)
            }
        }
        RibbonGroup {
            caption: "Size"
            StageDragSlider {
                width: 140
                anchors.verticalCenter: parent.verticalCenter
                title: ""
                value: Layout.barGet("barScale", 1)
                min: 0.8; max: 1.3; decimals: 2
                onChanged: v => Layout.setBar("barScale", Math.round(v * 100) / 100)
            }
        }

        // Surface, inline when there is room, folded into a drop-down at 1366.
        RibbonGroup {
            caption: "Surface"
            visible: !tab.narrow
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                StageSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Frost"; checked: Layout.barGet("barFrostEnabled", false) === true
                    onToggled: Layout.setBar("barFrostEnabled", !(Layout.barGet("barFrostEnabled", false) === true))
                }
                StageSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Shadow"; checked: Layout.barGet("barShadowEnabled", false) === true
                    onToggled: Layout.setBar("barShadowEnabled", !(Layout.barGet("barShadowEnabled", false) === true))
                }
                StageSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Border"; checked: Layout.barGet("barBorderEnabled", true) === true
                    onToggled: Layout.setBar("barBorderEnabled", !(Layout.barGet("barBorderEnabled", true) === true))
                }
                StageDragSlider {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    title: "Corners"
                    value: Layout.barGet("barCornerRadius", 6)
                    min: 0; max: 24; decimals: 0
                    onChanged: v => Layout.setBar("barCornerRadius", Math.round(v))
                }
            }
        }
        RibbonDropdown {
            visible: tab.narrow
            overlay: tab.overlay
            dropY: tab.dropY
            key: "surface"
            label: "Surface"
            icon: "tune"
            panelW: 280
            StageSwitch {
                label: "Frost"; checked: Layout.barGet("barFrostEnabled", false) === true
                onToggled: Layout.setBar("barFrostEnabled", !(Layout.barGet("barFrostEnabled", false) === true))
            }
            StageSwitch {
                label: "Shadow"; checked: Layout.barGet("barShadowEnabled", false) === true
                onToggled: Layout.setBar("barShadowEnabled", !(Layout.barGet("barShadowEnabled", false) === true))
            }
            StageSwitch {
                label: "Border"; checked: Layout.barGet("barBorderEnabled", true) === true
                onToggled: Layout.setBar("barBorderEnabled", !(Layout.barGet("barBorderEnabled", true) === true))
            }
            StageDragSlider {
                width: 256
                title: "Corners"
                value: Layout.barGet("barCornerRadius", 6)
                min: 0; max: 24; decimals: 0
                onChanged: v => Layout.setBar("barCornerRadius", Math.round(v))
            }
        }

        // Modules: the three lanes of qsbar.layout, always a drop-down.
        RibbonDropdown {
            id: modulesDd
            overlay: tab.overlay
            dropY: tab.dropY
            key: "modules"
            label: "Modules"
            icon: "view_column"
            panelW: 540

            Row {
                width: parent.width
                spacing: 12
                Repeater {
                    model: [
                        { section: "left", caption: "Left" },
                        { section: "center", caption: "Centre" },
                        { section: "right", caption: "Right" }
                    ]
                    delegate: Column {
                        id: laneCol
                        required property var modelData
                        width: (parent.width - 24) / 3
                        spacing: 4
                        Text {
                            text: laneCol.modelData.caption
                            color: Theme.onSurfaceVariant
                            font.family: Theme.fontPrimary
                            font.pixelSize: Theme.fontSm - 3
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: tab.lanes[laneCol.modelData.section]
                            delegate: Rectangle {
                                id: modRow
                                required property string modelData
                                required property int index
                                width: parent.width
                                height: 30
                                radius: 6
                                color: modMa.hovered ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05) : "transparent"
                                HoverHandler { id: modMa }
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - ctlRow.width - 10
                                    elide: Text.ElideRight
                                    text: tab.labelOf(modRow.modelData)
                                    color: Theme.onSurface
                                    font.family: Theme.fontPrimary
                                    font.pixelSize: Theme.fontSm - 2
                                }
                                Row {
                                    id: ctlRow
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    MiniBtn {
                                        icon: "keyboard_arrow_up"
                                        enabledAct: modRow.index > 0
                                        onAct: tab.moveIn(laneCol.modelData.section, modRow.index, -1)
                                    }
                                    MiniBtn {
                                        icon: "keyboard_arrow_down"
                                        enabledAct: modRow.index < tab.lanes[laneCol.modelData.section].length - 1
                                        onAct: tab.moveIn(laneCol.modelData.section, modRow.index, 1)
                                    }
                                    MiniBtn {
                                        icon: "close"
                                        onAct: tab.removeFrom(laneCol.modelData.section, modRow.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
            }
            Text {
                text: "Add a module"
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 3
                font.weight: Font.DemiBold
            }
            Text {
                visible: tab.available.length === 0
                width: parent.width
                text: "Every module is on the bar."
                wrapMode: Text.WordWrap
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: Theme.fontSm - 2
            }
            Repeater {
                model: tab.available
                delegate: Rectangle {
                    id: addRow
                    required property string modelData
                    width: parent.width
                    height: 32
                    radius: 6
                    color: addMa.hovered ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05) : "transparent"
                    HoverHandler { id: addMa }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - laneBtns.width - 10
                        elide: Text.ElideRight
                        text: tab.labelOf(addRow.modelData)
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: Theme.fontSm - 2
                    }
                    Row {
                        id: laneBtns
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        MiniBtn { text_: "L"; onAct: tab.addTo("left", addRow.modelData) }
                        MiniBtn { text_: "C"; onAct: tab.addTo("center", addRow.modelData) }
                        MiniBtn { text_: "R"; onAct: tab.addTo("right", addRow.modelData) }
                    }
                }
            }
        }
    }
}
