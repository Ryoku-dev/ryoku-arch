pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"
import "../stage"
import "../stage/Singletons" as Stage

// Edit shell, Menus tab (docs/stage.md): a chip per edge menu (Quick settings,
// Theme, Wallpaper, Weather) that selects it, then Edge, Stretch and Width for
// the chosen one. Picking an edge already held by another menu swaps them
// (Layout.setMenuAnchor). Fits at 1366 with no folding.
Item {
    id: tab
    anchors.fill: parent

    property Item overlay: null
    property real dropY: 0
    property string monitor: ""
    property bool narrow: false

    readonly property var ses: Stage.StageSession
    readonly property string sel: Layout.menuIds.indexOf(tab.ses.selected) >= 0 ? tab.ses.selected : "quick-settings"

    onVisibleChanged: if (tab.visible && Layout.menuIds.indexOf(tab.ses.selected) < 0) tab.ses.select("quick-settings")

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        RibbonGroup {
            caption: "Menu"
            StageSeg {
                width: 430
                anchors.verticalCenter: parent.verticalCenter
                options: [
                    { id: "quick-settings", label: "Quick settings" },
                    { id: "theme", label: "Theme" },
                    { id: "wallpaper", label: "Wallpaper" },
                    { id: "weather", label: "Weather" }
                ]
                current: tab.sel
                onChose: id => tab.ses.select(id)
            }
        }
        RibbonGroup {
            caption: "Edge"
            StageSeg {
                width: 260
                anchors.verticalCenter: parent.verticalCenter
                options: [
                    { id: "top", label: "Top" }, { id: "bottom", label: "Bottom" },
                    { id: "left", label: "Left" }, { id: "right", label: "Right" }
                ]
                current: Layout.menuAnchor(tab.sel)
                onChose: id => Layout.setMenuAnchor(tab.sel, id)
            }
        }
        RibbonGroup {
            caption: "Stretch"
            StageSeg {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                options: [{ id: "always", label: "Always" }, { id: "never", label: "Never" }]
                current: Layout.menuExpansion(tab.sel)
                onChose: id => Layout.setMenuExpansion(tab.sel, id)
            }
        }
        RibbonGroup {
            caption: "Width"
            last: true
            StageDragSlider {
                width: 190
                anchors.verticalCenter: parent.verticalCenter
                title: ""
                unit: " px"
                value: Layout.menuWidth(tab.sel)
                min: 280; max: 1600; decimals: 0
                onChanged: v => Layout.setMenuWidth(tab.sel, v)
            }
        }
    }
}
