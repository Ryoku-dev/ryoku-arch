pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../components"
import Ryoku.Ui.Singletons

// The rice workshop: a wide info-and-manage drawer opened by clicking a rice in
// the carousel, instead of applying it on the spot. The left half previews the
// look; the right half reads its identity and what applying it touches, then
// fences the actions into groups -- apply and manage together, save/export/
// import in a separate share group.
FocusScope {
  id: root

  property var colors
  property var rice: null
  property bool open: false

  signal applyRequested(string slug)
  signal forkRequested(string slug)
  signal restoreRequested()
  signal deleteRequested(string slug, string name)
  signal saveLookRequested()
  signal exportRequested(string slug, string folder)
  signal importRequested(string folder)
  signal closeRequested()

  readonly property color _ink: colors ? colors.surfaceText : "#e0e2e8"
  readonly property color _inkDim: colors ? colors.surfaceVariantText : "#c2c7cf"
  readonly property color _surface: colors ? colors.surface : "#131313"
  readonly property color _lift: colors ? colors.surfaceContainer : "#1a1a1a"
  readonly property color _accent: colors ? colors.primary : Style.fallbackAccent

  readonly property string _slug: rice ? ("" + (rice.slug || "")) : ""
  readonly property string _name: rice ? ("" + (rice.name || rice.slug || "")) : ""
  readonly property string _author: rice ? ("" + (rice.author || "")) : ""
  readonly property string _blurb: rice ? ("" + (rice.blurb || "")) : ""
  readonly property string _compat: rice ? ("" + (rice.compat || "")) : ""
  readonly property string _createdWith: rice ? ("" + (rice.createdWith || "")) : ""
  readonly property string _preview: rice ? ("" + (rice.preview || "")) : ""
  readonly property bool _live: rice ? rice.live === true : false
  readonly property bool _active: rice ? rice.active === true : false
  readonly property var _tags: (rice && ("" + (rice.tags || "")) !== "") ? ("" + rice.tags).split(",") : []

  property string _touchBuf: ""
  property string _pickBuf: ""
  property string _pickMode: ""

  Keys.onEscapePressed: root.closeRequested()
  Component.onCompleted: { forceActiveFocus(); _loadTouches() }

  function _loadTouches() {
    touchModel.clear()
    if (root._slug === "") return
    root._touchBuf = ""
    _filesProc.command = ["ryoku-hub", "rice", "files", root._slug]
    _filesProc.running = true
  }

  // Native folder picker for export/import; the chosen path is emitted back to
  // the parent, which runs the CLI. zenity first, kdialog as a fallback.
  function _pick(mode) {
    var title = mode === "export" ? "Export rice to folder" : "Import rice from folder"
    root._pickMode = mode
    root._pickBuf = ""
    _pickProc.command = ["sh", "-c",
      "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --title='" + title + "'; "
      + "elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\" --title '" + title + "'; fi"]
    _pickProc.running = true
  }

  ListModel { id: touchModel }

  Process {
    id: _filesProc
    stdout: SplitParser { splitMarker: ""; onRead: data => root._touchBuf += data }
    onExited: {
      touchModel.clear()
      var d = null
      try { d = JSON.parse(root._touchBuf) } catch (e) { d = null }
      var t = (d && d.touches) ? d.touches : []
      for (var i = 0; i < t.length; i++) {
        if (t[i].provided === true)
          touchModel.append({ touchLabel: "" + (t[i].label || "") })
      }
    }
  }

  Process {
    id: _pickProc
    stdout: SplitParser { splitMarker: ""; onRead: data => root._pickBuf += data }
    onExited: {
      var path = root._pickBuf.trim()
      if (path === "") return
      if (root._pickMode === "export") root.exportRequested(root._slug, path)
      else root.importRequested(path)
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.closeRequested() }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property color tint: root._inkDim
    property bool strong: false
    implicitWidth: _chipText.implicitWidth + 16 * Config.uiScale
    height: 20 * Config.uiScale
    radius: Style.radiusRound
    color: chip.strong ? Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.16) : "transparent"
    border.width: 1
    border.color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, chip.strong ? 0.55 : 0.3)
    Text {
      id: _chipText
      anchors.centerIn: parent
      text: I18n.tr(chip.label)
      font.family: Style.fontFamily; font.pixelSize: 9 * Config.uiScale
      font.weight: Font.Medium; font.letterSpacing: 0.8
      color: chip.strong ? chip.tint : root._inkDim
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 100 * Config.uiScale, 860 * Config.uiScale)
    height: Math.min(parent.height - 100 * Config.uiScale, 470 * Config.uiScale)
    radius: Style.radiusLarge
    color: root._surface
    border.width: 1
    border.color: Qt.rgba(root._ink.r, root._ink.g, root._ink.b, 0.18)
    MouseArea { anchors.fill: parent }

    Text {
      id: closeBtn
      anchors.top: parent.top; anchors.right: parent.right
      anchors.topMargin: 12 * Config.uiScale; anchors.rightMargin: 14 * Config.uiScale
      text: "\u00d7"
      font.family: Style.fontFamily; font.pixelSize: 20 * Config.uiScale
      color: closeMouse.containsMouse ? root._ink : root._inkDim
      z: 5
      MouseArea {
        id: closeMouse
        anchors.fill: parent; anchors.margins: -8
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.closeRequested()
      }
    }

    Row {
      anchors.fill: parent
      anchors.margins: 22 * Config.uiScale
      spacing: 22 * Config.uiScale

      Rectangle {
        id: preview
        width: (parent.width - parent.spacing) * 0.42
        height: parent.height
        radius: Style.radiusMedium
        clip: true
        color: root._lift

        Image {
          anchors.fill: parent
          visible: root._preview !== "" && status === Image.Ready
          source: root._preview
          fillMode: Image.PreserveAspectCrop
          asynchronous: true; cache: false
          sourceSize.width: 520; sourceSize.height: 640
        }
        Text {
          anchors.centerIn: parent
          visible: root._preview === ""
          text: root._name.length > 0 ? root._name.charAt(0).toUpperCase() : "?"
          font.family: Style.fontFamilyHeading; font.pixelSize: 120 * Config.uiScale
          color: Qt.rgba(root._inkDim.r, root._inkDim.g, root._inkDim.b, 0.25)
        }
        Rectangle {
          anchors.fill: parent; radius: parent.radius; color: "transparent"
          border.width: 1; border.color: Qt.rgba(root._ink.r, root._ink.g, root._ink.b, 0.12)
        }
      }

      Item {
        width: parent.width - preview.width - parent.spacing
        height: parent.height

        Column {
          id: infoCol
          anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
          spacing: 8 * Config.uiScale

          Text {
            visible: root._author !== ""
            text: root._author.toUpperCase()
            font.family: Style.fontFamily; font.pixelSize: 9 * Config.uiScale
            font.weight: Font.Medium; font.letterSpacing: 2
            color: root._inkDim
          }
          Text {
            width: parent.width
            text: root._name
            font.family: Style.fontFamilyHeading; font.pixelSize: 26 * Config.uiScale
            color: root._ink; elide: Text.ElideRight; maximumLineCount: 1
          }
          Flow {
            width: parent.width; spacing: 6 * Config.uiScale
            Chip { visible: root._compat !== ""; label: root._compat.toUpperCase(); strong: true }
            Chip { visible: root._createdWith !== ""; label: "v" + root._createdWith }
            Chip { visible: root._live; label: I18n.tr("LIVE"); tint: root._accent; strong: true }
            Chip { visible: root._active; label: I18n.tr("ACTIVE"); tint: root._accent; strong: true }
            Repeater {
              model: root._tags
              Chip {
                required property string modelData
                label: modelData.trim()
              }
            }
          }
          Text {
            visible: root._blurb !== ""
            width: parent.width
            text: root._blurb
            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
            font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
            color: root._inkDim
          }
          SectionTitle { colors: root.colors; text: I18n.tr("TOUCHES") }
          Flow {
            width: parent.width; spacing: 6 * Config.uiScale
            Repeater {
              model: touchModel
              Chip {
                required property string touchLabel
                label: touchLabel
              }
            }
            Text {
              visible: touchModel.count === 0
              text: "\u2014"
              font.family: Style.fontFamily; font.pixelSize: 11 * Config.uiScale
              color: Qt.rgba(root._inkDim.r, root._inkDim.g, root._inkDim.b, 0.6)
            }
          }
        }

        Column {
          anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
          spacing: 10 * Config.uiScale

          Row {
            spacing: 8 * Config.uiScale
            FilterButton {
              colors: root.colors; label: I18n.tr("APPLY"); register: false
              height: 30 * Config.uiScale
              hasActiveColor: true; activeColor: root._accent; isActive: true
              onClicked: if (root._slug !== "") root.applyRequested(root._slug)
            }
            FilterButton {
              colors: root.colors; label: I18n.tr("FORK"); register: false; height: 30 * Config.uiScale
              tooltip: I18n.tr("Duplicate this rice to tweak")
              onClicked: if (root._slug !== "") root.forkRequested(root._slug)
            }
            FilterButton {
              colors: root.colors; label: I18n.tr("RESTORE"); register: false; height: 30 * Config.uiScale
              tooltip: I18n.tr("Revert the desktop to your original setup")
              onClicked: root.restoreRequested()
            }
            FilterButton {
              colors: root.colors; label: I18n.tr("DELETE"); register: false; height: 30 * Config.uiScale
              hasActiveColor: true; activeColor: root.colors ? root.colors.error : "#e2342a"; isActive: true
              onClicked: if (root._slug !== "") root.deleteRequested(root._slug, root._name)
            }
          }

          SectionTitle { colors: root.colors; text: I18n.tr("SHARE") }

          Row {
            spacing: 8 * Config.uiScale
            FilterButton {
              colors: root.colors; label: I18n.tr("SAVE LOOK"); register: false; height: 30 * Config.uiScale
              tooltip: I18n.tr("Capture the current desktop as a new rice")
              onClicked: root.saveLookRequested()
            }
            FilterButton {
              colors: root.colors; label: I18n.tr("EXPORT"); register: false; height: 30 * Config.uiScale
              tooltip: I18n.tr("Export this rice to a folder")
              onClicked: if (root._slug !== "") root._pick("export")
            }
            FilterButton {
              colors: root.colors; label: I18n.tr("IMPORT"); register: false; height: 30 * Config.uiScale
              tooltip: I18n.tr("Import a rice folder")
              onClicked: root._pick("import")
            }
          }
        }
      }
    }
  }
}
