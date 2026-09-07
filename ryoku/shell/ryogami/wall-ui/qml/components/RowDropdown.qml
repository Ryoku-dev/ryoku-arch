import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import ".."
import Ryoku.Ui.Singletons

SettingsRow {
  id: row
  property var model: []
  property string value: ""
  property var onSelect
  property bool _open: false

  readonly property string _currentLabel: {
    for (var i = 0; i < model.length; i++) {
      if (model[i].mode === value) return model[i].label
    }
    return value
  }

  Item {
    id: trigger
    width: 220 * Config.uiScale
    height: 28 * Config.uiScale
    readonly property int _ch: 5

    Shape {
      id: trigShape
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: row.colors ? Qt.rgba(row.colors.surfaceContainer.r, row.colors.surfaceContainer.g, row.colors.surfaceContainer.b, 0.92) : Qt.rgba(0.15, 0.15, 0.2, 0.92)
        strokeColor: row._open
          ? (row.colors ? row.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0))
          : (row.colors ? Qt.rgba(row.colors.outline.r, row.colors.outline.g, row.colors.outline.b, 0.28) : Qt.rgba(1, 1, 1, 0.14))
        strokeWidth: row._open ? 2 : 1
        Behavior on strokeColor { ColorAnimation { duration: 160 } }
        startX: trigger._ch; startY: 0
        PathLine { x: trigShape.width;               y: 0 }
        PathLine { x: trigShape.width;               y: trigShape.height - trigger._ch }
        PathLine { x: trigShape.width - trigger._ch; y: trigShape.height }
        PathLine { x: 0;                              y: trigShape.height }
        PathLine { x: 0;                              y: trigger._ch }
        PathLine { x: trigger._ch;                    y: 0 }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10 * Config.uiScale
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: chevron.left
      anchors.rightMargin: 8 * Config.uiScale
      text: row._currentLabel
      elide: Text.ElideRight
      font.family: Style.fontFamily
      font.pixelSize: 12 * Config.uiScale
      color: row.colors ? row.colors.surfaceText : "#ffffff"
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: 10 * Config.uiScale
      anchors.verticalCenter: parent.verticalCenter
      text: "▾"
      font.pixelSize: 11 * Config.uiScale
      color: row._open
        ? (row.colors ? row.colors.primary : Qt.rgba(0.5, 0.7, 1.0, 1.0))
        : (row.colors ? Qt.rgba(row.colors.surfaceText.r, row.colors.surfaceText.g, row.colors.surfaceText.b, 0.55) : Qt.rgba(1, 1, 1, 0.4))
      rotation: row._open ? 180 : 0
      Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on color    { ColorAnimation  { duration: 160 } }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { mouse.accepted = true; row._open = !row._open }
    }
  }

  Item {
    id: backdrop
    parent: row.Window.contentItem
    visible: row._open
    anchors.fill: parent
    z: 9998
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: row._open = false
    }
  }

  Item {
    id: popup
    parent: row.Window.contentItem
    visible: row._open
    z: 9999
    width: popup._grouped ? (popup._leftW + trigger.width + 13 * Config.uiScale) : trigger.width
    height: Math.min(popup._grouped ? popup._groupedContentH : (optionsCol.implicitHeight + 8 * Config.uiScale), popup._maxH)
    readonly property int _ch: 7
    readonly property real _maxH: Math.max(160 * Config.uiScale, Screen.height - 120 * Config.uiScale)
    readonly property real _leftW: 118 * Config.uiScale

    readonly property bool _grouped: row.model && row.model.length > 0
      && row.model[0].category !== undefined && row.model[0].category !== ""
    readonly property var _groups: {
      var seen = ({}), out = []
      for (var i = 0; i < row.model.length; i++) {
        var c = row.model[i].category || ""
        if (c !== "" && seen[c] === undefined) { seen[c] = true; out.push(c) }
      }
      return out
    }
    property string _activeGroup: ""
    readonly property var _activeItems: {
      var out = []
      for (var i = 0; i < row.model.length; i++)
        if ((row.model[i].category || "") === popup._activeGroup) out.push(row.model[i])
      return out
    }
    readonly property real _groupedContentH: {
      var rh = 26 * Config.uiScale
      var counts = ({}), maxItems = 0
      for (var i = 0; i < row.model.length; i++) {
        var c = row.model[i].category || ""
        if (c !== "") { counts[c] = (counts[c] || 0) + 1; if (counts[c] > maxItems) maxItems = counts[c] }
      }
      return Math.max(popup._groups.length * rh, maxItems * rh) + 8 * Config.uiScale
    }
    function _groupOfValue() {
      for (var i = 0; i < row.model.length; i++)
        if (row.model[i].mode === row.value) return row.model[i].category || ""
      return ""
    }

    property real _belowY: 0
    property real _aboveY: 0
    property bool _flipUp: false

    function _sync() {
      if (!parent) return
      var below = trigger.mapToItem(parent, 0, trigger.height + 4)
      var above = trigger.mapToItem(parent, 0, -popup.height - 4)
      popup._belowY = below.y
      popup._aboveY = above.y
      popup._flipUp = (below.y + popup.height) > parent.height - 8
      var x = below.x
      if (x + popup.width > parent.width - 8) x = parent.width - popup.width - 8
      if (x < 8) x = 8
      popup.x = x
      var y = popup._flipUp ? popup._aboveY : popup._belowY
      if (y + popup.height > parent.height - 8) y = parent.height - popup.height - 8
      if (y < 8) y = 8
      popup.y = y
    }

    Timer {
      interval: 33
      running: row._open
      repeat: true
      onTriggered: popup._sync()
    }

    onVisibleChanged: if (visible) {
      if (popup._grouped) popup._activeGroup = popup._groupOfValue() || (popup._groups[0] || "")
      popup._sync()
    }

    Shape {
      id: popShape
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: row.colors ? Qt.rgba(row.colors.surfaceContainer.r, row.colors.surfaceContainer.g, row.colors.surfaceContainer.b, 0.97) : Qt.rgba(0.10, 0.12, 0.18, 0.97)
        strokeColor: row.colors ? Qt.rgba(row.colors.outline.r, row.colors.outline.g, row.colors.outline.b, 0.32) : Qt.rgba(1, 1, 1, 0.16)
        strokeWidth: 1
        startX: popup._ch; startY: 0
        PathLine { x: popShape.width;             y: 0 }
        PathLine { x: popShape.width;             y: popShape.height - popup._ch }
        PathLine { x: popShape.width - popup._ch; y: popShape.height }
        PathLine { x: 0;                          y: popShape.height }
        PathLine { x: 0;                          y: popup._ch }
        PathLine { x: popup._ch;                  y: 0 }
      }
    }

    Flickable {
      id: flick
      visible: !popup._grouped
      anchors.fill: parent
      anchors.topMargin: 4 * Config.uiScale
      anchors.bottomMargin: 4 * Config.uiScale
      clip: true
      contentWidth: width
      contentHeight: optionsCol.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
      id: optionsCol
      width: flick.width

      Repeater {
        model: row.model
        delegate: Column {
          id: optDelegate
          required property var modelData
          required property int index
          width: optionsCol.width
          readonly property bool _showHeader: modelData.category !== undefined && modelData.category !== ""
            && (index === 0 || (row.model[index - 1].category || "") !== modelData.category)

          Item {
            width: parent.width
            height: optDelegate._showHeader ? 20 * Config.uiScale : 0
            visible: optDelegate._showHeader

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10 * Config.uiScale
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 3 * Config.uiScale
              text: optDelegate.modelData.category || ""
              font.family: Style.fontFamily
              font.pixelSize: 9 * Config.uiScale
              font.weight: Font.Bold
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 1
              color: row.colors ? Qt.rgba(row.colors.surfaceText.r, row.colors.surfaceText.g, row.colors.surfaceText.b, 0.45) : Qt.rgba(1, 1, 1, 0.45)
            }
          }

          Item {
            width: parent.width
            height: 24 * Config.uiScale
            readonly property bool _isActive: optDelegate.modelData.mode === row.value

            Rectangle {
              anchors.fill: parent
              color: optMouse.containsMouse
                ? (row.colors ? Qt.rgba(row.colors.primary.r, row.colors.primary.g, row.colors.primary.b, 0.18) : Qt.rgba(1, 1, 1, 0.08))
                : "transparent"
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10 * Config.uiScale
              anchors.verticalCenter: parent.verticalCenter
              text: I18n.tr(optDelegate.modelData.label)
              font.family: Style.fontFamily
              font.pixelSize: 12 * Config.uiScale
              font.weight: parent._isActive ? Font.Bold : Font.Normal
              color: parent._isActive
                ? (row.colors ? row.colors.primary : "#7986cb")
                : (row.colors ? row.colors.surfaceText : "#ffffff")
            }

            MouseArea {
              id: optMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                mouse.accepted = true
                if (row.onSelect) row.onSelect(optDelegate.modelData.mode)
                row._open = false
              }
            }
          }
        }
      }
      }
    }

    Rectangle {
      visible: !popup._grouped && flick.interactive
      width: 3 * Config.uiScale
      radius: 1.5 * Config.uiScale
      anchors.right: parent.right
      anchors.rightMargin: 2 * Config.uiScale
      y: 4 * Config.uiScale + flick.visibleArea.yPosition * (popup.height - 8 * Config.uiScale)
      height: Math.max(18 * Config.uiScale, flick.visibleArea.heightRatio * (popup.height - 8 * Config.uiScale))
      color: row.colors ? Qt.rgba(row.colors.primary.r, row.colors.primary.g, row.colors.primary.b, 0.5) : Qt.rgba(1, 1, 1, 0.3)
    }

    Item {
      id: groupedPane
      visible: popup._grouped
      anchors.fill: parent
      anchors.margins: 4 * Config.uiScale

      Column {
        id: groupsCol
        anchors.left: parent.left
        anchors.top: parent.top
        width: popup._leftW

        Repeater {
          model: popup._groups
          delegate: Item {
            id: grpDelegate
            required property var modelData
            width: groupsCol.width
            height: 26 * Config.uiScale
            readonly property bool _sel: modelData === popup._activeGroup

            Rectangle {
              anchors.fill: parent
              color: grpDelegate._sel
                ? (row.colors ? Qt.rgba(row.colors.primary.r, row.colors.primary.g, row.colors.primary.b, 0.16) : Qt.rgba(1, 1, 1, 0.10))
                : (grpMouse.containsMouse ? (row.colors ? Qt.rgba(row.colors.primary.r, row.colors.primary.g, row.colors.primary.b, 0.08) : Qt.rgba(1, 1, 1, 0.05)) : "transparent")
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10 * Config.uiScale
              anchors.right: parent.right
              anchors.rightMargin: 14 * Config.uiScale
              anchors.verticalCenter: parent.verticalCenter
              text: grpDelegate.modelData
              elide: Text.ElideRight
              font.family: Style.fontFamily
              font.pixelSize: 11 * Config.uiScale
              font.weight: grpDelegate._sel ? Font.Bold : Font.Normal
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 0.5
              color: grpDelegate._sel
                ? (row.colors ? row.colors.primary : "#7986cb")
                : (row.colors ? Qt.rgba(row.colors.surfaceText.r, row.colors.surfaceText.g, row.colors.surfaceText.b, 0.75) : Qt.rgba(1, 1, 1, 0.7))
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: 7 * Config.uiScale
              anchors.verticalCenter: parent.verticalCenter
              visible: grpDelegate._sel
              text: "›"
              font.pixelSize: 13 * Config.uiScale
              color: row.colors ? row.colors.primary : "#7986cb"
            }

            MouseArea {
              id: grpMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: popup._activeGroup = grpDelegate.modelData
              onClicked: function(mouse) { mouse.accepted = true; popup._activeGroup = grpDelegate.modelData }
            }
          }
        }
      }

      Rectangle {
        id: paneDivider
        anchors.left: groupsCol.right
        anchors.leftMargin: 4 * Config.uiScale
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: row.colors ? Qt.rgba(row.colors.outline.r, row.colors.outline.g, row.colors.outline.b, 0.25) : Qt.rgba(1, 1, 1, 0.12)
      }

      Flickable {
        id: rightFlick
        anchors.left: paneDivider.right
        anchors.leftMargin: 4 * Config.uiScale
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: rightCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: rightCol
          width: rightFlick.width

          Repeater {
            model: popup._activeItems
            delegate: Item {
              id: optDelegate2
              required property var modelData
              width: rightCol.width
              height: 26 * Config.uiScale
              readonly property bool _isActive: modelData.mode === row.value

              Rectangle {
                anchors.fill: parent
                color: opt2Mouse.containsMouse
                  ? (row.colors ? Qt.rgba(row.colors.primary.r, row.colors.primary.g, row.colors.primary.b, 0.18) : Qt.rgba(1, 1, 1, 0.08))
                  : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10 * Config.uiScale
                anchors.right: parent.right
                anchors.rightMargin: 8 * Config.uiScale
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr(optDelegate2.modelData.label)
                elide: Text.ElideRight
                font.family: Style.fontFamily
                font.pixelSize: 12 * Config.uiScale
                font.weight: optDelegate2._isActive ? Font.Bold : Font.Normal
                color: optDelegate2._isActive
                  ? (row.colors ? row.colors.primary : "#7986cb")
                  : (row.colors ? row.colors.surfaceText : "#ffffff")
              }

              MouseArea {
                id: opt2Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  mouse.accepted = true
                  if (row.onSelect) row.onSelect(optDelegate2.modelData.mode)
                  row._open = false
                }
              }
            }
          }
        }
      }
    }
  }
}
