pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import Ryoku.Ui.Singletons

QtObject {
  id: svc

  readonly property string _statusFilePath: Config.cacheDir + "/wallpaper/steam-dl-status.json"

  property var downloadStatus: ({})
  property var downloadProgress: ({})
  property string activeId: ""
  property string activeMessage: ""
  property int queueLength: 0
  property bool authPaused: false
  property var _failedAuth: []

  signal stateChanged()
  signal downloadFinished(string workshopId)

  Component.onCompleted: _recoverQueue()

  property string _recoverOutput: ""
  property var _recoverProc: Process {
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => { svc._recoverOutput += data }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !svc._recoverOutput.trim()) return
      try {
        var obj = JSON.parse(svc._recoverOutput)
        var downloads = obj.downloads || {}
        var ids = Object.keys(downloads)
        var toQueue = []
        for (var i = 0; i < ids.length; i++) {
          var st = downloads[ids[i]].status
          if (st === "queued" || st === "downloading" || st === "auth_error")
            toQueue.push(ids[i])
        }
        if (toQueue.length > 0) {
          console.log("[SteamDownloadService] recovering " + toQueue.length + " incomplete downloads from status file")
          for (var j = 0; j < toQueue.length; j++)
            svc.requestDownload(toQueue[j])
        }
      } catch (e) {
        console.log("[SteamDownloadService] recovery parse error: " + e.message)
      }
    }
  }

  function _recoverQueue() {
    _recoverOutput = ""
    _recoverProc.command = ["cat", _statusFilePath]
    _recoverProc.running = true
  }

  readonly property string _requestFilePath: Config.cacheDir + "/wallpaper/steam-dl-request"

  property string _readResult: ""

  property var _requestReadProc: Process {
    id: readProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => { svc._readResult += data }
    }
    onExited: function(exitCode, exitStatus) {
      var id = svc._readResult.trim().split("\n")[0] || ""
      console.log("[SteamDownloadService] pickUpRequest read id=" + JSON.stringify(id))
      svc._handleRequestData()
    }
  }

  function pickUpRequest() {
    _readResult = ""
    readProc.command = ["cat", _requestFilePath]
    readProc.running = true
  }

  property var _pendingSizes: ({})

  function _handleRequestData() {
    var lines = _readResult.trim().split("\n")
    var id = (lines[0] || "").trim()
    var sz = parseInt(lines[1]) || 0
    console.log("[SteamDownloadService] pickUpRequest read id=" + JSON.stringify(id) + " size=" + sz)
    if (id) {
      if (sz > 0) _pendingSizes[id] = sz
      requestDownload(id)
    }
  }

  function requestDownload(workshopId) {
    if (!workshopId) return
    var safeId = workshopId.toString().replace(/[^0-9]/g, "")
    if (!safeId || _activeDownloads[safeId]) return
    console.log("[SteamDownloadService] queuing download: " + safeId)

    var status = Object.assign({}, downloadStatus)
    status[safeId] = "queued"
    downloadStatus = status
    _activeDownloads[safeId] = true
    _downloadQueue.push(safeId)
    queueLength = _downloadQueue.length + _batchRemaining
    _writeStatus()
    _drainDownloadQueue()
  }

  property var _activeDownloads: ({})
  property var _downloadQueue: []
  property bool _batchRunning: false
  property int _batchRemaining: 0

  function retryAuthFailed() {
    if (_failedAuth.length === 0) return
    console.log("[SteamDownloadService] retrying " + _failedAuth.length + " auth-failed downloads")
    authPaused = false
    var ids = _failedAuth.slice()
    _failedAuth = []
    for (var i = 0; i < ids.length; i++) {
      var st = Object.assign({}, downloadStatus)
      st[ids[i]] = "queued"
      downloadStatus = st
      _activeDownloads[ids[i]] = true
      _downloadQueue.push(ids[i])
    }
    queueLength = _downloadQueue.length + _batchRemaining
    _writeStatus()
    _drainDownloadQueue()
  }

  function _drainDownloadQueue() {
    if (_batchRunning || _downloadQueue.length === 0) return
    var batch = _downloadQueue.slice()
    _downloadQueue = []
    _spawnBatch(batch)
  }

  function _spawnBatch(ids) {
    _batchRunning = true
    _batchRemaining = ids.length
    activeId = ids[0]
    activeMessage = I18n.tr("Starting steamcmd...")
    var s = Object.assign({}, downloadStatus)
    s[ids[0]] = "downloading"
    downloadStatus = s
    queueLength = ids.length + _downloadQueue.length
    _writeStatus()

    console.log("[SteamDownloadService] spawning batch of " + ids.length + " items: " + ids.join(", "))

    var comp = Qt.createComponent("../wallpaper/SteamWorkshopDownloadProc.qml")
    var sizes = {}
    for (var j = 0; j < ids.length; j++) {
      if (svc._pendingSizes[ids[j]]) {
        sizes[ids[j]] = svc._pendingSizes[ids[j]]
        delete svc._pendingSizes[ids[j]]
      }
    }
    var proc = comp.createObject(svc, {
      workshopIds: ids,
      steamDir: Config.weDir.replace(/\/steamapps\/workshop\/content\/431960\/?$/, ""),
      steamUsername: Config.steamUsername,
      expectedSizes: sizes
    })
    proc.command = proc.buildCommand()

    proc.onProgressUpdate.connect(function(id, pct) {
      var p = Object.assign({}, downloadProgress)
      p[id] = pct
      downloadProgress = p
      activeMessage = I18n.tr("Downloading %1%").arg(Math.round(pct * 100))
      _writeStatus()
    })
    proc.onStatusMessage.connect(function(id, msg) {
      activeId = id
      activeMessage = msg
      if (downloadStatus[id] === "queued") {
        var st = Object.assign({}, downloadStatus)
        st[id] = "downloading"
        downloadStatus = st
      }
      _writeStatus()
    })
    proc.onCredentialError.connect(function(id) {
      console.log("[SteamDownloadService] credential error, pausing queue")
      svc.authPaused = true
    })
    proc.onItemDone.connect(function(id, success) {
      _batchRemaining--
      var st = Object.assign({}, downloadStatus)
      if (success) {
        st[id] = "done"
        if (svc.authPaused) {
          svc.authPaused = false
          svc._failedAuth = []
        }
      } else {
        st[id] = "error"
      }
      downloadStatus = st
      delete _activeDownloads[id]
      downloadFinished(id)
      queueLength = _downloadQueue.length + _batchRemaining
      var nextId = proc.currentId
      if (nextId && nextId !== id && _batchRemaining > 0) {
        activeId = nextId
        activeMessage = I18n.tr("Downloading workshop item...")
        var st2 = Object.assign({}, downloadStatus)
        st2[nextId] = "downloading"
        downloadStatus = st2
      }
      _writeStatus()
    })
    proc.onBatchDone.connect(function(success) {
      for (var k = 0; k < ids.length; k++) {
        var sid = ids[k]
        if (downloadStatus[sid] === "downloading" || downloadStatus[sid] === "queued") {
          var st = Object.assign({}, downloadStatus)
          if (svc.authPaused) {
            st[sid] = "auth_error"
            _failedAuth.push(sid)
          } else {
            st[sid] = "error"
          }
          downloadStatus = st
          delete _activeDownloads[sid]
        }
      }
      _batchRunning = false
      _batchRemaining = 0
      proc.destroy()

      if (svc.authPaused) {
        while (_downloadQueue.length > 0) {
          var qid = _downloadQueue.shift()
          var s2 = Object.assign({}, downloadStatus)
          s2[qid] = "auth_error"
          downloadStatus = s2
          _failedAuth.push(qid)
          delete _activeDownloads[qid]
        }
        queueLength = 0
        _writeStatus()
      } else if (_downloadQueue.length > 0) {
        _drainDownloadQueue()
      } else {
        activeId = ""
        activeMessage = ""
        queueLength = 0
        _writeStatus()
      }
    })
    proc.running = true
  }

  property var _statusFileView: FileView { id: statusFile }

  function _writeStatus() {
    var obj = {
      downloads: {},
      activeId: activeId,
      activeMessage: activeMessage,
      queueLength: queueLength,
      authPaused: authPaused,
      authFailedCount: _failedAuth.length
    }
    var ids = Object.keys(downloadStatus)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      obj.downloads[id] = {
        status: downloadStatus[id] || "",
        progress: downloadProgress[id] || 0
      }
    }
    statusFile.path = _statusFilePath
    statusFile.setText(JSON.stringify(obj))
    svc.stateChanged()
  }
}
