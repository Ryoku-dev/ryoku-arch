import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../services"
import Ryoku.Ui.Singletons
QtObject {
  id: swService

  required property string weDir
  property string query: ""
  property string sorting: "trend"
  property int trendDays: 7
  property string requiredTag: ""
  property string requiredResolution: ""
  property string requiredType: "Video"
  property bool nsfwEnabled: false
  readonly property var _nsfwTags: ["Mature", "Questionable", "NSFW", "Partial Nudity", "Nudity", "Gore"]
  property var excludedTags: nsfwEnabled ? [] : _nsfwTags
  property int currentPage: 1
  property int lastPage: 1
  property string apiKey: ""
  property int numPerPage: 24

  property var results: []
  property bool loading: false
  property string errorText: ""
  property bool hasMore: currentPage < lastPage
  property bool daemonBrowserAvailable: false

  property var downloadStatus: ({})
  property var downloadProgress: ({})
  property string activeDownloadId: ""
  property string activeDownloadMessage: ""
  property int downloadQueueLength: 0
  property bool authPaused: false
  property int authFailedCount: 0
  property var localWorkshopIds: ({})

  readonly property int _appId: 431960

  signal resultsUpdated()
  signal downloadFinished(string workshopId)

  readonly property string _requestFilePath: Config.cacheDir + "/wallpaper/steam-dl-request"
  property var _requestWriter: FileView { id: requestWriter }

  function downloadWorkshop(workshopId, fileSize) {
    if (!workshopId) {
      console.log("[SteamWorkshopService] downloadWorkshop blocked: no workshopId")
      return
    }
    var safeId = workshopId.toString().replace(/[^0-9]/g, "")
    if (!safeId) return
    var sz = parseInt(fileSize) || 0
    console.log("[SteamWorkshopService] requesting download " + safeId + " size=" + sz)

    var updated = Object.assign({}, downloadStatus)
    updated[safeId] = "queued"
    downloadStatus = updated
    downloadQueueLength = downloadQueueLength + 1
    requestWriter.path = _requestFilePath
    requestWriter.setText(safeId + "\n" + sz)
    DaemonClient.call("steam.download", {"id": safeId}, function(resp) {
      if (resp && resp.error)
        console.log("[SteamWorkshopService] download request failed: " + resp.error)
    })
  }

  function retryDownloads() {
    DaemonClient.call("steam.retry", {}, function(resp) {
      if (resp && resp.error)
        console.log("[SteamWorkshopService] retry failed: " + resp.error)
    })
  }

  readonly property string _statusFilePath: Config.cacheDir + "/wallpaper/steam-dl-status.json"

  property var _statusFileView: FileView {
    path: swService._statusFilePath
    watchChanges: true
    onLoaded: swService._parseStatusFile()
    onFileChanged: { reload(); swService._parseStatusFile() }
  }

  property string _statusRaw: ""

  function refreshDownloadStatus() {
    if (_statusFileView.path)
      _statusFileView.reload()
  }

  function _parseStatusFile() {
    swService._statusRaw = _statusFileView.text() || ""
    if (!swService._statusRaw) return
    try {
      var obj = JSON.parse(swService._statusRaw)
      var newStatus = {}
      var newProgress = {}
      var downloads = obj.downloads || {}
      var ids = Object.keys(downloads)
      for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        newStatus[id] = downloads[id].status || ""
        newProgress[id] = downloads[id].progress || 0
        if (downloads[id].status === "done" && !localWorkshopIds[id]) {
          var loc = Object.assign({}, localWorkshopIds)
          loc[id] = true
          localWorkshopIds = loc
          downloadFinished(id)
        }
      }
      downloadStatus = newStatus
      downloadProgress = newProgress
      activeDownloadId = obj.activeId || ""
      activeDownloadMessage = obj.activeMessage || ""
      downloadQueueLength = obj.queueLength || 0
      authPaused = obj.authPaused || false
      authFailedCount = obj.authFailedCount || 0
    } catch (e) {
    }
  }

  function scanLocalDirs() {
    _localScanOutput = ""
    if (!weDir) return
    _localScanProc.running = true
  }

  property string _localScanOutput: ""
  property var _localScanProc: Process {
    command: ["find", swService.weDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\n"]
    stdout: SplitParser {
      onRead: data => { swService._localScanOutput += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      var ids = {}
      var lines = swService._localScanOutput.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var id = lines[i].trim()
        if (id && /^\d+$/.test(id)) ids[id] = true
      }
      swService.localWorkshopIds = ids
    }
  }

  Component.onCompleted: {
    DaemonClient.call("steam.browser_status", {}, function(result, err) {
      if (!err && result && result.available === true) {
        swService.daemonBrowserAvailable = true
      }
    })
  }

  function search(page) {
    if (loading) return
    currentPage = page || 1
    if (currentPage === 1) results = []
    loading = true
    errorText = ""

    if (Config.steamBackend === "steam") {
      var sortKey = sorting === "trend" ? "trend"
                  : sorting === "new" ? "recent"
                  : sorting === "toprated" ? "votes"
                  : sorting === "popular" ? "subs"
                  : sorting === "favorited" ? "favorites"
                  : "trend"

      var required = []
      if (requiredType) required.push(requiredType)
      if (requiredTag) required.push(requiredTag)
      if (requiredResolution) required.push(requiredResolution)

      var params = {
        page: currentPage,
        query: query,
        sort: sortKey,
        required_tags: required,
        excluded_tags: excludedTags,
        match_any_required: false
      }
      if (sortKey === "trend") params.trend_days = trendDays

      DaemonClient.call("steam.search", params, function(result, err) {
        swService.loading = false
        if (err || !result || !result.items) {
          swService.errorText = (err && err.message) ? I18n.tr("Workshop browse failed: %1").arg(err.message) : I18n.tr("Workshop browse failed")
          swService.resultsUpdated()
          return
        }
        var mapped = result.items.map(function(it) {
          return {
            id: it.id || "",
            title: it.title || I18n.tr("Untitled"),
            description: (it.description || "").substring(0, 120),
            previewUrl: it.preview_url || "",
            subscriptions: it.subscriptions || 0,
            favorited: it.favorites || 0,
            fileSize: it.file_size || 0,
            tags: it.tags || [],
            creator: it.creator || ""
          }
        })
        swService.results = mapped
        swService.lastPage = mapped.length >= swService.numPerPage ? currentPage + 1 : currentPage
        swService.resultsUpdated()
      })
      return
    }

    if (!apiKey) {
      loading = false
      errorText = I18n.tr("Workshop browsing needs Steam to be running, OR a Steam API key. Open Steam, OR set a key in Settings → Steam → API key. (Downloads work without either if you already have a Workshop ID.)")
      resultsUpdated()
      return
    }
    _searchOutput = ""
    _searchProcess.command = ["curl", "-sSL", "--globoff", _buildUrl()]
    _searchProcess.running = true
  }

  function loadMore() {
    if (loading || !hasMore) return
    search(currentPage + 1)
  }

  function clearCache() {
    results = []
    currentPage = 1
    lastPage = 1
    errorText = ""
  }

  function nextPage() {
    loadMore()
  }
  function prevPage() {
    if (loading || currentPage <= 1) return
    search(currentPage - 1)
  }

  function _buildUrl() {
    var url = "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?"
    var params = []
    params.push("key=" + encodeURIComponent(apiKey))
    params.push("appid=" + _appId)
    params.push("return_previews=true")
    params.push("return_tags=true")
    params.push("return_metadata=true")
    params.push("numperpage=" + numPerPage)
    params.push("page=" + currentPage)

    var queryType = 3
    if (sorting === "trend") queryType = 3
    else if (sorting === "new") queryType = 1
    else if (sorting === "toprated") queryType = 0
    else if (sorting === "popular") queryType = 9
    else if (sorting === "favorited") queryType = 11

    if (query) queryType = 12
    params.push("query_type=" + queryType)

    if (sorting === "trend" && !query)
      params.push("days=" + trendDays)

    if (query) params.push("search_text=" + encodeURIComponent(query))
    var tagIdx = 0
    if (requiredType) { params.push("requiredtags[" + tagIdx + "]=" + encodeURIComponent(requiredType)); tagIdx++ }
    if (requiredTag) { params.push("requiredtags[" + tagIdx + "]=" + encodeURIComponent(requiredTag)); tagIdx++ }
    if (requiredResolution) { params.push("requiredtags[" + tagIdx + "]=" + encodeURIComponent(requiredResolution)); tagIdx++ }

    for (var e = 0; e < excludedTags.length; e++) {
      params.push("excludedtags[" + e + "]=" + encodeURIComponent(excludedTags[e]))
    }

    return url + params.join("&")
  }

  property string _searchOutput: ""

  property var _searchProcess: Process {
    command: ["curl", "-fsSL", "about:blank"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => { swService._searchOutput += data }
    }
    onRunningChanged: {
      if (running) swService._searchOutput = ""
    }
    onExited: function(exitCode, exitStatus) {
      swService.loading = false
      if (exitCode !== 0) {
        swService.errorText = I18n.tr("Network error (curl exit %1)").arg(exitCode)
        swService.results = []
        swService.resultsUpdated()
        return
      }
      try {
        var json = JSON.parse(swService._searchOutput)
        var response = json.response || {}
        var total = response.total || 0
        var items = response.publishedfiledetails || []

        var newItems = items.map(function(item) {
          var previewUrl = item.preview_url || ""
          if (item.previews && item.previews.length > 0) {
            for (var p = 0; p < item.previews.length; p++) {
              if (item.previews[p].url) {
                previewUrl = item.previews[p].url
                break
              }
            }
          }

          var tags = []
          if (item.tags) {
            for (var t = 0; t < item.tags.length; t++) {
              if (item.tags[t].display_name) tags.push(item.tags[t].display_name)
              else if (item.tags[t].tag) tags.push(item.tags[t].tag)
            }
          }

          return {
            id: item.publishedfileid || "",
            title: item.title || I18n.tr("Untitled"),
            description: (item.short_description || item.file_description || "").substring(0, 120),
            previewUrl: previewUrl,
            subscriptions: item.subscriptions || 0,
            favorited: item.favorited || 0,
            fileSize: item.file_size ? parseInt(item.file_size) : 0,
            tags: tags,
            creator: item.creator || ""
          }
        })

        swService.results = newItems
        swService.lastPage = Math.max(1, Math.ceil(total / swService.numPerPage))
        swService.errorText = ""
      } catch (e) {
        swService.errorText = I18n.tr("Parse error: %1").arg(e.message)
        swService.results = []
      }
      swService.resultsUpdated()
      swService.scanLocalDirs()
    }
  }
}
