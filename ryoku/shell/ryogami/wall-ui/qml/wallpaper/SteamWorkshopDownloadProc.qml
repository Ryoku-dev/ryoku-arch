import Quickshell.Io
import QtQuick
import Ryoku.Ui.Singletons

Process {
  id: dlProc

  property var workshopIds: []
  property string steamDir: ""
  property string steamUsername: ""
  property var expectedSizes: ({})

  signal progressUpdate(string id, real pct)
  signal itemDone(string id, bool success)
  signal batchDone(bool success)
  signal statusMessage(string id, string msg)
  signal credentialError(string id)

  property string currentId: workshopIds.length > 0 ? workshopIds[0] : ""
  property bool _credentialError: false
  property bool _downloading: false
  property var _doneIds: ({})

  readonly property string _login: steamUsername || "anonymous"
  readonly property string _steamBase: steamDir || (Qt.resolvedUrl("").replace("file://", "") + "/../.local/share/Steam")
  readonly property string _dlPath: _steamBase + "/steamapps/workshop/downloads/431960/" + currentId
  readonly property string _contentPath: _steamBase + "/steamapps/workshop/content/431960/" + currentId
  readonly property real _currentExpectedSize: currentId ? (expectedSizes[currentId] || 0) : 0

  property var _sizePoller: Timer {
    interval: 800
    repeat: true
    running: dlProc._downloading && dlProc.currentId !== "" && dlProc._currentExpectedSize > 0
    onTriggered: dlProc._pollSize()
  }

  property string _pollOutput: ""
  property var _pollProc: Process {
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => { dlProc._pollOutput += data }
    }
    onExited: function(exitCode) {
      var bytes = parseInt(dlProc._pollOutput.trim())
      var expected = dlProc._currentExpectedSize
      if (bytes > 0 && expected > 0) {
        var pct = Math.min(bytes / expected, 0.99)
        dlProc.progressUpdate(dlProc.currentId, pct)
        var mb = (bytes / 1048576).toFixed(1)
        var totalMb = (expected / 1048576).toFixed(1)
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Downloading %1 / %2 MB (%3%)").arg(mb).arg(totalMb).arg(Math.round(pct * 100)))
      }
    }
  }

  function _pollSize() {
    _pollOutput = ""
    _pollProc.command = ["bash", "-c",
      "(du -sb " + JSON.stringify(_dlPath) + " 2>/dev/null || du -sb " + JSON.stringify(_contentPath) + " 2>/dev/null || echo '0\tx')"
      + " | awk '{print $1}'"
    ]
    _pollProc.running = true
  }

  function buildCommand() {
    var cmd = ["steamcmd"]
    if (steamDir) cmd.push("+force_install_dir", steamDir)
    cmd.push("+login", _login)
    for (var i = 0; i < workshopIds.length; i++)
      cmd.push("+workshop_download_item", "431960", workshopIds[i])
    cmd.push("+quit")
    return cmd
  }

  function _markItemDone(id, success) {
    if (_doneIds[id]) return
    _doneIds[id] = true
    _downloading = false
    if (success) {
      progressUpdate(id, 1.0)
      statusMessage(id, I18n.tr("Download complete"))
    }
    itemDone(id, success)
    _advanceToNext()
  }

  function _advanceToNext() {
    for (var i = 0; i < workshopIds.length; i++) {
      if (!_doneIds[workshopIds[i]]) {
        currentId = workshopIds[i]
        return
      }
    }
  }

  stderr: SplitParser {
    splitMarker: "\n"
    onRead: data => {
      console.log("[Steam DL batch stderr] " + data)
      if (!dlProc.currentId) return
      var match = data.match(/(\d+)\s*\/\s*(\d+)\s*bytes/)
      if (match) {
        var got = parseInt(match[1])
        var total = parseInt(match[2])
        if (total > 0) dlProc.progressUpdate(dlProc.currentId, got / total)
      }
      var pctMatch = data.match(/(\d+(?:\.\d+)?)\s*%/)
      if (pctMatch) {
        dlProc.progressUpdate(dlProc.currentId, parseFloat(pctMatch[1]) / 100.0)
      }
    }
  }

  stdout: SplitParser {
    splitMarker: "\n"
    onRead: data => {
      console.log("[Steam DL batch] " + data)

      if (data.indexOf("Downloading item") >= 0) {
        var nums = data.match(/\d{7,}/g)
        if (nums) {
          for (var i = nums.length - 1; i >= 0; i--) {
            if (dlProc.workshopIds.indexOf(nums[i]) >= 0 && !dlProc._doneIds[nums[i]]) {
              dlProc.currentId = nums[i]
              dlProc._downloading = true
              dlProc.statusMessage(nums[i], I18n.tr("Downloading workshop item..."))
              break
            }
          }
        }
        if (!nums || !dlProc._downloading) {
          dlProc._downloading = true
          dlProc.statusMessage(dlProc.currentId, I18n.tr("Downloading workshop item..."))
        }
      }

      if (data.indexOf("Success") >= 0 || data.indexOf("fully installed") >= 0) {
        var successId = dlProc.currentId
        var sNums = data.match(/\d{7,}/g)
        if (sNums) {
          for (var j = sNums.length - 1; j >= 0; j--) {
            if (dlProc.workshopIds.indexOf(sNums[j]) >= 0) {
              successId = sNums[j]
              break
            }
          }
        }
        if (successId) dlProc._markItemDone(successId, true)
      }
      else {
        var match = data.match(/(\d+(?:\.\d+)?)\s*%/)
        if (match && dlProc.currentId) {
          var pct = parseFloat(match[1]) / 100.0
          dlProc.progressUpdate(dlProc.currentId, pct)
          dlProc.statusMessage(dlProc.currentId, I18n.tr("Downloading %1%").arg(Math.round(pct * 100)))
        }
      }

      if (data.indexOf("Cached credentials not found") >= 0 || data.indexOf("Login Failure") >= 0) {
        dlProc._credentialError = true
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Steam login required. Run: steamcmd +login %1 +quit").arg(dlProc._login))
        dlProc.credentialError(dlProc.currentId)
      }

      if (data.indexOf("Checking for available update") >= 0)
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Checking for updates..."))
      else if (data.indexOf("Verifying installation") >= 0)
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Verifying installation..."))
      else if (data.indexOf("Loading Steam API") >= 0)
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Connecting to Steam..."))
      else if (data.indexOf("Logging in") >= 0 || data.indexOf("Waiting for user info") >= 0)
        dlProc.statusMessage(dlProc.currentId, I18n.tr("Logging in... Program isn't frozen this takes time!"))
    }
  }

  onExited: function(exitCode, exitStatus) {
    console.log("[Steam DL batch] exited code " + exitCode + ", " + Object.keys(_doneIds).length + "/" + workshopIds.length + " completed")
    dlProc.batchDone(exitCode === 0)
  }
}
