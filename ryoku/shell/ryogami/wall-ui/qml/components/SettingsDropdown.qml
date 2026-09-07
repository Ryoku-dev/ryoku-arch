import QtQuick
import ".."
import Ryoku.Ui.Singletons

Column {
  id: root
  property var colors
  property string label: ""
  property string value: ""
  property var model: []
  property var onSelect
  property bool _open: false

  width: parent ? parent.width : 0
  spacing: 2 * Config.uiScale

  Text {
    visible: root.label !== ""
    text: I18n.tr(root.label)
    font.family: Style.fontFamily
    font.pixelSize: 11 * Config.uiScale
    font.weight: Font.Medium
    color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
  }

  Item {
    id: trigger
    width: parent.width
    height: 28 * Config.uiScale
    z: 5

    Rectangle {
      anchors.fill: parent
      color: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.85) : Qt.rgba(0.1, 0.12, 0.18, 0.85)
      border.color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.20) : Qt.rgba(1, 1, 1, 0.10)
      border.width: 1
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10 * Config.uiScale
      anchors.verticalCenter: parent.verticalCenter
      text: {
        for (var i = 0; i < root.model.length; i++) {
          if (root.model[i].mode === root.value) return root.model[i].label
        }
        return root.value
      }
      font.family: Style.fontFamily
      font.pixelSize: 12 * Config.uiScale
      color: root.colors ? root.colors.surfaceText : "#ffffff"
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 10 * Config.uiScale
      anchors.verticalCenter: parent.verticalCenter
      text: root._open ? "▲" : "▼"
      font.pixelSize: 9 * Config.uiScale
      color: root.colors ? root.colors.tertiary : Qt.rgba(1, 1, 1, 0.5)
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root._open = !root._open
    }
  }

  Rectangle {
    visible: root._open
    width: parent.width
    height: visible ? optionsCol.implicitHeight + 8 * Config.uiScale : 0
    color: root.colors ? Qt.rgba(root.colors.surfaceContainer.r, root.colors.surfaceContainer.g, root.colors.surfaceContainer.b, 0.95) : Qt.rgba(0.1, 0.12, 0.18, 0.95)
    border.color: root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.20) : Qt.rgba(1, 1, 1, 0.10)
    border.width: 1

    Column {
      id: optionsCol
      width: parent.width
      anchors.top: parent.top
      anchors.topMargin: 4 * Config.uiScale

      Repeater {
        model: root.model
        Item {
          width: optionsCol.width
          height: 24 * Config.uiScale

          property bool _isActive: modelData.mode === root.value

          Rectangle {
            anchors.fill: parent
            color: optMouse.containsMouse
              ? (root.colors ? Qt.rgba(root.colors.primary.r, root.colors.primary.g, root.colors.primary.b, 0.18) : Qt.rgba(1, 1, 1, 0.06))
              : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 12 * Config.uiScale
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr(modelData.label)
            font.family: Style.fontFamily
            font.pixelSize: 12 * Config.uiScale
            font.weight: parent._isActive ? Font.Bold : Font.Normal
            color: parent._isActive
              ? (root.colors ? root.colors.primary : "#7986cb")
              : (root.colors ? root.colors.surfaceText : "#ffffff")
          }

          MouseArea {
            id: optMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.onSelect) root.onSelect(modelData.mode)
              root._open = false
            }
          }
        }
      }
    }
  }
}
