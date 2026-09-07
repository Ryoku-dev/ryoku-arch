import Quickshell.Io
import QtQuick
import QtQuick.Controls
import ".."
import "../services"
import Ryoku.Ui.Singletons

Item {
  id: browser

  property var colors
  property var whService
  property bool browserVisible: false

  signal escapePressed()

  property var _previewWp: null
  property bool _previewOpen: _previewWp !== null

  property string _pendingApplyId: ""

  // pagination contract consumed by BrowseSurface's shared top bar
  readonly property bool pageActive: browser.whService && (browser.whService.results.length > 0 || browser.whService.currentPage > 1)
  readonly property int pageNum: browser.whService ? browser.whService.currentPage : 1
  readonly property bool pageCanPrev: browser.whService && browser.whService.currentPage > 1 && !browser.whService.loading
  readonly property bool pageCanNext: browser.whService && browser.whService.hasMore && !browser.whService.loading
  function pagePrev() { if (pageCanPrev) { browser.whService.prevPage(); resultsGrid.positionViewAtBeginning() } }
  function pageNext() { if (pageCanNext) { browser.whService.nextPage(); resultsGrid.positionViewAtBeginning() } }

  clip: !_previewOpen

  visible: browserVisible
  opacity: browserVisible ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Style.animNormal; easing.type: Easing.OutCubic } }

  readonly property real _gridCellW: Config.wallhavenThumbWidth + 8
  readonly property real _gridCellH: Config.wallhavenThumbHeight + 8
  readonly property real _gridTotalW: _gridCellW * Config.wallhavenColumns

  function runSearch(q) {
    if (!whService) return
    whService.query = q
    whService.search(1)
  }

  MouseArea { anchors.fill: parent }

  property Component filterBar: Component {
    Column {
      spacing: 8

      Row {
        spacing: 2

        Repeater {
          model: [
            { label: I18n.tr("General"), bit: 0 },
            { label: I18n.tr("Anime"),   bit: 1 },
            { label: I18n.tr("People"),  bit: 2 }
          ]
          FilterButton {
            colors: browser.colors; label: I18n.tr(modelData.label); skew: 8
            isActive: browser.whService ? browser.whService.categories.charAt(modelData.bit) === "1" : false
            onClicked: {
              var c = browser.whService.categories.split("")
              c[modelData.bit] = c[modelData.bit] === "1" ? "0" : "1"
              if (c.join("") === "000") return
              browser.whService.categories = c.join("")
              browser.whService.search(1)
            }
          }
        }

        Item { width: 8; height: 1 }

        Repeater {
          model: [
            { key: "toplist",    label: I18n.tr("Top") },
            { key: "date_added", label: I18n.tr("New") },
            { key: "views",      label: I18n.tr("Views") },
            { key: "random",     label: I18n.tr("Random") }
          ]
          FilterButton {
            colors: browser.colors; label: I18n.tr(modelData.label); skew: 8
            isActive: browser.whService ? browser.whService.sorting === modelData.key : false
            onClicked: { browser.whService.sorting = modelData.key; browser.whService.search(1) }
          }
        }

        Item { width: 8; height: 1 }

        FilterDropdown {
          visible: browser.whService && browser.whService.sorting === "toplist"
          colors: browser.colors; skew: 8
          label: I18n.tr("PERIOD")
          value: browser.whService ? browser.whService.topRange : "1M"
          displayValue: {
            if (!browser.whService) return I18n.tr("Month")
            var map = { "1d": I18n.tr("Day"), "1w": I18n.tr("Week"), "1M": I18n.tr("Month"), "3M": "3M", "6M": "6M", "1y": I18n.tr("Year") }
            return map[browser.whService.topRange] || I18n.tr("Month")
          }
          model: [
            { key: "1d", label: I18n.tr("Day") },
            { key: "1w", label: I18n.tr("Week") },
            { key: "1M", label: I18n.tr("Month") },
            { key: "3M", label: "3M" },
            { key: "6M", label: "6M" },
            { key: "1y", label: I18n.tr("Year") }
          ]
          onSelected: function(key) { browser.whService.topRange = key; browser.whService.search(1) }
        }
      }

      Row {
        spacing: 2

        Text {
          text: I18n.tr("PURITY")
          font.family: Style.fontFamily; font.pixelSize: 9 * Config.uiScale; font.weight: Font.Bold; font.letterSpacing: 1.2
          color: browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.35) : Qt.rgba(1,1,1,0.25)
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: 10; height: 1 }

        Repeater {
          model: [
            { label: I18n.tr("SFW"),     bit: 0 },
            { label: I18n.tr("Sketchy"), bit: 1 },
            { label: I18n.tr("NSFW"),    bit: 2 }
          ]
          FilterButton {
            colors: browser.colors; label: I18n.tr(modelData.label); skew: 8
            isActive: browser.whService ? browser.whService.purity.charAt(modelData.bit) === "1" : false
            activeColor: "#e53935"; hasActiveColor: modelData.bit === 2
            activeOpacity: modelData.bit === 2 && (!browser.whService || !browser.whService.apiKey) && !isActive ? 0.4 : 1.0
            tooltip: modelData.bit === 2 && (!browser.whService || !browser.whService.apiKey) ? I18n.tr("NSFW requires an API key") : ""
            onClicked: {
              var p = browser.whService.purity.split("")
              p[modelData.bit] = p[modelData.bit] === "1" ? "0" : "1"
              if (p.join("") === "000") return
              browser.whService.purity = p.join("")
              browser.whService.search(1)
            }
          }
        }

        Item { width: 14; height: 1 }

        FilterDropdown {
          colors: browser.colors; skew: 8
          label: I18n.tr("MIN RES")
          value: browser.whService ? browser.whService.atleast : ""
          displayValue: {
            if (!browser.whService || browser.whService.atleast === "") return I18n.tr("Any")
            var map = { "1920x1080": "1080p", "2560x1440": "2K", "3840x2160": "4K", "5120x2880": "5K", "7680x4320": "8K" }
            return map[browser.whService.atleast] || browser.whService.atleast
          }
          model: [
            { key: "",           label: I18n.tr("Any") },
            { key: "1920x1080", label: "1080p" },
            { key: "2560x1440", label: "2K" },
            { key: "3840x2160", label: "4K" },
            { key: "5120x2880", label: "5K" },
            { key: "7680x4320", label: "8K" }
          ]
          onSelected: function(key) { browser.whService.atleast = key; browser.whService.search(1) }
        }

        Item { width: 14; height: 1 }

        FilterDropdown {
          colors: browser.colors; skew: 8
          label: I18n.tr("RATIO")
          value: browser.whService ? browser.whService.ratios : ""
          displayValue: {
            if (!browser.whService || browser.whService.ratios === "") return I18n.tr("Any")
            var map = { "16x9": "16:9", "16x10": "16:10", "21x9": "21:9", "32x9": "32:9", "4x3": "4:3" }
            return map[browser.whService.ratios] || browser.whService.ratios
          }
          model: [
            { key: "",     label: I18n.tr("Any") },
            { key: "16x9", label: "16:9" },
            { key: "16x10", label: "16:10" },
            { key: "21x9", label: "21:9" },
            { key: "32x9", label: "32:9" },
            { key: "4x3",  label: "4:3" }
          ]
          onSelected: function(key) { browser.whService.ratios = key; browser.whService.search(1) }
        }

        Item { width: 14; height: 1 }

        ColorFilterStrip {
          colors: browser.colors
          selectedValue: browser.whService ? browser.whService.selectedColor : -1
          onValueSelected: function(v) {
            if (!browser.whService) return
            browser.whService.selectedColor = v
            browser.whService.search(1)
          }
        }
      }
    }
  }

  Text {
    z: 20
    anchors.top: parent.top
    anchors.topMargin: 6
    anchors.horizontalCenter: parent.horizontalCenter
    visible: browser.whService && browser.whService.errorText !== ""
    text: browser.whService ? browser.whService.errorText : ""
    font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
    color: "#ff6b6b"
    width: browser._gridTotalW
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
  }

  ListModel { id: resultsModel }

  Connections {
    target: browser.whService
    function onResultsUpdated() {
      var total = browser.whService ? browser.whService.results.length : 0
      console.log("[WH-UI] onResultsUpdated total=" + total + "  modelCount=" + resultsModel.count)
      if (total < resultsModel.count) {
        resultsModel.clear()
      }
      var toAdd = total - resultsModel.count
      if (toAdd > 0) {
        var batch = []
        for (var i = 0; i < toAdd; i++)
          batch.push({ idx: resultsModel.count + i })
        resultsModel.append(batch)
        console.log("[WH-UI] appended " + toAdd + " items, new modelCount=" + resultsModel.count)
      }
      resultsGrid.positionViewAtBeginning()
    }
  }

  GridView {
    id: resultsGrid
    anchors.top: parent.top; anchors.topMargin: 10
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

    property real _wheelAccum: 0

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

    function _onWheelDelta(dy) {
      if (dy === 0) return
      if ((_wheelAccum > 0) !== (dy > 0)) _wheelAccum = 0
      _wheelAccum += dy
      if (Math.abs(_wheelAccum) >= 120) {
        _snapScroll(_wheelAccum)
        _wheelAccum = 0
      }
    }

    Keys.onUpPressed: resultsGrid._snapScroll(1)
    Keys.onDownPressed: resultsGrid._snapScroll(-1)

    MouseArea {
      anchors.fill: parent
      propagateComposedEvents: true
      onWheel: function(wheel) {
        resultsGrid._onWheelDelta(wheel.angleDelta.y)
        resultsGrid.forceActiveFocus()
      }
      onPressed: function(mouse) { resultsGrid.forceActiveFocus(); mouse.accepted = false }
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
        property var wp: browser.whService ? browser.whService.results[index] : null
        property string dlStatus: {
          if (!browser.whService || !wp) return ""
          var s = browser.whService.downloadStatus
          return s[wp.id] || ""
        }
        property real dlProgress: {
          if (!browser.whService || !wp) return 0
          var p = browser.whService.downloadProgress
          return p[wp.id] || 0
        }
        property bool isLocal: {
          if (!browser.whService || !wp) return false
          var ids = browser.whService.localWallhavenIds
          return !!ids[wp.id]
        }

        property bool _needsEntryAnim: false
        opacity: 0
        transform: Translate { id: thumbTranslate; y: 0 }

        Component.onCompleted: {
          if (resultsGrid._lastScrollDir >= 0) {
            _needsEntryAnim = true
            thumbTranslate.y = 30
            var col = index % Config.wallhavenColumns
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
            source: thumbDelegate.wp ? thumbDelegate.wp.thumbLarge : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false
            sourceSize.width: Config.wallhavenThumbWidth
            sourceSize.height: Config.wallhavenThumbHeight
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
                anchors.horizontalCenter: parent.horizontalCenter
                text: thumbDelegate.wp ? thumbDelegate.wp.resolution : ""
                font.family: Style.fontFamily; font.pixelSize: 10
                color: "#cccccc"
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -3
                visible: thumbDelegate.dlStatus !== "downloading"

                ActionButton {
                  colors: browser.colors
                  icon: (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal) ? "\u{f012c}" : (thumbDelegate.dlStatus === "error" ? "\u{f0159}" : "\u{f01da}")
                  label: (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal) ? I18n.tr("Saved") : (thumbDelegate.dlStatus === "error" ? I18n.tr("Error") : I18n.tr("Save"))
                  tooltip: I18n.tr("Download to wallpaper folder")
                  onClicked: {
                    if (thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal || !thumbDelegate.wp) return
                    browser.whService.downloadWallpaper(thumbDelegate.wp.id, thumbDelegate.wp.path)
                  }
                }

                ActionButton {
                  colors: browser.colors
                  icon: "\u{f0e56}"; label: I18n.tr("Apply")
                  tooltip: I18n.tr("Download and set as wallpaper")
                  visible: thumbDelegate.dlStatus !== "done" && !thumbDelegate.isLocal
                  onClicked: {
                    if (!thumbDelegate.wp || thumbDelegate.dlStatus === "downloading") return
                    browser._pendingApplyId = thumbDelegate.wp.id
                    browser.whService.downloadWallpaper(thumbDelegate.wp.id, thumbDelegate.wp.path)
                  }
                }

                ActionButton {
                  colors: browser.colors
                  icon: "\u{f0e56}"; label: I18n.tr("Apply")
                  tooltip: I18n.tr("Set as wallpaper")
                  visible: thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal
                  onClicked: {
                    if (!thumbDelegate.wp) return
                    browser._applyLocalWallhaven(thumbDelegate.wp.id)
                  }
                }

                ActionButton {
                  colors: browser.colors
                  icon: "\u{f01b4}"; label: I18n.tr("Delete")
                  danger: true
                  tooltip: I18n.tr("Delete from wallpaper folder")
                  visible: thumbDelegate.dlStatus === "done" || thumbDelegate.isLocal
                  onClicked: {
                    if (!thumbDelegate.wp) return
                    browser._deleteWallhaven(thumbDelegate.wp.id)
                  }
                }
              }

              Text {
                visible: thumbDelegate.dlStatus === "downloading"
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Downloading...")
                font.family: Style.fontFamily; font.pixelSize: 11
                color: browser.colors ? browser.colors.primary : Style.fallbackAccent
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: thumbDelegate.wp ? _formatSize(thumbDelegate.wp.fileSize) : ""
                font.family: Style.fontFamily; font.pixelSize: 9
                color: "#999"
              }
            }
          }

          Row {
            anchors.bottom: parent.bottom; anchors.left: parent.left
            anchors.margins: 4; spacing: 3

            Rectangle {
              width: catBadge.implicitWidth + 6; height: 14; radius: 3
              color: Qt.rgba(0, 0, 0, 0.6)
              Text {
                id: catBadge; anchors.centerIn: parent
                text: thumbDelegate.wp ? thumbDelegate.wp.category : ""
                font.family: Style.fontFamily; font.pixelSize: 8
                color: "#ccc"
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
                text: I18n.tr("Saved"); font.family: Style.fontFamily; font.pixelSize: 8; font.weight: Font.Medium
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
            visible: thumbDelegate.dlStatus === "downloading"
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
    visible: browser.whService && !browser.whService.loading && resultsModel.count === 0 && browser.whService.errorText === ""
    text: I18n.tr("Search wallhaven.cc for wallpapers, or browse the top list")
    font.family: Style.fontFamily; font.pixelSize: 12
    color: browser.colors ? Qt.rgba(browser.colors.surfaceText.r, browser.colors.surfaceText.g, browser.colors.surfaceText.b, 0.4)
                          : Qt.rgba(1, 1, 1, 0.3)
    anchors.centerIn: resultsGrid
  }

  onBrowserVisibleChanged: {
    if (browserVisible && whService && resultsModel.count === 0) {
      whService.search(1)
    } else if (browserVisible) {
      if (whService) whService.scanLocalFiles()
    } else {
      if (whService) whService.clearCache()
      resultsModel.clear()
      _previewWp = null
    }
  }

  onWhServiceChanged: {
    if (browserVisible && whService && resultsModel.count === 0) {
      whService.search(1)
    }
  }
  Item {
    anchors.fill: resultsGrid
    visible: browser.whService && browser.whService.loading

    enabled: false

    Text {
      anchors.centerIn: parent
      text: "\u{f051f}"
      font.family: Style.fontFamilyNerdIcons; font.pixelSize: 128
      color: browser.colors ? browser.colors.primary : Style.fallbackAccent
      opacity: browser.whService && browser.whService.loading ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.animFast } }
      RotationAnimation on rotation { from: 0; to: 360; duration: Style.animSpin; loops: Animation.Infinite; running: browser.whService && browser.whService.loading }
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
      source: browser._previewWp ? browser._previewWp.path : ""
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

        Row {
          spacing: 5; anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "\u{f0a39}"
            font.family: Style.fontFamilyNerdIcons; font.pixelSize: 14
            color: browser.colors ? browser.colors.primary : Style.fallbackAccent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: browser._previewWp ? browser._previewWp.resolution : ""
            font.family: Style.fontFamily; font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.85)
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          spacing: 5; anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "\u{f0224}"
            font.family: Style.fontFamilyNerdIcons; font.pixelSize: 14
            color: browser.colors ? browser.colors.primary : Style.fallbackAccent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: browser._previewWp ? _formatSize(browser._previewWp.fileSize) : ""
            font.family: Style.fontFamily; font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.65)
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Rectangle {
          width: catText.implicitWidth + 12; height: 24; radius: 4
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(1, 1, 1, 0.1)
          Text {
            id: catText; anchors.centerIn: parent
            text: browser._previewWp ? browser._previewWp.category : ""
            font.family: Style.fontFamily; font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.7)
          }
        }

        Rectangle {
          width: purText.implicitWidth + 12; height: 24; radius: 4
          anchors.verticalCenter: parent.verticalCenter
          color: {
            var p = browser._previewWp ? browser._previewWp.purity : ""
            return p === "sfw" ? Qt.rgba(0.3, 0.8, 0.3, 0.2)
                 : p === "sketchy" ? Qt.rgba(1, 0.8, 0, 0.2)
                 : Qt.rgba(1, 0.3, 0.3, 0.2)
          }
          Text {
            id: purText; anchors.centerIn: parent
            text: browser._previewWp ? browser._previewWp.purity : ""
            font.family: Style.fontFamily; font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.8)
          }
        }

        Rectangle { width: 1; height: 24; color: Qt.rgba(1,1,1,0.15); anchors.verticalCenter: parent.verticalCenter }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: -3

          property string _dlSt: {
            if (!browser.whService || !browser._previewWp) return ""
            var s = browser.whService.downloadStatus
            return s[browser._previewWp.id] || ""
          }
          property bool _isLocal: {
            if (!browser.whService || !browser._previewWp) return false
            return !!browser.whService.localWallhavenIds[browser._previewWp.id]
          }

          ActionButton {
            colors: browser.colors
            icon: (parent._dlSt === "done" || parent._isLocal) ? "\u{f012c}" : (parent._dlSt === "error" ? "\u{f0159}" : "\u{f01da}")
            label: (parent._dlSt === "done" || parent._isLocal) ? I18n.tr("Saved") : (parent._dlSt === "downloading" ? I18n.tr("Downloading...") : (parent._dlSt === "error" ? I18n.tr("Error") : I18n.tr("Download")))
            tooltip: I18n.tr("Save to wallpaper folder")
            onClicked: {
              if (parent._dlSt === "done" || parent._isLocal || parent._dlSt === "downloading" || !browser._previewWp) return
              browser.whService.downloadWallpaper(browser._previewWp.id, browser._previewWp.path)
            }
          }

          ActionButton {
            colors: browser.colors
            icon: "\u{f0e56}"; label: I18n.tr("Apply")
            tooltip: I18n.tr("Download and set as wallpaper")
            visible: parent._dlSt !== "done" && !parent._isLocal
            onClicked: {
              if (!browser._previewWp || parent._dlSt === "downloading") return
              browser._pendingApplyId = browser._previewWp.id
              browser.whService.downloadWallpaper(browser._previewWp.id, browser._previewWp.path)
            }
          }

          ActionButton {
            colors: browser.colors
            icon: "\u{f0e56}"; label: I18n.tr("Apply")
            tooltip: I18n.tr("Set as wallpaper")
            visible: parent._dlSt === "done" || parent._isLocal
            onClicked: {
              if (!browser._previewWp) return
              browser._applyLocalWallhaven(browser._previewWp.id)
            }
          }

          ActionButton {
            colors: browser.colors
            icon: "\u{f01b4}"; label: I18n.tr("Delete")
            danger: true
            tooltip: I18n.tr("Delete from wallpaper folder")
            visible: parent._dlSt === "done" || parent._isLocal
            onClicked: {
              if (!browser._previewWp) return
              browser._deleteWallhaven(browser._previewWp.id)
            }
          }
        }
      }
    }
  }

  Connections {
    target: browser.whService
    function onDownloadFinished(wallhavenId, localPath) {
      if (wallhavenId === browser._pendingApplyId && localPath !== "") {
        browser._pendingApplyId = ""
        DaemonClient.applyStatic(localPath, [], [])
      }
    }
  }

  function _applyLocalWallhaven(whId) {
    var safeId = whId.replace(/[^a-zA-Z0-9]/g, "")
    _applyLookupProc.command = ["find", Config.wallpaperDir, "-maxdepth", "1", "-name", "wallhaven-" + safeId + ".*", "-not", "-name", "*.tmp", "-print", "-quit"]
    _applyLookupProc.running = true
  }

  property string _applyLookupResult: ""
  property var _applyLookupProc: Process {
    stdout: SplitParser {
      onRead: data => { browser._applyLookupResult = data.trim() }
    }
    onExited: {
      if (browser._applyLookupResult !== "")
        DaemonClient.applyStatic(browser._applyLookupResult, [], [])
      browser._applyLookupResult = ""
    }
  }

  function _deleteWallhaven(whId) {
    var safeId = whId.replace(/[^a-zA-Z0-9]/g, "")
    _deleteLookupProc.command = ["find", Config.wallpaperDir, "-maxdepth", "1", "-name", "wallhaven-" + safeId + ".*", "-not", "-name", "*.tmp", "-print", "-quit"]
    _deleteLookupProc._whId = safeId
    _deleteLookupProc.running = true
  }

  property var _deleteLookupProc: Process {
    property string _whId: ""
    property string _foundPath: ""
    stdout: SplitParser {
      onRead: data => { browser._deleteLookupProc._foundPath = data.trim() }
    }
    onExited: {
      if (_foundPath !== "") {
        _deleteFileProc.command = ["rm", "-f", _foundPath]
        _deleteFileProc.running = true
      }
      if (_whId !== "" && browser.whService) {
        var ids = Object.assign({}, browser.whService.localWallhavenIds)
        delete ids[_whId]
        browser.whService.localWallhavenIds = ids
        var st = Object.assign({}, browser.whService.downloadStatus)
        delete st[_whId]
        browser.whService.downloadStatus = st
      }
      _foundPath = ""
      _whId = ""
    }
  }

  property var _deleteFileProc: Process {
    onExited: {
      if (browser.whService) browser.whService.scanLocalFiles()
    }
  }


  function _formatSize(bytes) {
    if (!bytes || bytes <= 0) return ""
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1048576) return (bytes / 1024).toFixed(0) + " KB"
    return (bytes / 1048576).toFixed(1) + " MB"
  }
}
