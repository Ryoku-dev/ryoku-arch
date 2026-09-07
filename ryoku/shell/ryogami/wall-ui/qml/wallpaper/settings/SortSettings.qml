import QtQuick
import "../.."
import "../../components"
import Ryoku.Ui.Singletons

Column {
    id: root
    property var colors
    property var service

    width: parent ? parent.width : 0
    spacing: 8

    SettingsCard {
        colors: root.colors
        title: I18n.tr("Sort mode")
        subtitle: I18n.tr("How wallpapers are ordered in the selector. The same option is also available as a quick toggle in the filter bar.")

        Repeater {
            model: [
                { mode: "color",       label: I18n.tr("Default"),      description: I18n.tr("Group by dominant color (red - orange - yellow - … - pink - neutral). Within each color, the most-saturated wallpapers come first.") },
                { mode: "pop",         label: I18n.tr("Color pop"),    description: I18n.tr("Sort by how much vivid color the wallpaper actually contains, ignoring which color it is. Saturated, eye-catching wallpapers lead; muted and mostly-neutral ones drop to the back.") },
                { mode: "richness",    label: I18n.tr("Colourful"),    description: I18n.tr("Sort by palette diversity - wallpapers using many distinct colors lead, monochrome scenes fall to the back. Good for finding maximalist artwork and detailed illustrations.") },
                { mode: "minimalist",  label: I18n.tr("Minimalist"),   description: I18n.tr("Inverse of richness - fewest colors first. Solid backgrounds, clean gradients, and single-subject compositions surface; busy multi-color images drop to the back.") },
                { mode: "applied",     label: I18n.tr("Most applied"), description: I18n.tr("Sorts by how often you've actually set this wallpaper. Your greatest hits lead; never-applied wallpapers fall back to newest-first within them.") },
                { mode: "date",        label: I18n.tr("Newest"),       description: I18n.tr("Most recently added wallpapers first. Useful right after dropping new files into your wallpaper directory.") }
            ]
            delegate: SettingsRow {
                colors: root.colors
                title: I18n.tr(modelData.label)
                description: modelData.description
                onClicked: {
                    if (!root.service) return
                    root.service.sortMode = modelData.mode
                    root.service.updateFilteredModel()
                }

                Rectangle {
                    width: 16; height: 16; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    property bool active: root.service && root.service.sortMode === modelData.mode
                    color: active
                        ? (root.colors ? root.colors.primary : "#7986cb")
                        : "transparent"
                    border.width: 2
                    border.color: root.colors ? root.colors.primary : "#7986cb"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6; height: 6; radius: 3
                        color: root.colors ? root.colors.primaryText : "#000"
                        visible: parent.active
                    }
                }
            }
        }
    }
}
