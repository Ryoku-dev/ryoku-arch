import Quickshell.Io
import QtQuick
import QtQuick.Controls
import ".."
import "../services"
import Ryoku.Ui.Singletons

Item {
  id: browser

  property var colors
  property var swService
  property bool browserVisible: false

  signal escapePressed()

  property var _previewWp: null
  property bool _previewOpen: _previewWp !== null

  clip: !_previewOpen

  visible: browserVisible
  opacity: browserVisible ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }

  readonly property real _gridCellW: Config.steamThumbWidth + 8
  readonly property real _gridCellH: Config.steamThumbHeight + 8
  readonly property real _gridTotalW: _gridCellW * Config.steamColumns

  function runSearch(q) {
    if (!swService) return
    swService.query = q
    swService.search(1)
  }

  // pagination contract consumed by BrowseSurface's shared top bar
  readonly property bool pageActive: browser.swService && (browser.swService.results.length > 0 || browser.swService.currentPage > 1)
  readonly property int pageNum: browser.swService ? browser.swService.currentPage : 1
  readonly property bool pageCanPrev: browser.swService && browser.swService.currentPage > 1 && !browser.swService.loading
  readonly property bool pageCanNext: browser.swService && browser.swService.hasMore && !browser.swService.loading
  function pagePrev() { if (pageCanPrev) { browser.swService.prevPage(); resultsGrid.positionViewAtBeginning() } }
  function pageNext() { if (pageCanNext) { browser.swService.nextPage(); resultsGrid.positionViewAtBeginning() } }

  MouseArea { anchors.fill: parent }

  property Component filterBar: Component {
    Column {
      spacing: 8

      Row {
        spacing: -6

        Repeater {
          model: [
            { key: "trend",      label: I18n.tr("Trending") },
            { key: "new",        label: I18n.tr("New") },
            { key: "toprated",   label: I18n.tr("Top Rated") },
            { key: "popular",    label: I18n.tr("Popular") },
            { key: "favorited",  label: I18n.tr("Favorites") }
          ]
          FilterButton {
            colors: browser.colors; label: I18n.tr(modelData.label); skew: 8
            isActive: browser.swService ? browser.swService.sorting === modelData.key : false
            onClicked: { browser.swService.sorting = modelData.key; browser.swService.search(1) }
          }
        }

        Item { width: 8; height: 1 }

        FilterDropdown {
          visible: browser.swService && browser.swService.sorting === "trend"
          colors: browser.colors; skew: 8
          label: I18n.tr("PERIOD")
          value: browser.swService ? browser.swService.trendDays : 7
          displayValue: {
            if (!browser.swService) return I18n.tr("Week")
            var map = { 1: I18n.tr("Day"), 7: I18n.tr("Week"), 30: I18n.tr("Month"), 90: "3M", 180: "6M", 365: I18n.tr("Year") }
            return map[browser.swService.trendDays] || I18n.tr("Week")
          }
          model: [
            { key: "1",   label: I18n.tr("Day") },
            { key: "7",   label: I18n.tr("Week") },
            { key: "30",  label: I18n.tr("Month") },
            { key: "90",  label: "3M" },
            { key: "180", label: "6M" },
            { key: "365", label: I18n.tr("Year") }
          ]
          onSelected: function(key) { browser.swService.trendDays = parseInt(key); browser.swService.search(1) }
        }
      }

      Row {
        spacing: -6

        FilterDropdown {
          colors: browser.colors; skew: 8
          label: I18n.tr("TYPE")
          value: browser.swService ? browser.swService.requiredType : ""
          displayValue: {
            if (!browser.swService || browser.swService.requiredType === "") return I18n.tr("All Types")
            var map = { "Video": I18n.tr("Video"), "Web": I18n.tr("Web"), "Scene": I18n.tr("Scene"), "Application": I18n.tr("App") }
            return map[browser.swService.requiredType] || browser.swService.requiredType
          }
          model: [
            { key: "",            label: I18n.tr("All Types") },
            { key: "Video",       label: I18n.tr("Video") },
            { key: "Web",         label: I18n.tr("Web") },
            { key: "Scene",       label: I18n.tr("Scene") },
            { key: "Application", label: I18n.tr("App") }
          ]
          onSelected: function(key) { browser.swService.requiredType = key; browser.swService.search(1) }
        }

        Item { width: 14; height: 1 }

        Text {
          text: I18n.tr("CONTENT")
          font.family: Style.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2
          color: browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.35) : Qt.rgba(1,1,1,0.25)
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: 10; height: 1 }

        FilterButton {
          colors: browser.colors; label: I18n.tr("SFW"); skew: 8
          isActive: browser.swService ? !browser.swService.nsfwEnabled : true
          onClicked: { browser.swService.nsfwEnabled = false; browser.swService.search(1) }
        }
        FilterButton {
          colors: browser.colors; label: I18n.tr("NSFW"); skew: 8
          isActive: browser.swService ? browser.swService.nsfwEnabled : false
          activeColor: "#e53935"; hasActiveColor: true
          onClicked: { browser.swService.nsfwEnabled = true; browser.swService.search(1) }
        }

        Item { width: 14; height: 1 }

        FilterDropdown {
          colors: browser.colors; skew: 8
          label: I18n.tr("RESOLUTION")
          value: browser.swService ? browser.swService.requiredResolution : ""
          displayValue: {
            if (!browser.swService || browser.swService.requiredResolution === "") return I18n.tr("Any")
            var map = { "1920 x 1080": "1080p", "2560 x 1440": "2K", "3840 x 2160": "4K", "2560 x 1080": "UW", "3440 x 1440": "UWQHD", "3840 x 1080": "Dual", "5120 x 1440": "Dual QHD" }
            return map[browser.swService.requiredResolution] || browser.swService.requiredResolution
          }
          model: [
            { key: "",                label: I18n.tr("Any") },
            { key: "1920 x 1080",    label: "1080p" },
            { key: "2560 x 1440",    label: "2K" },
            { key: "3840 x 2160",    label: "4K" },
            { key: "2560 x 1080",    label: "UW" },
            { key: "3440 x 1440",    label: "UWQHD" },
            { key: "3840 x 1080",    label: "Dual" },
            { key: "5120 x 1440",    label: "Dual QHD" }
          ]
          onSelected: function(key) { browser.swService.requiredResolution = key; browser.swService.search(1) }
        }

        Item { width: 14; height: 1 }

        FilterDropdown {
          colors: browser.colors; skew: 8
          label: I18n.tr("CATEGORY")
          value: browser.swService ? browser.swService.requiredTag : ""
          displayValue: {
            if (!browser.swService || browser.swService.requiredTag === "") return I18n.tr("All")
            return browser.swService.requiredTag
          }
          model: [
            { key: "",           label: I18n.tr("All") },
            { key: "Abstract",   label: I18n.tr("Abstract") },
            { key: "Animal",     label: I18n.tr("Animal") },
            { key: "Anime",      label: I18n.tr("Anime") },
            { key: "CGI",        label: I18n.tr("CGI") },
            { key: "Cyberpunk",  label: I18n.tr("Cyberpunk") },
            { key: "Fantasy",    label: I18n.tr("Fantasy") },
            { key: "Game",       label: I18n.tr("Game") },
            { key: "Girls",      label: I18n.tr("Girls") },
            { key: "Guys",       label: I18n.tr("Guys") },
            { key: "Landscape",  label: I18n.tr("Landscape") },
            { key: "Medieval",   label: I18n.tr("Medieval") },
            { key: "Music",      label: I18n.tr("Music") },
            { key: "Nature",     label: I18n.tr("Nature") },
            { key: "Pixel art",  label: I18n.tr("Pixel Art") },
            { key: "Relaxing",   label: I18n.tr("Relaxing") },
            { key: "Retro",      label: I18n.tr("Retro") },
            { key: "Sci-Fi",     label: I18n.tr("Sci-Fi") },
            { key: "Technology", label: I18n.tr("Technology") },
            { key: "Vehicle",    label: I18n.tr("Vehicle") }
          ]
          onSelected: function(key) { browser.swService.requiredTag = key; browser.swService.search(1) }
        }
      }
    }
  }

  Column {
    id: contentCol
    z: 10
    width: browser._gridTotalW
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: 12
    spacing: 8


    Text {
      visible: browser.swService && browser.swService.errorText !== ""
      text: browser.swService ? browser.swService.errorText : ""
      font.family: Style.fontFamily; font.pixelSize: 11
      color: "#ff6b6b"
      width: parent.width
      wrapMode: Text.Wrap
    }

    Rectangle {
      id: downloadStatusBar
      width: parent.width
      height: _dlBarVisible ? 28 : 0
      radius: 4
      clip: true
      property bool _dlBarVisible: browser.swService && (browser.swService.downloadQueueLength > 0 || browser.swService.authPaused)
      visible: _dlBarVisible
      Behavior on height { NumberAnimation { duration: Style.animFast; easing.type: Easing.OutCubic } }

      color: browser.swService && browser.swService.authPaused
        ? Qt.rgba(0.9, 0.2, 0.2, 0.15)
        : (browser.colors ? Qt.rgba(browser.colors.surface.r, browser.colors.surface.g, browser.colors.surface.b, 0.7)
                          : Qt.rgba(0.12, 0.14, 0.18, 0.7))
      border.width: 1
      border.color: browser.swService && browser.swService.authPaused
        ? Qt.rgba(0.9, 0.2, 0.2, 0.4)
        : (browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.25)
                          : Qt.rgba(1, 1, 1, 0.08))

      Rectangle {
        id: _progressFill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: !browser.swService || !browser.swService.authPaused
        property real _realProgress: browser.swService && browser.swService.activeDownloadId
          ? (browser.swService.downloadProgress[browser.swService.activeDownloadId] || 0)
          : 0
        property bool _hasProgress: _realProgress > 0.01
        width: _hasProgress ? parent.width * _realProgress : 0
        radius: 4
        color: browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.15)
                              : Qt.rgba(1, 0.53, 0, 0.1)
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }

      Rectangle {
        id: _indeterminateShimmer
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.25
        radius: 4
        visible: downloadStatusBar._dlBarVisible && !_progressFill._hasProgress && !(browser.swService && browser.swService.authPaused)
        color: browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.12)
                              : Qt.rgba(1, 0.53, 0, 0.08)
        property real _pos: 0
        x: _pos * (parent.width - width)

        SequentialAnimation on _pos {
          running: _indeterminateShimmer.visible
          loops: Animation.Infinite
          NumberAnimation { from: 0; to: 1; duration: 1500; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1; to: 0; duration: 1500; easing.type: Easing.InOutSine }
        }
      }

      Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
          text: browser.swService && browser.swService.authPaused ? "\u{f0341}" : "\u{f01da}"
          font.family: Style.fontFamilyNerdIcons; font.pixelSize: 13
          color: browser.swService && browser.swService.authPaused
            ? "#ff6b6b"
            : (browser.colors ? browser.colors.primary : Style.fallbackAccent)
        }

        Text {
          text: {
            if (!browser.swService) return ""
            if (browser.swService.authPaused) {
              var n = browser.swService.authFailedCount
              return I18n.tr("Steam login expired - %1 downloads paused. Run: steamcmd +login %2 +quit").arg(n).arg(Config.steamUsername || "your_username")
            }
            var msg = browser.swService.activeDownloadMessage || I18n.tr("Preparing...")
            var q = browser.swService.downloadQueueLength
            return msg + (q > 1 ? "  \u{f0142}  " + I18n.tr("%1 queued").arg(q - 1) : "")
          }
          font.family: Style.fontFamily; font.pixelSize: 11; font.weight: Font.Medium
          color: browser.swService && browser.swService.authPaused
            ? "#ff6b6b"
            : (browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.8)
                              : Qt.rgba(1, 1, 1, 0.7))
        }

        Rectangle {
          visible: browser.swService && browser.swService.authPaused
          width: retryText.implicitWidth + 16; height: 20; radius: 3
          color: retryMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
          border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)
          Text {
            id: retryText; anchors.centerIn: parent
            text: I18n.tr("Retry"); font.family: Style.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
            color: browser.colors ? browser.colors.surfaceText : "#e0e0e0"
          }
          MouseArea {
            id: retryMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: browser.swService.retryDownloads()
          }
        }
      }
    }
  }

  ListModel { id: resultsModel }

  Connections {
    target: browser.swService
    function onResultsUpdated() {
      var total = browser.swService ? browser.swService.results.length : 0
      if (total < resultsModel.count) {
        resultsModel.clear()
      }
      var toAdd = total - resultsModel.count
      if (toAdd > 0) {
        var batch = []
        for (var i = 0; i < toAdd; i++)
          batch.push({ idx: resultsModel.count + i })
        resultsModel.append(batch)
      }
      resultsGrid.positionViewAtBeginning()
    }
  }

  GridView {
    id: resultsGrid
    anchors.top: contentCol.bottom; anchors.topMargin: 10
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12
    width: browser._gridTotalW
    clip: true
    cellWidth: browser._gridCellW
    cellHeight: browser._gridCellH

    model: resultsModel
    cacheBuffer: 600
    boundsBehavior: Flickable.StopAtBounds
    interactive: false

    property real _scrollTarget: 0
    onContentYChanged: {
      if (!_gridScrollAnim.running) _scrollTarget = contentY
      if (contentY > _prevContentY) _lastScrollDir = 1
      else if (contentY < _prevContentY) _lastScrollDir = -1
      _prevContentY = contentY
    }

    NumberAnimation {
      id: _gridScrollAnim
      target: resultsGrid
      property: "contentY"
      duration: 400
      easing.type: Easing.OutCubic
    }

    function _snapScroll(delta) {
      if (!_gridScrollAnim.running) _scrollTarget = contentY
      var step = cellHeight
      _scrollTarget += (delta > 0 ? -step : step)
      var maxY = contentHeight - height
      _scrollTarget = Math.max(0, Math.min(_scrollTarget, maxY))
      _gridScrollAnim.stop()
      _gridScrollAnim.from = contentY
      _gridScrollAnim.to = _scrollTarget
      _gridScrollAnim.start()
    }

    MouseArea {
      anchors.fill: parent
      propagateComposedEvents: true
      onWheel: function(wheel) {
        resultsGrid._snapScroll(wheel.angleDelta.y)
        resultsGrid.forceActiveFocus()
      }
      onPressed: function(mouse) { mouse.accepted = false }
      onReleased: function(mouse) { mouse.accepted = false }
      onClicked: function(mouse) { mouse.accepted = false }
    }

    property int _lastScrollDir: 1
    property real _prevContentY: 0
    onContentHeightChanged: _prevContentY = contentY


    ScrollBar.vertical: ScrollBar {
      policy: ScrollBar.AsNeeded
      width: 4
      contentItem: Rectangle {
        radius: 2
        color: browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.4)
                              : Qt.rgba(1, 1, 1, 0.3)
      }
    }

      delegate: Item {
        id: thumbDelegate
        width: resultsGrid.cellWidth
        height: resultsGrid.cellHeight

        required property int index
        property var wp: browser.swService ? browser.swService.results[index] : null
        property string dlStatus: {
          if (!browser.swService || !wp) return ""
          var s = browser.swService.downloadStatus
          return s[wp.id] || ""
        }
        property real dlProgress: {
          if (!browser.swService || !wp) return 0
          var p = browser.swService.downloadProgress
          return p[wp.id] || 0
        }
        property bool isLocal: {
          if (!browser.swService || !wp) return false
          var ids = browser.swService.localWorkshopIds
          return !!ids[wp.id]
        }

        property bool _needsEntryAnim: false
        opacity: 0
        transform: Translate { id: thumbTranslate; y: 0 }

        Component.onCompleted: {
          if (resultsGrid._lastScrollDir >= 0) {
            _needsEntryAnim = true
            thumbTranslate.y = 30
            var col = index % Config.steamColumns
            _entryDelay.interval = col * 35
            _entryDelay.start()
          } else {
            opacity = 1
          }
        }

        Timer {
          id: _entryDelay
          repeat: false
          onTriggered: {
            _opacityAnim.start()
            _slideAnim.start()
          }
        }

        NumberAnimation {
          id: _opacityAnim
          target: thumbDelegate; property: "opacity"
          from: 0; to: 1; duration: Style.animEnter
          easing.type: Easing.OutCubic
        }

        NumberAnimation {
          id: _slideAnim
          target: thumbTranslate; property: "y"
          from: 30; to: 0; duration: Style.animExpand
          easing.type: Easing.OutBack
        }

        Rectangle {
          anchors.fill: parent; anchors.margins: 4; radius: 6
          color: "transparent"
          border.width: resultsGrid.currentIndex === thumbDelegate.index ? 2 : 0
          border.color: browser.colors ? browser.colors.primary : "#ff8800"
          Behavior on border.width { NumberAnimation { duration: Style.animFast; easing.type: Easing.OutQuad } }

          Rectangle {
            anchors.fill: parent; anchors.margins: parent.border.width; radius: 5
            color: browser.colors ? Qt.rgba(browser.colors.surface.r, browser.colors.surface.g, browser.colors.surface.b, 0.6)
                                  : Qt.rgba(0.12, 0.14, 0.18, 0.6)
            clip: true

          Image {
            id: thumbImg
            anchors.fill: parent
            source: thumbDelegate.wp ? thumbDelegate.wp.previewUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false
            sourceSize.width: Config.steamThumbWidth
            sourceSize.height: Config.steamThumbHeight
          }

          Rectangle {
            id: skeleton
            anchors.fill: parent; radius: 6
            visible: thumbImg.status !== Image.Ready
            color: browser.colors ? Qt.rgba(browser.colors.surfaceVariant.r, browser.colors.surfaceVariant.g, browser.colors.surfaceVariant.b, 0.5)
                                  : Qt.rgba(0.18, 0.20, 0.25, 0.8)

            Rectangle {
              id: shimmer
              width: parent.width * 0.5
              height: parent.height
              radius: 6
              opacity: 0.35
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.08) }
                GradientStop { position: 1.0; color: "transparent" }
              }
              NumberAnimation on x {
                from: -shimmer.width
                to: skeleton.width
                duration: 1200
                loops: Animation.Infinite
                running: skeleton.visible
              }
            }

            Text {
              anchors.centerIn: parent
              text: "\u{f0553}"
              font.family: Style.fontFamilyNerdIcons; font.pixelSize: 22
              color: browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.15) : Qt.rgba(1,1,1,0.1)
            }
          }

          Rectangle {
            id: hoverOverlay
            anchors.fill: parent; radius: 6
            color: Qt.rgba(0, 0, 0, 0.55)
            opacity: thumbMouse.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.animFast } }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: browser._previewWp = thumbDelegate.wp
            }

            Column {
              anchors.centerIn: parent
              spacing: 4

              Text {
                width: parent.parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
                text: thumbDelegate.wp ? thumbDelegate.wp.title : ""
                font.family: Style.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
                color: "#e0e0e0"
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -3
                visible: thumbDelegate.dlStatus !== "downloading" && thumbDelegate.dlStatus !== "queued"

                ActionButton {
                  colors: browser.colors
                  icon: (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal) ? "\u{f012c}" : (thumbDelegate.dlStatus === "error" ? "\u{f0159}" : "\u{f01da}")
                  label: (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal) ? I18n.tr("Installed") : (thumbDelegate.dlStatus === "error" ? I18n.tr("Error") : I18n.tr("Install"))
                  tooltip: I18n.tr("Download via steamcmd")
                  onClicked: {
                    if (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal || !thumbDelegate.wp) return
                    browser.swService.downloadWorkshop(thumbDelegate.wp.id, thumbDelegate.wp.fileSize)
                  }
                }
              }

              Text {
                visible: thumbDelegate.dlStatus === "downloading" || thumbDelegate.dlStatus === "queued"
                anchors.horizontalCenter: parent.horizontalCenter
                text: thumbDelegate.dlStatus === "queued" ? I18n.tr("Queued...") : (browser.swService.activeDownloadMessage || I18n.tr("Downloading..."))
                font.family: Style.fontFamily; font.pixelSize: 11
                color: browser.colors ? browser.colors.primary : Style.fallbackAccent
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Text {
                  text: thumbDelegate.wp ? "\u{f0899} " + _formatCount(thumbDelegate.wp.subscriptions) : ""
                  font.family: Style.fontFamilyNerdIcons; font.pixelSize: 9
                  color: "#999"
                }
                Text {
                  text: thumbDelegate.wp ? "\u{f02d1} " + _formatCount(thumbDelegate.wp.favorited) : ""
                  font.family: Style.fontFamilyNerdIcons; font.pixelSize: 9
                  color: "#999"
                }
              }
            }
          }

          Row {
            anchors.bottom: parent.bottom; anchors.left: parent.left
            anchors.margins: 4; spacing: 3
            Repeater {
              model: thumbDelegate.wp ? Math.min(thumbDelegate.wp.tags.length, 2) : 0
              Rectangle {
                width: tagBadge.implicitWidth + 6; height: 14; radius: 3
                color: Qt.rgba(0, 0, 0, 0.6)
                Text {
                  id: tagBadge; anchors.centerIn: parent
                  text: thumbDelegate.wp.tags[index]
                  font.family: Style.fontFamily; font.pixelSize: 8
                  color: "#ccc"
                }
              }
            }
          }

          Rectangle {
            visible: thumbDelegate.isLocal || thumbDelegate.dlStatus === "done"
            anchors.top: parent.top; anchors.left: parent.left
            anchors.margins: 4
            width: dlBadgeRow.implicitWidth + 8; height: 16; radius: 4
            color: browser.colors ? Qt.rgba(browser.colors.primary.r, browser.colors.primary.g, browser.colors.primary.b, 0.85)
                                  : Qt.rgba(0.3, 0.76, 0.97, 0.85)
            Row {
              id: dlBadgeRow; anchors.centerIn: parent; spacing: 3
              Text {
                text: "\u{f012c}"; font.family: Style.fontFamilyNerdIcons; font.pixelSize: 10
                color: browser.colors ? browser.colors.primaryText : "#000"
              }
              Text {
                text: I18n.tr("Installed"); font.family: Style.fontFamily; font.pixelSize: 8; font.weight: Font.Medium
                color: browser.colors ? browser.colors.primaryText : "#000"
              }
            }
          }

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            color: "transparent"
            visible: thumbDelegate.dlStatus === "downloading" || thumbDelegate.dlStatus === "queued"
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * thumbDelegate.dlProgress
              radius: 2
              color: browser.colors ? browser.colors.primary : Style.fallbackAccent
              Behavior on width { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }
            }
          }

          MouseArea {
            id: thumbMouse; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            propagateComposedEvents: true
            onContainsMouseChanged: {
              if (containsMouse) resultsGrid.currentIndex = thumbDelegate.index
            }
            onPressed: function(mouse) { mouse.accepted = false }
          }
          }
        }
      }
  }

  Text {
    visible: browser.swService && !browser.swService.loading && resultsModel.count === 0 && browser.swService.errorText === ""
    text: I18n.tr("Search the Steam Workshop for Wallpaper Engine wallpapers")
    font.family: Style.fontFamily; font.pixelSize: 12
    color: browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.4)
                          : Qt.rgba(1, 1, 1, 0.3)
    anchors.centerIn: resultsGrid
  }

  Component.onCompleted: {
    if (browserVisible && swService && resultsModel.count === 0) {
      swService.search(1)
    }
  }

  onBrowserVisibleChanged: {
    if (browserVisible && swService && resultsModel.count === 0) {
      swService.search(1)
    } else if (browserVisible) {
      if (swService) swService.scanLocalDirs()
    } else {
      if (swService) swService.clearCache()
      resultsModel.clear()
      _previewWp = null
    }
  }


  Item {
    anchors.fill: resultsGrid
    visible: browser.swService && browser.swService.loading

    enabled: false

    Text {
      anchors.centerIn: parent
      text: "\u{f051f}"
      font.family: Style.fontFamilyNerdIcons; font.pixelSize: 128
      color: browser.colors ? browser.colors.primary : Style.fallbackAccent
      opacity: browser.swService && browser.swService.loading ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.animFast } }
      RotationAnimation on rotation { from: 0; to: 360; duration: Style.animSpin; loops: Animation.Infinite; running: browser.swService && browser.swService.loading }
    }
  }

  Rectangle {
    id: previewOverlay

    property point _rootPos: {
      if (!browser._previewOpen) return Qt.point(0, 0)
      var mapped = browser.mapToItem(null, 0, 0)
      return mapped
    }
    property var _rootItem: {
      var p = browser.parent
      while (p && p.parent) p = p.parent
      return p
    }

    x: -_rootPos.x
    y: -_rootPos.y
    width: _rootItem ? _rootItem.width : parent.width
    height: _rootItem ? _rootItem.height : parent.height
    z: 100
    visible: opacity > 0
    color: Qt.rgba(0, 0, 0, 0.92)
    opacity: browser._previewOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.animEnter; easing.type: Easing.OutCubic } }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: browser._previewWp = null
    }

    Keys.onEscapePressed: browser._previewWp = null
    focus: browser._previewOpen

    Image {
      id: previewImg
      anchors.fill: parent
      anchors.margins: 60
      anchors.bottomMargin: 80
      source: browser._previewWp ? browser._previewWp.previewUrl : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true; cache: false
      sourceSize.width: previewOverlay.width
      sourceSize.height: previewOverlay.height

      scale: browser._previewOpen ? 1.0 : 0.85
      Behavior on scale { NumberAnimation { duration: Style.animExpand; easing.type: Easing.OutBack } }

      opacity: browser._previewOpen ? 1.0 : 0.0
      Behavior on opacity { NumberAnimation { duration: Style.animEnter; easing.type: Easing.OutCubic } }
    }

    Text {
      anchors.centerIn: parent
      visible: previewImg.status === Image.Loading
      text: "\u{f051f}"
      font.family: Style.fontFamilyNerdIcons; font.pixelSize: 40
      color: browser.colors ? browser.colors.primary : Style.fallbackAccent
      RotationAnimation on rotation { from: 0; to: 360; duration: Style.animSpin; loops: Animation.Infinite; running: previewImg.status === Image.Loading }
    }

    Rectangle {
      anchors.top: parent.top; anchors.right: parent.right
      anchors.margins: 20
      width: 40; height: 40; radius: 20
      color: previewCloseMouse.containsMouse ? Qt.rgba(1,1,1,0.25) : Qt.rgba(1,1,1,0.1)
      Behavior on color { ColorAnimation { duration: Style.animVeryFast } }

      Text {
        anchors.centerIn: parent
        text: "\u{f0156}"
        font.family: Style.fontFamilyNerdIcons; font.pixelSize: 20
        color: "#fff"
      }
      MouseArea {
        id: previewCloseMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: browser._previewWp = null
      }
      StyledToolTip { visible: previewCloseMouse.containsMouse; text: I18n.tr("Close preview"); delay: 400 }
    }

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.left: parent.left; anchors.right: parent.right
      height: 56
      color: Qt.rgba(0, 0, 0, 0.6)

      Row {
        anchors.centerIn: parent
        spacing: 20

        Text {
          text: browser._previewWp ? browser._previewWp.title : ""
          font.family: Style.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
          color: Qt.rgba(1, 1, 1, 0.85)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          maximumLineCount: 1
          width: Math.min(implicitWidth, 300)
        }

        Row {
          spacing: 5; anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "\u{f0899}"
            font.family: Style.fontFamilyNerdIcons; font.pixelSize: 14
            color: browser.colors ? browser.colors.primary : Style.fallbackAccent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: browser._previewWp ? _formatCount(browser._previewWp.subscriptions) : ""
            font.family: Style.fontFamily; font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.65)
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          spacing: 5; anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "\u{f02d1}"
            font.family: Style.fontFamilyNerdIcons; font.pixelSize: 14
            color: browser.colors ? browser.colors.primary : Style.fallbackAccent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: browser._previewWp ? _formatCount(browser._previewWp.favorited) : ""
            font.family: Style.fontFamily; font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.65)
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          spacing: 4; anchors.verticalCenter: parent.verticalCenter
          visible: browser._previewWp && browser._previewWp.tags.length > 0
          Repeater {
            model: browser._previewWp ? Math.min(browser._previewWp.tags.length, 3) : 0
            Rectangle {
              width: pvTagText.implicitWidth + 12; height: 24; radius: 4
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(1, 1, 1, 0.1)
              Text {
                id: pvTagText; anchors.centerIn: parent
                text: browser._previewWp.tags[index]
                font.family: Style.fontFamily; font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.7)
              }
            }
          }
        }

        Rectangle { width: 1; height: 24; color: Qt.rgba(1,1,1,0.15); anchors.verticalCenter: parent.verticalCenter }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: -3

          property string _dlSt: {
            if (!browser.swService || !browser._previewWp) return ""
            var s = browser.swService.downloadStatus
            return s[browser._previewWp.id] || ""
          }
          property bool _isLocal: {
            if (!browser.swService || !browser._previewWp) return false
            return !!browser.swService.localWorkshopIds[browser._previewWp.id]
          }

          ActionButton {
            colors: browser.colors
            icon: (parent._dlSt === "done" || parent._isLocal) ? "\u{f012c}" : (parent._dlSt === "error" ? "\u{f0159}" : "\u{f01da}")
            label: (parent._dlSt === "done" || parent._isLocal) ? I18n.tr("Installed")
              : (parent._dlSt === "downloading" ? (browser.swService.activeDownloadMessage || I18n.tr("Downloading..."))
              : (parent._dlSt === "queued" ? I18n.tr("Queued...")
              : (parent._dlSt === "error" ? I18n.tr("Error") : I18n.tr("Install"))))
            tooltip: I18n.tr("Download via steamcmd")
            onClicked: {
              if (parent._dlSt === "done" || parent._isLocal || parent._dlSt === "downloading" || parent._dlSt === "queued" || !browser._previewWp) return
              browser.swService.downloadWorkshop(browser._previewWp.id, browser._previewWp.fileSize)
            }
          }
        }
      }
    }
  }

  function _formatCount(n) {
    if (!n || n <= 0) return "0"
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "K"
    return n.toString()
  }

  function _formatSize(bytes) {
    if (!bytes || bytes <= 0) return ""
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1048576) return (bytes / 1024).toFixed(0) + " KB"
    return (bytes / 1048576).toFixed(1) + " MB"
  }
}
