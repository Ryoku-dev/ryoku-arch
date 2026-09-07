import QtQuick
import QtQuick.Shapes
import ".."
import "../.."
import "../../components"
import "../../services"
import Ryoku.Ui.Singletons

// Playlists settings tab: reimplements skwd-wall V2's playlists panel
// (src/frontend/playlists). Index of playlists + a detail editor (name, dwell,
// kind, smart source, member list with reorder/remove, per-output assignment,
// play-now, delete) and a catalog picker for adding curated members. All state
// lives in the ryogami daemon behind the playlist.* RPC verbs.
Flow {
  id: root
  property var colors
  property var saveConfigKey // unused; playlists persist daemon-side

  width: parent ? parent.width : 0
  spacing: 12

  property var _lists: []
  property var _assignments: []
  property var _outputs: []
  property int _selected: -1
  property var _members: []
  property bool _adding: false
  property var _catalog: []

  Component.onCompleted: root.refresh()

  Connections {
    target: DaemonClient
    function onEventReceived(event, data) {
      if (event === "ryogami.playlist.changed") {
        root.refresh()
        if (root._selected >= 0) root.refreshMembers()
      }
    }
  }

  function refresh() {
    DaemonClient.call("playlist.list", {}, function(res, err) {
      if (err || !res) return
      root._lists = res.playlists || []
      root._assignments = res.assignments || []
      root._outputs = res.outputs || []
      if (root._selected < 0 && root._lists.length > 0)
        root.select(root._lists[0].id)
      else if (root._selected >= 0 && !root._byId(root._selected) && root._lists.length > 0)
        root.select(root._lists[0].id)
      else if (root._lists.length === 0)
        root._selected = -1
    })
  }

  function refreshMembers() {
    DaemonClient.call("playlist.members", { id: root._selected }, function(res, err) {
      if (err || !res) return
      root._members = res.members || []
    })
  }

  function select(id) {
    root._selected = id
    root._adding = false
    root.refreshMembers()
  }

  function _byId(id) {
    for (var i = 0; i < root._lists.length; i++)
      if (root._lists[i].id === id) return root._lists[i]
    return null
  }

  function _assignedTo(output) {
    for (var i = 0; i < root._assignments.length; i++)
      if (root._assignments[i].output === output) return root._assignments[i].id
    return -1
  }

  function _isMember(key) {
    for (var i = 0; i < root._members.length; i++)
      if (root._members[i].key === key) return true
    return false
  }

  function _call(method, params) {
    DaemonClient.call(method, params, function(res, err) {
      root.refresh()
      if (root._selected >= 0) root.refreshMembers()
    })
  }

  // ---- index card ----
  SettingsCard {
    colors: root.colors
    title: I18n.tr("Playlists")
    width: (parent.width - parent.spacing) * 0.42

    // Stacked creator: label above a full-width field. The stock RowTextInput
    // pins a fixed 220px input beside the title, which collides with the title
    // in this narrow 42%-wide card.
    Item {
      width: parent ? parent.width : 0
      implicitHeight: newCol.implicitHeight + 14 * Config.uiScale

      Column {
        id: newCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 18 * Config.uiScale
        anchors.rightMargin: 14 * Config.uiScale
        spacing: 4 * Config.uiScale

        Text {
          text: I18n.tr("New playlist")
          font.family: Style.fontFamily
          font.pixelSize: 12 * Config.uiScale
          font.weight: Font.Medium
          color: root.colors ? root.colors.surfaceText : "#ffffff"
        }

        Item {
          id: tinBox
          width: parent.width
          height: 28 * Config.uiScale
          readonly property int _ch: 5

          Shape {
            id: tinShape
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.92) : Qt.rgba(0.15, 0.15, 0.2, 0.92)
              strokeColor: newInput.activeFocus
                ? (root.colors ? root.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0))
                : (root.colors ? Qt.rgba(root.colors.outline.r, root.colors.outline.g, root.colors.outline.b, 0.28) : Qt.rgba(1, 1, 1, 0.14))
              strokeWidth: newInput.activeFocus ? 2 : 1
              Behavior on strokeColor { ColorAnimation { duration: 120 } }
              startX: tinBox._ch; startY: 0
              PathLine { x: tinShape.width;              y: 0 }
              PathLine { x: tinShape.width;              y: tinShape.height - tinBox._ch }
              PathLine { x: tinShape.width - tinBox._ch; y: tinShape.height }
              PathLine { x: 0;                           y: tinShape.height }
              PathLine { x: 0;                           y: tinBox._ch }
              PathLine { x: tinBox._ch;                  y: 0 }
            }
          }

          TextInput {
            id: newInput
            anchors.fill: parent
            anchors.leftMargin: 10 * Config.uiScale
            anchors.rightMargin: 10 * Config.uiScale
            verticalAlignment: TextInput.AlignVCenter
            font.family: Style.fontFamily
            font.pixelSize: 12 * Config.uiScale
            color: root.colors ? root.colors.surfaceText : "#ffffff"
            clip: true
            selectByMouse: true
            onAccepted: {
              var name = (text || "").trim()
              if (name === "") return
              DaemonClient.call("playlist.create", { name: name }, function(res) {
                if (res && res.id !== undefined) { root.refresh(); root.select(res.id) }
              })
              text = ""
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              text: I18n.tr("Name, then Enter")
              font: parent.font
              color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.3) : Qt.rgba(1, 1, 1, 0.2)
              visible: !parent.text && !parent.activeFocus
            }
          }
        }
      }
    }

    Repeater {
      model: root._lists
      RowAction {
        colors: root.colors
        title: (root._selected === modelData.id ? "\u25B8  " : "") + modelData.name
        description: I18n.tr("%1 · %2 items").arg(modelData.kind === "smart" ? I18n.tr("Smart") : I18n.tr("Curated")).arg(modelData.count)
        valueLabel: root._outputsFor(modelData.id)
        onClicked: root.select(modelData.id)
      }
    }

    Text {
      visible: root._lists.length === 0
      text: I18n.tr("No playlists yet. Create one above.")
      font.family: Style.fontFamily
      font.pixelSize: 11 * Config.uiScale
      color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.5) : Qt.rgba(1, 1, 1, 0.4)
    }
  }

  function _outputsFor(id) {
    var n = 0
    for (var i = 0; i < root._assignments.length; i++)
      if (root._assignments[i].id === id) n++
    return n > 0 ? (n === 1 ? I18n.tr("%1 screen").arg(n) : I18n.tr("%1 screens").arg(n)) : ""
  }

  // ---- detail card ----
  SettingsCard {
    id: detail
    colors: root.colors
    visible: root._selected >= 0
    property var pl: root._byId(root._selected)
    title: pl ? pl.name : I18n.tr("Details")
    width: (parent.width - parent.spacing) * 0.55

    RowTextInput {
      colors: root.colors
      title: I18n.tr("Name")
      value: detail.pl ? detail.pl.name : ""
      onCommit: function(v) { if (v && v.trim() !== "") root._call("playlist.update", { id: root._selected, field: "name", value: v.trim() }) }
    }

    RowInput {
      colors: root.colors
      title: I18n.tr("Dwell")
      suffix: " s"
      min: 5; max: 86400
      value: detail.pl ? detail.pl.dwell : 300
      onCommit: function(v) { root._call("playlist.update", { id: root._selected, field: "dwell", value: String(Math.round(v)) }) }
    }

    RowDropdown {
      colors: root.colors
      title: I18n.tr("Kind")
      model: [ { mode: "curated", label: I18n.tr("Curated") }, { mode: "smart", label: I18n.tr("Smart") } ]
      value: detail.pl ? (detail.pl.kind || "curated") : "curated"
      onSelect: function(v) { root._call("playlist.update", { id: root._selected, field: "kind", value: v }) }
    }

    RowTextInput {
      visible: detail.pl && detail.pl.kind === "smart"
      colors: root.colors
      title: I18n.tr("Query")
      placeholder: I18n.tr("Match by name")
      value: detail.pl && detail.pl.source ? detail.pl.source : ""
      onCommit: function(v) { root._call("playlist.update", { id: root._selected, field: "source", value: v || "" }) }
    }

    SectionTitle { colors: root.colors; text: I18n.tr("OUTPUTS") }

    Repeater {
      model: root._outputs
      RowToggle {
        colors: root.colors
        title: modelData
        description: I18n.tr("Rotate this playlist on %1").arg(modelData)
        checked: root._assignedTo(modelData) === root._selected
        onToggle: function(v) { root._call("playlist.toggle", { output: modelData, id: root._selected }) }
      }
    }

    Text {
      visible: root._outputs.length === 0
      text: I18n.tr("No outputs detected.")
      font.family: Style.fontFamily
      font.pixelSize: 11 * Config.uiScale
      color: root.colors ? Qt.rgba(root.colors.surfaceText.r, root.colors.surfaceText.g, root.colors.surfaceText.b, 0.5) : Qt.rgba(1, 1, 1, 0.4)
    }

    SectionTitle {
      colors: root.colors
      text: I18n.tr("MEMBERS")
      visible: detail.pl && detail.pl.kind !== "smart"
    }

    // member rows: thumb + name + reorder/remove
    Repeater {
      model: (detail.pl && detail.pl.kind !== "smart") ? root._members : []
      Item {
        width: parent ? parent.width : 0
        height: 40 * Config.uiScale

        Image {
          id: mthumb
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: 48 * Config.uiScale; height: 30 * Config.uiScale
          fillMode: Image.PreserveAspectCrop
          clip: true
          asynchronous: true
          cache: false
          source: modelData.thumb_sm ? ("file://" + modelData.thumb_sm) : (modelData.thumb ? ("file://" + modelData.thumb) : "")
        }
        Text {
          anchors.left: mthumb.right
          anchors.leftMargin: 10 * Config.uiScale
          anchors.right: mctl.left
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: modelData.key ? modelData.key.split("/").pop() : "?"
          font.family: Style.fontFamily
          font.pixelSize: 11 * Config.uiScale
          color: root.colors ? root.colors.surfaceText : "#fff"
        }
        Row {
          id: mctl
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4 * Config.uiScale
          FilterButton { colors: root.colors; icon: "\u2191"; skew: 4; onClicked: root._call("playlist.move", { id: root._selected, key: modelData.key, delta: -1 }) }
          FilterButton { colors: root.colors; icon: "\u2193"; skew: 4; onClicked: root._call("playlist.move", { id: root._selected, key: modelData.key, delta: 1 }) }
          FilterButton { colors: root.colors; icon: "\u2715"; skew: 4; onClicked: root._call("playlist.remove", { id: root._selected, key: modelData.key }) }
        }
      }
    }

    // add-from-catalog toggle + grid
    FilterButton {
      visible: detail.pl && detail.pl.kind !== "smart"
      colors: root.colors
      label: root._adding ? I18n.tr("DONE ADDING") : I18n.tr("+ ADD WALLPAPERS")
      skew: 8
      onClicked: {
        root._adding = !root._adding
        if (root._adding && root._catalog.length === 0)
          DaemonClient.listWallpapers(false, function(res, err) { if (!err && res) root._catalog = res.wallpapers || [] })
      }
    }

    Flow {
      visible: root._adding && detail.pl && detail.pl.kind !== "smart"
      width: parent.width
      spacing: 6 * Config.uiScale
      Repeater {
        model: root._adding ? root._catalog : []
        Item {
          width: 84 * Config.uiScale; height: 52 * Config.uiScale
          Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            clip: true
            asynchronous: true
            cache: false
            source: modelData.thumb_sm ? ("file://" + modelData.thumb_sm) : (modelData.thumb ? ("file://" + modelData.thumb) : "")
          }
          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: root._isMember(modelData.key) ? 2 : 1
            border.color: root._isMember(modelData.key)
              ? (root.colors ? root.colors.primary : "#8bceff")
              : Qt.rgba(1, 1, 1, 0.15)
          }
          Rectangle {
            visible: root._isMember(modelData.key)
            anchors.top: parent.top; anchors.right: parent.right
            width: 16 * Config.uiScale; height: 16 * Config.uiScale
            color: root.colors ? root.colors.primary : "#8bceff"
            Text {
              anchors.centerIn: parent; text: "\u2713"
              font.pixelSize: 11 * Config.uiScale
              color: root.colors ? root.colors.primaryText : "#000"
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root._isMember(modelData.key))
                root._call("playlist.remove", { id: root._selected, key: modelData.key })
              else
                root._call("playlist.add", { id: root._selected, key: modelData.key })
            }
          }
        }
      }
    }

    SectionTitle { colors: root.colors; text: I18n.tr("ACTIONS") }

    RowAction {
      colors: root.colors
      title: I18n.tr("Play now")
      description: I18n.tr("Apply the current wallpaper immediately.")
      valueLabel: "\u25B6"
      onClicked: DaemonClient.call("playlist.play_now", { id: root._selected }, function() {})
    }

    FilterButton {
      colors: root.colors
      label: I18n.tr("DELETE PLAYLIST")
      skew: 8
      hasActiveColor: true
      activeColor: "#c62828"
      isActive: true
      onClicked: {
        DaemonClient.call("playlist.delete", { id: root._selected }, function() {
          root._selected = -1
          root.refresh()
        })
      }
    }
  }
}
