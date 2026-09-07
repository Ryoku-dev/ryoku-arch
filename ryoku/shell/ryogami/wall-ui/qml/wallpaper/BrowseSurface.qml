import QtQuick
import QtQuick.Effects
import ".."
import "../components"
import "../services"
import Ryoku.Ui.Singletons

// One Browse surface for every remote source. The active source's browser fills
// the width; a SOURCES button opens a slide-out drawer that switches source and
// holds that source's keys & setup (API keys, grid), so sources and their config
// live in one place instead of scattered across browser buttons and settings tabs.
Item {
  id: root
  clip: true

  property var colors
  property var whService
  property var swService
  property bool browserVisible: false
  property string source: "wallhaven"     // active source key
  property bool drawerOpen: false

  signal escapePressed()

  function _saveField(key, value) {
    if (!Config._data.components || typeof Config._data.components.wallpaperSelector !== "object" || Config._data.components.wallpaperSelector === null)
      Config.saveKey("components.wallpaperSelector.enabled", true)
    Config.saveKey("components.wallpaperSelector." + key, value)
  }
  function _saveConfigKey(path, value) { Config.saveKey(path, value) }

  // ryowalls-shaped remote sources (scrape-based, no keys): one generic
  // LibraryBrowser serves them all, keyed off these descriptors.
  readonly property var _libDefs: ({
    "moewalls":  { label: "MOEWALLS",  kana: "萌", search: "moewalls-search",  download: "moewalls-download",  post: true },
    "motionbgs": { label: "MOTIONBGS", kana: "動", search: "motionbgs-search", download: "motionbgs-download", post: false },
    "ryostore":  { label: "RYOSTORE",  kana: "蔵", search: "extras-search",     download: "extras-download",     post: false },
    "repos":     { label: "REPOS",     kana: "庫", search: "library-list",      download: "library-download",    post: false }
  })
  readonly property bool _isLib: _libDefs[source] !== undefined

  readonly property var _sources: {
    var s = []
    if (Config.wallhavenEnabled) s.push({ key: "wallhaven", label: "WALLHAVEN" })
    if (Config.steamEnabled) s.push({ key: "steam", label: "STEAM" })
    s.push({ key: "moewalls", label: "MOEWALLS" })
    s.push({ key: "motionbgs", label: "MOTIONBGS" })
    s.push({ key: "ryostore", label: "RYOSTORE" })
    s.push({ key: "repos", label: "REPOS" })
    return s
  }
  readonly property string _activeLabel: {
    for (var i = 0; i < _sources.length; i++) if (_sources[i].key === source) return _sources[i].label
    return I18n.tr("SOURCES")
  }
  function _validSource(k) {
    for (var i = 0; i < _sources.length; i++) if (_sources[i].key === k) return true
    return false
  }
  property var repos: []
  property string activeRepo: ""
  function _loadRepos() {
    var r = (Config._data.sources && Config._data.sources.repos) || []
    repos = r.slice()
    if (activeRepo === "" && repos.length > 0) activeRepo = repos[0]
  }
  function _addRepo(raw) {
    var v = ("" + raw).trim().replace(/^https?:\/\/github\.com\//, "").replace(/\.git$/, "").replace(/\/+$/, "")
    if (!v || v.indexOf("/") < 0) return
    if (repos.indexOf(v) < 0) { var n = repos.slice(); n.push(v); repos = n; Config.saveKey("sources.repos", n) }
    activeRepo = v
  }
  function _removeRepo(v) {
    var n = repos.filter(function(x) { return x !== v }); repos = n; Config.saveKey("sources.repos", n)
    if (activeRepo === v) activeRepo = n.length > 0 ? n[0] : ""
  }
  Component.onCompleted: {
    _loadRepos()
    if (_sources.length > 0 && !_validSource(source)) source = _sources[0].key
  }

  visible: browserVisible
  opacity: browserVisible ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }

  readonly property var _activeItem: {
    if (source === "wallhaven") return whLoader.item
    if (source === "steam") return swLoader.item
    return libLoader.item
  }
  readonly property bool _searchable: !_isLib || source !== "repos" || activeRepo !== ""
  readonly property string _searchHint: {
    if (source === "wallhaven") return I18n.tr("SEARCH %1…").arg("WALLHAVEN")
    if (source === "steam") return I18n.tr("SEARCH %1…").arg("STEAM WORKSHOP")
    var d = _libDefs[source]
    return d ? I18n.tr("SEARCH %1…").arg(d.label) : I18n.tr("SEARCH…")
  }
  readonly property real _barHeight: 84 * Config.uiScale
  function _runSearch(q) {
    if (!_searchable) return
    if (_activeItem && _activeItem.runSearch) _activeItem.runSearch(q)
  }

  // ---- active source's browser, filling the area below the shared bar ----
  Loader {
    id: whLoader
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    anchors.top: topBar.bottom; anchors.topMargin: 8
    active: root.source === "wallhaven"
    visible: active
    sourceComponent: Component {
      WallhavenBrowser {
        colors: root.colors
        whService: root.whService
        browserVisible: true
        onEscapePressed: root.escapePressed()
      }
    }
  }

  Loader {
    id: swLoader
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    anchors.top: topBar.bottom; anchors.topMargin: 8
    active: root.source === "steam"
    visible: active
    sourceComponent: Component {
      SteamWorkshopBrowser {
        colors: root.colors
        swService: root.swService
        browserVisible: true
        onEscapePressed: root.escapePressed()
      }
    }
  }

  Loader {
    id: libLoader
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    anchors.top: topBar.bottom; anchors.topMargin: 8
    active: root._isLib
    visible: active
    sourceComponent: Component {
      LibraryBrowser {
        colors: root.colors
        browserVisible: true
        sourceName: root._libDefs[root.source] ? root._libDefs[root.source].label : ""
        kana: root._libDefs[root.source] ? root._libDefs[root.source].kana : ""
        searchVerb: root._libDefs[root.source] ? root._libDefs[root.source].search : ""
        downloadVerb: root._libDefs[root.source] ? root._libDefs[root.source].download : ""
        needsPost: root._libDefs[root.source] ? root._libDefs[root.source].post : false
        extraArgs: root.source === "repos" && root.activeRepo !== "" ? ["--repo", root.activeRepo] : []
        searchable: root.source !== "repos" || root.activeRepo !== ""
        idleHint: I18n.tr("Add a GitHub repo in the Sources drawer (owner/repo).")
        onEscapePressed: root.escapePressed()
      }
    }
  }

  // ---- one fixed, opaque paper bar shared by every source; only the middle
  // filter region swaps when the source changes, so the bar never moves ----
  Item {
    id: topBar
    z: 30
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: root._barHeight

    Rectangle {
      anchors.fill: parent
      z: -1
      radius: Style.radiusRound
      color: root.colors ? Qt.rgba(root.colors.surface.r, root.colors.surface.g, root.colors.surface.b, 0.9) : Qt.rgba(0.06, 0.07, 0.09, 0.9)
      border.width: 1
      border.color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.22) : Qt.rgba(1, 1, 1, 0.15)
      layer.enabled: true
      layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowVerticalOffset: 3; shadowColor: Qt.rgba(0, 0, 0, 0.5) }
    }

    MouseArea { anchors.fill: parent }

    Row {
      id: barRow
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      FilterButton {
        anchors.verticalCenter: parent.verticalCenter
        colors: root.colors
        icon: "\u{f0141}"
        register: false
        skew: 8
        height: 26 * Config.uiScale
        tooltip: I18n.tr("Back to wallpapers")
        onClicked: root.escapePressed()
      }

      FilterButton {
        id: sourcesBtn
        anchors.verticalCenter: parent.verticalCenter
        colors: root.colors
        label: "源  " + root._activeLabel
        register: false
        skew: 8
        height: 26 * Config.uiScale
        isActive: root.drawerOpen
        tooltip: I18n.tr("Switch source · keys & setup")
        onClicked: root.drawerOpen = !root.drawerOpen
      }

      Rectangle {
        id: searchField
        anchors.verticalCenter: parent.verticalCenter
        width: 220 * Config.uiScale
        height: 24 * Config.uiScale
        radius: 0
        opacity: root._searchable ? 1 : 0.45
        color: root.colors ? Qt.rgba(root.colors.surface.r, root.colors.surface.g, root.colors.surface.b, 0.8) : Qt.rgba(0.15, 0.17, 0.22, 0.8)
        border.width: searchInput.activeFocus ? 2 : 1
        border.color: searchInput.activeFocus
            ? (root.colors ? root.colors.primary : Style.fallbackAccent)
            : (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.2) : Qt.rgba(1, 1, 1, 0.12))
        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.15, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

        TextInput {
          id: searchInput
          anchors.fill: parent; anchors.margins: 6 * Config.uiScale
          verticalAlignment: TextInput.AlignVCenter
          enabled: root._searchable
          font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
          color: root.colors ? root.colors.surfaceText : "#e0e0e0"
          clip: true; selectByMouse: true
          Keys.onReturnPressed: root._runSearch(text)
          Keys.onEnterPressed: root._runSearch(text)
          Keys.onEscapePressed: root.escapePressed()
        }
        Text {
          anchors.fill: parent; anchors.margins: 6 * Config.uiScale
          verticalAlignment: Text.AlignVCenter
          font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
          color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.35) : Qt.rgba(1, 1, 1, 0.3)
          text: root._searchHint
          font.letterSpacing: 0.5; font.weight: Font.Medium
          visible: !searchInput.text && !searchInput.activeFocus
        }
      }

      FilterButton {
        anchors.verticalCenter: parent.verticalCenter
        colors: root.colors
        label: I18n.tr("SEARCH")
        register: false
        skew: 8
        height: 26 * Config.uiScale
        onClicked: root._runSearch(searchInput.text)
      }

      Row {
        id: pageNav
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        visible: !!(root._activeItem && root._activeItem.pageActive)
        FilterButton {
          colors: root.colors
          label: "\u2039"
          register: false; skew: 8
          height: 26 * Config.uiScale
          activeOpacity: (root._activeItem && root._activeItem.pageCanPrev) ? 1 : 0.3
          tooltip: I18n.tr("Previous page")
          onClicked: if (root._activeItem) root._activeItem.pagePrev()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: I18n.tr("PAGE %1").arg(root._activeItem ? root._activeItem.pageNum : 1)
          font.family: Style.fontFamily; font.pixelSize: 10 * Config.uiScale
          font.weight: Font.Medium; font.letterSpacing: 1.2
          color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.7) : "#c2c7cf"
        }
        FilterButton {
          colors: root.colors
          label: "\u203a"
          register: false; skew: 8
          height: 26 * Config.uiScale
          activeOpacity: (root._activeItem && root._activeItem.pageCanNext) ? 1 : 0.3
          tooltip: I18n.tr("Next page")
          onClicked: if (root._activeItem) root._activeItem.pageNext()
        }
      }

      Loader {
        id: filterLoader
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: root._activeItem ? root._activeItem.filterBar : null
      }
    }
  }

  // ---- scrim ----
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    visible: root.drawerOpen || opacity > 0.01
    opacity: root.drawerOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.animNormal } }
    z: 40
    MouseArea { anchors.fill: parent; onClicked: root.drawerOpen = false }
  }

  // ---- sources & setup drawer ----
  Rectangle {
    id: drawer
    width: Math.min(520 * Config.uiScale, root.width - 40 * Config.uiScale)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    x: root.drawerOpen ? 0 : -width
    Behavior on x { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }
    z: 46
    clip: true
    color: root.colors ? Qt.rgba(root.colors.surface.r, root.colors.surface.g, root.colors.surface.b, 0.98) : Qt.rgba(0.06, 0.07, 0.09, 0.98)
    border.width: 1
    border.color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.16) : Qt.rgba(1, 1, 1, 0.12)

    MouseArea { anchors.fill: parent }

    Flickable {
      anchors.fill: parent
      anchors.margins: 22
      contentHeight: drawerCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: drawerCol
        width: parent.width
        spacing: Style.spacingXLarge

        Column {
          width: parent.width
          spacing: Style.spacingTiny
          Row {
            spacing: Style.spacingMedium
            Text {
              text: I18n.tr("SOURCES")
              font.family: Style.fontFamilyHeading
              font.pixelSize: 20 * Config.uiScale
              font.weight: Font.Medium
              color: root.colors ? root.colors.surfaceText : "#e0e2e8"
            }
            Text {
              text: "源"
              font.family: Style.fontFamilyJp
              font.pixelSize: 18 * Config.uiScale
              color: root.colors ? Qt.rgba(root.colors.surfaceVariantText.r, root.colors.surfaceVariantText.g, root.colors.surfaceVariantText.b, 0.6) : "#8a8f97"
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Text {
            text: I18n.tr("Pick where wallpapers come from.")
            font.family: Style.fontFamily
            font.pixelSize: 11 * Config.uiScale
            color: root.colors ? Qt.rgba(root.colors.surfaceVariantText.r, root.colors.surfaceVariantText.g, root.colors.surfaceVariantText.b, 0.7) : "#8a8f97"
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacingMedium
          Repeater {
            model: root._sources
            FilterButton {
              colors: root.colors
              label: I18n.tr(modelData.label)
              register: false
              skew: 8
              height: 28 * Config.uiScale
              isActive: root.source === modelData.key
              onClicked: { root.source = modelData.key; root.drawerOpen = false }
            }
          }
        }

        Rectangle {
          width: parent.width; height: 1
          color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.2) : Qt.rgba(1, 1, 1, 0.16)
        }

        Text {
          text: {
            var d = root._libDefs[root.source]
            if (d) return I18n.tr("%1 · NO KEYS NEEDED").arg(d.label)
            return I18n.tr("%1 · KEYS & SETUP").arg(root.source === "steam" ? "STEAM" : "WALLHAVEN")
          }
          font.family: Style.fontFamily
          font.pixelSize: 11 * Config.uiScale
          font.weight: Font.Medium
          font.letterSpacing: 1.2
          color: root.colors ? root.colors.surfaceVariantText : "#c2c7cf"
        }

        Text {
          visible: root._isLib
          width: parent.width
          wrapMode: Text.WordWrap
          text: I18n.tr("Scraped source. Browse and click to apply; downloads land in your video library.")
          font.family: Style.fontFamily
          font.pixelSize: 10 * Config.uiScale
          color: root.colors ? Qt.rgba(root.colors.surfaceVariantText.r, root.colors.surfaceVariantText.g, root.colors.surfaceVariantText.b, 0.7) : "#8a8f97"
        }

        Loader {
          width: parent.width
          active: root.source === "wallhaven"
          visible: active
          source: "settings/WallhavenSettings.qml"
          onLoaded: {
            item.colors = Qt.binding(function() { return root.colors })
            item.saveField = function(k, v) { root._saveField(k, v) }
            item.saveConfigKey = function(k, v) { root._saveConfigKey(k, v) }
          }
        }

        Loader {
          width: parent.width
          active: root.source === "steam"
          visible: active
          source: "settings/SteamSettings.qml"
          onLoaded: {
            item.colors = Qt.binding(function() { return root.colors })
            item.saveField = function(k, v) { root._saveField(k, v) }
            item.saveConfigKey = function(k, v) { root._saveConfigKey(k, v) }
          }
        }

        // user GitHub repos: add / select / remove
        Column {
          visible: root.source === "repos"
          width: parent.width
          spacing: 8

          Flow {
            width: parent.width
            spacing: 6
            visible: root.repos.length > 0
            Repeater {
              model: root.repos
              Row {
                spacing: 2
                FilterButton {
                  colors: root.colors
                  label: modelData
                  register: false
                  skew: 8
                  height: 26 * Config.uiScale
                  isActive: root.activeRepo === modelData
                  onClicked: root.activeRepo = modelData
                }
                FilterButton {
                  colors: root.colors
                  label: "\u00d7"
                  register: false
                  skew: 8
                  height: 26 * Config.uiScale
                  onClicked: root._removeRepo(modelData)
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: 6
            Rectangle {
              width: parent.width - addBtn.width - parent.spacing
              height: 28 * Config.uiScale
              color: root.colors ? Qt.rgba(root.colors.surface.r, root.colors.surface.g, root.colors.surface.b, 0.8) : Qt.rgba(0.15, 0.17, 0.22, 0.8)
              border.width: repoInput.activeFocus ? 2 : 1
              border.color: repoInput.activeFocus ? (root.colors ? root.colors.primary : Style.fallbackAccent) : (root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.2) : Qt.rgba(1, 1, 1, 0.16))
              Text {
                visible: repoInput.text.length === 0
                anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("owner/repo")
                font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
                color: root.colors ? Qt.rgba(root.colors.surfaceVariantText.r, root.colors.surfaceVariantText.g, root.colors.surfaceVariantText.b, 0.7) : "#8a8f97"
              }
              TextInput {
                id: repoInput
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
                color: root.colors ? root.colors.surfaceText : "#e0e2e8"
                clip: true; selectByMouse: true
                onAccepted: { root._addRepo(text); text = "" }
              }
            }
            FilterButton {
              id: addBtn
              colors: root.colors
              label: I18n.tr("ADD")
              register: false
              skew: 8
              height: 28 * Config.uiScale
              onClicked: { root._addRepo(repoInput.text); repoInput.text = "" }
            }
          }
        }
      }
    }
  }
}
