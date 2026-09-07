import QtQuick
import "../.."
import "../../components"
import "../../services"
import Ryoku.Ui.Singletons

Row {
    id: root
    property var colors
    property var saveConfigKey
    property var service
    property var openOptimizeConfirm
    property string lastOptimizeResult: ""
    property string _videoCacheResult: ""

    width: parent ? parent.width : 0
    spacing: 12

    readonly property real _colWidth: (width - spacing) / 2

    Connections {
        target: ImageOptimizeService
        function onFinished(optimized, skippedCount, failed) {
            var parts = []
            if (optimized > 0) parts.push(I18n.tr("%1 optimised").arg(optimized))
            if (skippedCount > 0) parts.push(I18n.tr("%1 skipped").arg(skippedCount))
            if (failed > 0) parts.push(I18n.tr("%1 failed").arg(failed))
            root.lastOptimizeResult = parts.length > 0 ? parts.join(" · ") : ""
        }
    }

    Column {
        width: root._colWidth
        spacing: 12

        SettingsCard {
            colors: root.colors
            title: I18n.tr("Image optimisation")
            subtitle: I18n.tr("Convert PNG, JPEG, and GIF images to WebP. Smaller files, no visible quality loss. Steam Workshop assets are never modified.")
            width: parent.width

            RowToggle {
                colors: root.colors
                title: I18n.tr("Auto-optimise new images")
                description: I18n.tr("Automatically convert images dropped into the wallpaper directory.")
                checked: Config.autoOptimizeImages
                onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.autoOptimizeImages", v) }
            }

            RowDropdown {
                colors: root.colors
                title: I18n.tr("Quality")
                description: I18n.tr("Light: q82 max compression. Balanced: q88 good trade-off. Quality: q94 visually lossless.")
                value: Config.imageOptimizePreset
                model: [
                    { mode: "light",    label: I18n.tr("Light") },
                    { mode: "balanced", label: I18n.tr("Balanced") },
                    { mode: "quality",  label: I18n.tr("Quality") }
                ]
                onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.imageOptimizePreset", v) }
            }

            RowDropdown {
                colors: root.colors
                title: I18n.tr("Max resolution")
                description: I18n.tr("Images above the cap are downscaled. Smaller images are never upscaled.")
                value: Config.imageOptimizeResolution
                model: [
                    { mode: "1080p", label: "1080p" },
                    { mode: "2k",    label: "2K" },
                    { mode: "4k",    label: "4K" }
                ]
                onSelect: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.imageOptimizeResolution", v) }
            }

            RowAction {
                colors: root.colors
                title: ImageOptimizeService.running ? I18n.tr("Cancel optimisation") : I18n.tr("Optimise all images")
                description: root.lastOptimizeResult || I18n.tr("Run image optimisation across the wallpaper library.")
                onClicked: {
                    if (ImageOptimizeService.running) ImageOptimizeService.cancel()
                    else if (root.openOptimizeConfirm) root.openOptimizeConfirm()
                }
            }
        }

        SettingsCard {
            colors: root.colors
            title: I18n.tr("Trash")
            subtitle: I18n.tr("Originals are moved to trash before optimisation, so you can recover them if needed.")
            width: parent.width

            RowInput {
                colors: root.colors
                title: I18n.tr("Image retention (days)")
                description: I18n.tr("Days to keep trashed images before auto-cleanup.")
                value: Config.imageTrashDays
                min: 1; max: 365
                onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.imageTrashDays", v) }
            }

            RowToggle {
                colors: root.colors
                title: I18n.tr("Auto-delete images after retention")
                description: I18n.tr("Permanently delete trashed images once they exceed the retention period.")
                checked: Config.autoDeleteImageTrash
                onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.autoDeleteImageTrash", v) }
            }
        }
    }

    Column {
        width: root._colWidth
        spacing: 12

        SettingsCard {
            colors: root.colors
            title: I18n.tr("Previews")
            subtitle: I18n.tr("Animated thumbnails for video wallpapers.")
            width: parent.width

            RowToggle {
                colors: root.colors
                title: I18n.tr("Video previews")
                description: I18n.tr("Play short animated thumbnails when hovering over video wallpapers.")
                checked: Config.videoPreviewEnabled
                onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("features.videoPreview", v) }
            }

            RowToggle {
                colors: root.colors
                title: I18n.tr("Instant playback")
                description: I18n.tr("Start video previews immediately on hover instead of after a short delay.")
                checked: Config.videoPreviewInstant

                onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("features.videoPreviewInstant", v) }
            }
        }

        SettingsCard {
            colors: root.colors
            title: I18n.tr("Thumbnails & cache")
            width: parent.width

            RowInput {
                colors: root.colors
                title: I18n.tr("Max concurrent thumbnail jobs")
                description: I18n.tr("Number of thumbnail jobs that run in parallel during cache rebuilds.")
                value: Config.maxThumbJobs
                min: 1; max: 64
                onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.maxThumbJobs", v) }
            }

            RowAction {
                colors: root.colors
                title: DaemonClient.cacheRunning ? I18n.tr("Clearing cache...") : I18n.tr("Clear all cached data")
                description: I18n.tr("Erase all cached thumbnails and regenerate from scratch on next scan.")
                onClicked: if (root.service && !DaemonClient.cacheRunning) root.service.clearData()
            }

            RowAction {
                colors: root.colors
                title: _recomputeState._running ? I18n.tr("Recomputing colours...") : I18n.tr("Recompute colours")
                description: I18n.tr("Re-derive per-wallpaper colour bucket and saturation from existing thumbnails. Useful after the algorithm changes - does not touch tags or favourites.")
                onClicked: {
                    if (_recomputeState._running) return
                    _recomputeState._running = true
                    DaemonClient.recomputeColors(function(_r, _e) { _recomputeReset.restart() })
                }

                QtObject {
                    id: _recomputeState
                    property bool _running: false
                }
                Timer {
                    id: _recomputeReset
                    interval: 60000
                    onTriggered: _recomputeState._running = false
                }
                Connections {
                    target: DaemonClient
                    function onEventReceived(event, data) {
                        if (event === "ryogami.wall.recompute_colors.complete") {
                            _recomputeState._running = false
                            _recomputeReset.stop()
                            if (root.service && root.service.refreshFromDb) root.service.refreshFromDb()
                        }
                    }
                }
            }
        }

        SettingsCard {
            colors: root.colors
            title: I18n.tr("Video cache")
            subtitle: I18n.tr("Transcoded copies of video wallpapers, rebuilt automatically when a clip plays. Clearing them is safe.")
            width: parent.width

            RowInput {
                colors: root.colors
                title: I18n.tr("Cache retention (days)")
                description: I18n.tr("Days to keep transcoded video clips before auto-clean removes them.")
                value: Config.videoCacheDays
                min: 1; max: 365
                onCommit: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.videoCacheDays", v) }
            }

            RowToggle {
                colors: root.colors
                title: I18n.tr("Auto-clean cached transcodes")
                description: I18n.tr("Remove transcoded clips older than the retention period when the picker opens.")
                checked: Config.autoCleanVideoCache
                onToggle: function(v) { if (root.saveConfigKey) root.saveConfigKey("performance.autoCleanVideoCache", v) }
            }

            RowAction {
                colors: root.colors
                title: I18n.tr("Clear video cache")
                description: root._videoCacheResult || I18n.tr("Delete all transcoded video clips now.")
                onClicked: {
                    DaemonClient.clearVideoCache(0, function(res, err) {
                        if (err || !res) { root._videoCacheResult = I18n.tr("Clear failed"); return }
                        var freed = res.freed || 0
                        var mb = (freed / 1048576).toFixed(freed >= 10485760 ? 0 : 1)
                        root._videoCacheResult = (res.removed || 0) > 0
                            ? I18n.tr("Cleared %1 clips \u00b7 %2 MB freed").arg(res.removed).arg(mb)
                            : I18n.tr("Cache already empty")
                    })
                }
            }
        }
    }
}
