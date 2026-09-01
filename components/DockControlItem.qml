pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string controlCommand
  required property int slotSize
  required property int iconSize
  required property real magnification
  required property real magnificationRadius
  required property bool hoverGlowEnabled
  required property real hoverGlowOpacity
  required property real hoverGlowRadius
  required property real pointerPosition
  required property bool autoHide
  required property string position
  required property bool vertical
  signal settingsRequested()
  signal addApplicationRequested()
  signal autoHideToggled(bool enabled)
  signal contextMenuVisibilityChanged(bool visible)

  readonly property real itemCenter: (vertical ? y + height / 2 : x + width / 2)
  readonly property real distance: Math.abs(pointerPosition - itemCenter)
  readonly property real influence: pointerPosition < -1000
    ? 0
    : Math.exp(-(distance * distance) / (magnificationRadius * magnificationRadius))
  readonly property real iconScale: 1 + (magnification - 1) * influence

  function activate() {
    if (root.controlCommand)
      Quickshell.execDetached(["sh", "-lc", root.controlCommand])
  }

  width: vertical ? slotSize + 6 : slotSize
  height: vertical ? slotSize : slotSize + 6

  Item {
    id: iconContainer

    x: (root.width - root.iconSize) / 2
    y: (root.height - root.iconSize) / 2
    width: root.iconSize
    height: root.iconSize
    scale: root.iconScale
    transformOrigin: root.position === "top"
      ? Item.Top
      : root.position === "left"
        ? Item.Left
        : root.position === "right" ? Item.Right : Item.Bottom

    Behavior on scale {
      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    RectangularShadow {
      id: hoverGlow

      anchors.fill: parent
      radius: Math.min(width, height) * 0.34
      blur: Math.max(8, root.iconSize * root.hoverGlowRadius / 100)
      spread: Math.max(1, root.iconSize * 0.06)
      offset: Qt.vector2d(0, 0)
      color: Color.accent
      opacity: root.hoverGlowEnabled && mouse.hovered
        ? root.hoverGlowOpacity : 0
      z: -1

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    Item {
      id: sliderGlyph

      anchors.centerIn: parent
      width: parent.width * 0.72
      height: parent.height * 0.62
      opacity: 0.96

      Repeater {
        model: [0.26, 0.68, 0.42]

        Item {
          required property real modelData
          required property int index

          width: sliderGlyph.width
          height: sliderGlyph.height / 3
          y: index * height

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Math.max(2, root.iconSize * 0.055)
            radius: height / 2
            color: Color.foreground
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * modelData - width / 2
            width: Math.max(6, root.iconSize * 0.18)
            height: width
            radius: width / 2
            color: Color.foreground
            border.width: Math.max(1, root.iconSize * 0.04)
            border.color: Color.menu.background
          }
        }
      }
    }
  }

  PanelToolTip {
    visible: mouse.hovered && !contextMenu.visible
    text: "Dock Controls"
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }

  HoverHandler {
    id: mouse
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: contextMenu.open()
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: contextMenu.open()
  }

  DockContextMenu {
    id: contextMenu

    anchorItem: root
    position: root.position
    autoHide: root.autoHide
    pinnedItem: false
    runningToplevels: []
    controlItem: true
    onVisibleChanged: root.contextMenuVisibilityChanged(visible)
    onOpenLauncher: {
      contextMenu.dismiss()
      Qt.callLater(() => root.activate())
    }
    onOpenSettings: root.settingsRequested()
    onAddApplication: root.addApplicationRequested()
    onToggleAutoHide: root.autoHideToggled(!root.autoHide)
  }
}
