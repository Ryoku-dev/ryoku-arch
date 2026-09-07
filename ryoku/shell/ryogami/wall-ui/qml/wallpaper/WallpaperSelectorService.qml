import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../services"
import Ryoku.Ui.Singletons

QtObject {
  id: service


  required property string scriptsDir
  required property string homeDir
  required property string wallpaperDir
  required property string videoDir
  required property string cacheBaseDir
  required property string weDir
  required property string weAssetsDir
  required property bool showing

  property string thumbsCacheDir: cacheBaseDir + "/wallpaper/thumbs"
  property string weCache: cacheBaseDir + "/wallpaper/we-thumbs"

  property bool cacheReady: false
  property string cacheResult: ""
  readonly property int cacheProgress: DaemonClient.cacheProgress
  readonly property int cacheTotal: DaemonClient.cacheTotal
  property bool cacheLoading: DaemonClient.cacheRunning

  property int selectedColorFilter: -1
  property string selectedTypeFilter: ""
  property string selectedFolder: ""
  property var availableFolders: []
  property string sortMode: "color"
  property var favouritesDb: ({})
  property bool favouriteFilterActive: false
  property bool _favouritesLoaded: false
  property bool _videoCachePruned: false

  function _loadFromDaemon() {
    console.log("[WSS] _loadFromDaemon called, DaemonClient.ready=" + DaemonClient.ready)
    DaemonClient.listWallpapers(false, function(result, error) {
      if (error) {
        console.warn("[WSS] listWallpapers error:", error.message)
        return
      }
      var walls = result.wallpapers || []
      console.log("[WSS] listWallpapers returned " + walls.length + " items")
      var items = []
      var newFavs = {}

      for (var i = 0; i < walls.length; i++) {
        var r = walls[i]
        var type = r.type, name = r.name, thumb = r.thumb
        if (!name || !thumb) continue
        var key = r.key || name
        var videoFile = r.video_file || "", weId = r.we_id || ""
        var videoPrev = r.video_prev || ""
        var mtime = r.mtime || 0
        var hue = r.hue != null ? r.hue : 99, sat = r.sat || 0
        var richness = r.richness != null ? r.richness : 0
        var applyCount = r.apply_count != null ? r.apply_count : 0

        items.push({
          name: name, type: type, thumb: thumb,
          path: type === "static" ? service.wallpaperDir + "/" + name
              : (type === "video" ? (videoFile || service.videoDir + "/" + name) : ""),
          weId: weId, videoFile: videoFile, videoPrev: videoPrev,
          mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
          placeholder: false
        })

        if (r.favourite === 1) newFavs[key] = true
      }

      console.log("[WSS] built " + items.length + " model items from " + walls.length + " daemon rows")
      _wallpaperData = items
      var keys = {}
      for (var k = 0; k < items.length; k++) {
        var lookupKey = items[k].weId || items[k].name
        keys[lookupKey] = true
      }
      _wallpaperDataKeys = keys
      if (!_favouritesLoaded) {
        favouritesDb = newFavs
        _favouritesLoaded = true
      }

      cacheReady = true
      cacheResult = "cached"

      FileMetadataService.loadFromDaemonData(walls)
      updateFilteredModel()

      if (!service._videoCachePruned && Config.autoCleanVideoCache) {
        service._videoCachePruned = true
        DaemonClient.clearVideoCache(Config.videoCacheDays)
      }
    })
  }

  function refreshFromDb() {
    _loadFromDaemon()
  }

  function startCacheCheck() {
    console.log("[WSS] startCacheCheck called, DaemonClient.ready=" + DaemonClient.ready)
    cacheResult = ""

    if (DaemonClient.ready) {
      _loadFromDaemon()
    }
  }

  property var _daemonConn: Connections {
    target: DaemonClient
    function onReadyChanged() {
      console.log("[WSS] onReadyChanged: ready=" + DaemonClient.ready)
      if (DaemonClient.ready)
        service._loadFromDaemon()
    }
    function onCacheReady() {
      console.log("[WSS] onCacheReady")
      service._loadFromDaemon()
    }
    function onScanDone() {
      console.log("[WSS] onScanDone")
    }
    function onWeItemAdded(weId, weDir) {
      console.log("[WSS] onWeItemAdded: " + weId + " dir=" + weDir)
    }

    
    function onWallpaperApplied(type, name, path, weId, key) {
      var matchKey = key || weId || (name || "").replace(/\.[^.]+$/, "")
      if (!matchKey) return
      
      for (var i = 0; i < service._wallpaperData.length; i++) {
        var item = service._wallpaperData[i]
        var itemKey = item.weId || (item.name || "").replace(/\.[^.]+$/, "")
        if (itemKey === matchKey) {
          item.applyCount = (item.applyCount || 0) + 1
          break
        }
      }
      
      for (var j = 0; j < service.filteredModel.count; j++) {
        var row = service.filteredModel.get(j)
        var rowKey = (row.weId || "")
          ? row.weId
          : (row.name || "").replace(/\.[^.]+$/, "")
        if (rowKey === matchKey) {
          service.filteredModel.setProperty(j, "applyCount", (row.applyCount || 0) + 1)
          break
        }
      }
    }

    function onItemCached(data) {
      var type = data.type || "static"
      var name = data.name || ""
      var thumb = data.thumb || ""
      if (!name || !thumb) return

      var key = data.key || name
      var weId = data.we_id || ""
      var videoFile = data.video_file || ""
      var videoPrev = data.video_prev || ""
      var mtime = data.mtime || 0
      var hue = data.hue != null ? data.hue : 99
      var sat = data.sat || 0
      var richness = data.richness != null ? data.richness : 0
      var applyCount = data.apply_count != null ? data.apply_count : 0

      var lookupKey = weId || name
      if (_wallpaperDataKeys[lookupKey]) return

      var path = type === "static" ? service.wallpaperDir + "/" + name
               : type === "video" ? (videoFile || (service.videoDir + "/" + name))
               : ""

      var item = {
        name: name, type: type, thumb: thumb,
        path: path,
        weId: weId, videoFile: videoFile, videoPrev: videoPrev,
        mtime: mtime, hue: hue, saturation: sat, richness: richness, applyCount: applyCount,
        placeholder: false
      }
      _wallpaperData.push(item)
      _wallpaperDataKeys[lookupKey] = true

      var idx = _findInsertIndex(item)
      service.filteredModel.insert(idx, item)
    }

    function _findInsertIndex(item) {
      var count = service.filteredModel.count
      for (var i = 0; i < count; i++) {
        var existing = service.filteredModel.get(i)
        if (sortMode === "date") {
          if (item.mtime > existing.mtime) return i
        } else if (sortMode === "pop") {
          var popItem = item.saturation - item.richness / 15
          var popEx = existing.saturation - existing.richness / 15
          if (popItem > popEx) return i
        } else if (sortMode === "richness") {
          if (item.richness > existing.richness) return i
          if (item.richness === existing.richness && item.saturation > existing.saturation) return i
        } else if (sortMode === "minimalist") {
          if (item.richness < existing.richness) return i
          if (item.richness === existing.richness && item.saturation > existing.saturation) return i
        } else if (sortMode === "applied") {
          if (item.applyCount > existing.applyCount) return i
          if (item.applyCount === existing.applyCount && item.mtime > existing.mtime) return i
        } else {
          var hueNew = item.hue === 99 ? 100 : item.hue
          var hueEx = existing.hue === 99 ? 100 : existing.hue
          if (hueNew < hueEx) return i
          if (hueNew === hueEx && item.saturation > existing.saturation) return i
        }
      }
      return count
    }

    function onFileAdded(name, path, type) {
      console.log("[WSS] onFileAdded: " + name + " path=" + path + " type=" + type)
    }

    function onFileRenamed(oldName, newName) {
      console.log("[WSS] onFileRenamed: " + oldName + " -> " + newName)

      for (var i = 0; i < service.filteredModel.count; i++) {
        if (service.filteredModel.get(i).name === oldName) {
          service.filteredModel.setProperty(i, "name", newName)
          service.filteredModel.setProperty(i, "path", service.wallpaperDir + "/" + newName)
          break
        }
      }

      for (var j = 0; j < _wallpaperData.length; j++) {
        if (_wallpaperData[j].name === oldName) {
          _wallpaperData[j].name = newName
          _wallpaperData[j].path = service.wallpaperDir + "/" + newName
          break
        }
      }

      delete _wallpaperDataKeys[oldName]
      _wallpaperDataKeys[newName] = true
    }

    function onFileRemoved(name, type) {
      console.log("[WSS] onFileRemoved: " + name + " type=" + type)

      for (var i = service.filteredModel.count - 1; i >= 0; i--) {
        var fi = service.filteredModel.get(i)
        if (fi.name === name) {
          service.filteredModel.remove(i)
          break
        }
      }

      for (var j = _wallpaperData.length - 1; j >= 0; j--) {
        if (_wallpaperData[j].name === name) {
          _wallpaperData.splice(j, 1)
          break
        }
      }

      delete _wallpaperDataKeys[name]
    }

    function onFolderRemoved(names) {
      var nameSet = {}
      for (var n = 0; n < names.length; n++) nameSet[names[n]] = true

      for (var i = service.filteredModel.count - 1; i >= 0; i--) {
        if (nameSet[service.filteredModel.get(i).name])
          service.filteredModel.remove(i)
      }

      for (var j = _wallpaperData.length - 1; j >= 0; j--) {
        var nm = _wallpaperData[j].name
        if (nameSet[nm]) {
          _wallpaperData.splice(j, 1)
          delete _wallpaperDataKeys[nm]
        }
      }
    }
  }

  function isFavourite(name, weId) {
    var key = weId ? weId : name
    return !!favouritesDb[key]
  }

  function toggleFavourite(name, weId) {
    var key = weId ? weId : name
    var db = JSON.parse(JSON.stringify(favouritesDb))
    if (db[key]) {
      delete db[key]
    } else {
      db[key] = true
    }
    favouritesDb = db
    DaemonClient.setFavourite(key, !!db[key])
    if (favouriteFilterActive) updateFilteredModel()
  }

  property var _debouncedUpdate: Timer {
    interval: 0
    onTriggered: service.updateFilteredModel()
  }

  onFavouriteFilterActiveChanged: _debouncedUpdate.restart()

  property var _wallpaperData: []
  property var _wallpaperDataKeys: ({})
  property var filteredModel: ListModel {}
  property string lastApplyError: ""

  signal modelUpdated()
  signal wallpaperApplied()
  signal wallpaperApplyFailed(string message)

  function _handleApplyResult(result, error) {
    if (error) {
      var message = error.message || I18n.tr("wallpaper apply failed (code %1)").arg(error.code ?? I18n.tr("unknown"))
      lastApplyError = message
      console.warn("[WSS] wallpaper apply failed:", message)
      wallpaperApplyFailed(message)
      return
    }
    lastApplyError = ""
    wallpaperApplied()
  }

  function _folderOf(item) {
    if (!item) return ""
    if (item.type === "we") return "Wallpaper Engine"
    if (item.type !== "static") return ""
    var name = item.name
    var slash = name ? name.indexOf("/") : -1
    return slash > 0 ? name.substring(0, slash) : ""
  }

  function _rebuildFolders() {
    var seen = ({}), out = []
    for (var i = 0; i < _wallpaperData.length; i++) {
      var f = _folderOf(_wallpaperData[i])
      if (f !== "" && seen[f] === undefined) { seen[f] = true; out.push(f) }
    }
    out.sort()
    if (out.join(" ") !== availableFolders.join(" ")) availableFolders = out
  }

  function updateFilteredModel(skipCrossfade) {
    _skipCrossfade = !!skipCrossfade
    _rebuildFolders()

    var items = []
    for (var i = 0; i < _wallpaperData.length; i++) {
      var item = _wallpaperData[i]
      var hue = item.hue
      var saturation = item.saturation || 0
      var effectiveType = (item.type === "we" && item.videoFile) ? "video" : item.type
      if (selectedFolder !== "*" && _folderOf(item) !== selectedFolder) continue
      if (selectedTypeFilter !== "" && effectiveType !== selectedTypeFilter) continue
      if (selectedColorFilter !== -1 && hue !== selectedColorFilter) continue
      if (favouriteFilterActive && !isFavourite(item.name, item.weId)) continue

      items.push({
        name: item.name, type: item.type, thumb: item.thumb, path: item.path,
        weId: item.weId, videoFile: item.videoFile, videoPrev: item.videoPrev || "", mtime: item.mtime,
        hue: hue, saturation: saturation,
        richness: (item.richness != null ? item.richness : 0),
        applyCount: (item.applyCount != null ? item.applyCount : 0),
        placeholder: !!item.placeholder
      })
    }

    if (sortMode === "date") {
      items.sort(function(a, b) { return b.mtime - a.mtime })
    } else if (sortMode === "pop") {
      items.sort(function(a, b) {
        var popA = a.saturation - a.richness / 15
        var popB = b.saturation - b.richness / 15
        return popB - popA
      })
    } else if (sortMode === "richness") {
      items.sort(function(a, b) {
        if (a.richness !== b.richness) return b.richness - a.richness
        return b.saturation - a.saturation
      })
    } else if (sortMode === "minimalist") {
      items.sort(function(a, b) {
        if (a.richness !== b.richness) return a.richness - b.richness
        return b.saturation - a.saturation
      })
    } else if (sortMode === "applied") {
      items.sort(function(a, b) {
        if (a.applyCount !== b.applyCount) return b.applyCount - a.applyCount
        return b.mtime - a.mtime
      })
    } else {
      items.sort(function(a, b) {
        var hueA = a.hue === 99 ? 100 : a.hue
        var hueB = b.hue === 99 ? 100 : b.hue
        if (hueA !== hueB) return hueA - hueB
        return b.saturation - a.saturation
      })
    }

    _pendingItems = items
    requestFilterUpdate()
  }

  signal requestFilterUpdate()
  property var _pendingItems: []
  property bool filterTransitioning: false
  property bool _skipCrossfade: false

  function commitFilteredModel() {
    filteredModel.clear()
    if (_pendingItems.length > 0) filteredModel.append(_pendingItems)
    _pendingItems = []
    modelUpdated()
  }

  onSelectedColorFilterChanged: updateFilteredModel()
  onSelectedTypeFilterChanged: updateFilteredModel()
  onSelectedFolderChanged: updateFilteredModel()

  function _collectNeighbors(path) {
    var n = filteredModel.count
    if (n === 0) return []
    var idx = -1
    for (var i = 0; i < n; i++) {
      if (filteredModel.get(i).path === path) { idx = i; break }
    }
    if (idx < 0) return []
    var picks = []
    var maxNeighbors = 20
    for (var step = 1; picks.length < maxNeighbors && step < n; step++) {
      var fwd = idx + step
      var back = idx - step
      if (fwd < n) {
        var fp = filteredModel.get(fwd).path
        if (fp && fp !== path) picks.push(fp)
        if (picks.length >= maxNeighbors) break
      }
      if (back >= 0) {
        var bp = filteredModel.get(back).path
        if (bp && bp !== path) picks.push(bp)
      }
    }
    return picks
  }

  function applyStatic(path, outputs) {
    var neighbors = _collectNeighbors(path)
    var screens = Quickshell.screens.map(function(s) { return s.name })
    DaemonClient.applyStatic(path, outputs, neighbors, screens, function(result, error) {
      service._handleApplyResult(result, error)
    })
  }

  function applyBackdrop(path) {
    var p = path || ""
    Config.saveKey("niri.backdrop", p)
    DaemonClient.call("wall.backdrop", { "path": p }, function() {})
  }


  function applyWE(id, outputs, audioMap, volumeMap) {
    var screens = (outputs && outputs.length > 0)
      ? outputs
      : Quickshell.screens.map(function(s) { return s.name })
    DaemonClient.applyWE(id, screens, audioMap, volumeMap, function(result, error) {
      service._handleApplyResult(result, error)
    })
  }

  function applyVideo(path, outputs, audioMap, volumeMap) {
    var neighbors = _collectNeighbors(path)
    var screens = Quickshell.screens.map(function(s) { return s.name })
    DaemonClient.applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap, function(result, error) {
      service._handleApplyResult(result, error)
    })
  }

  function deleteWallpaperItem(type, name, weId) {
    for (var i = filteredModel.count - 1; i >= 0; i--) {
      var fi = filteredModel.get(i)
      if (fi.name === name && (fi.weId || "") === (weId || "")) {
        filteredModel.remove(i)
        break
      }
    }

    for (var j = _wallpaperData.length - 1; j >= 0; j--) {
      var wi = _wallpaperData[j]
      if (wi.name === name && (wi.weId || "") === (weId || "")) {
        _wallpaperData.splice(j, 1)
        _wallpaperData = _wallpaperData
        break
      }
    }

    DaemonClient.deleteItem(name, type, weId || "")
  }

  function openSteamPage(weId) {
    _unsubscribeWE.command = ["xdg-open", "steam://url/CommunityFilePage/" + weId]
    _unsubscribeWE.running = true
  }

  function clearData() {
    cacheReady = false
    cacheResult = ""
    _wallpaperData = []
    _wallpaperDataKeys = {}
    updateFilteredModel()
    DaemonClient.clearData()
  }

  property var _clearCache: Process {
    id: clearCache
    command: ["bash", "-c", "true"]
    onExited: {
      service.cacheReady = false
      service._wallpaperData = []
    }
  }

  property var _unsubscribeWE: Process { command: ["bash", "-c", "true"] }

  property var _optimizeConn: Connections {
    target: ImageOptimizeService
    function onFinished(optimized, skipped, failed) {
      if (optimized > 0)
        service.refreshFromDb()
    }
  }

  property var _videoConvertConn: Connections {
    target: VideoConvertService
  }
}
