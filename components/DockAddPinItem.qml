pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: root

  required property int slotSize
  required property int iconSize
  required property real magnification
  required property real magnificationRadius
  required property bool hoverGlowEnabled
  required property real hoverGlowOpacity
  required property real hoverGlowRadius
  required property real pointerPosition
  required property string position
  required property bool vertical
  required property bool interfaceAnimationsEnabled
  signal activated()

  objectName: "dock-add-pin"
  Accessible.role: Accessible.Button
  Accessible.name: "Add pinned application"
  activeFocusOnTab: true

  readonly property real itemCenter: vertical ? y + height / 2 : x + width / 2
  readonly property real distance: Math.abs(pointerPosition - itemCenter)
  readonly property real influence: pointerPosition < -1000
    ? 0
    : Math.exp(-(distance * distance) / (magnificationRadius * magnificationRadius))
  readonly property real iconScale: 1 + (magnification - 1) * influence

  width: vertical ? slotSize + 6 : slotSize
  height: vertical ? slotSize : slotSize + 6

  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

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
      enabled: root.interfaceAnimationsEnabled
      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    RectangularShadow {
      anchors.fill: parent
      radius: Math.min(width, height) * 0.34
      blur: Math.max(8, root.iconSize * root.hoverGlowRadius / 100)
      spread: Math.max(1, root.iconSize * 0.06)
      offset: Qt.vector2d(0, 0)
      color: Color.accent
      opacity: root.hoverGlowEnabled && addHover.hovered
        ? root.hoverGlowOpacity : 0
      z: -1

      Behavior on opacity {
        enabled: root.interfaceAnimationsEnabled
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: Math.max(10, Style.cornerRadius)
      color: addTap.pressed
        ? Util.alpha(Color.accent, 0.20)
        : addHover.hovered || root.activeFocus
          ? Util.alpha(Color.foreground, 0.10) : "transparent"
      border.width: 1
      border.color: addHover.hovered || root.activeFocus
        ? Util.alpha(Color.accent, 0.72)
        : Util.alpha(Color.foreground, 0.22)

      Behavior on color {
        enabled: root.interfaceAnimationsEnabled
        ColorAnimation { duration: 120 }
      }
      Behavior on border.color {
        enabled: root.interfaceAnimationsEnabled
        ColorAnimation { duration: 120 }
      }
    }

    DockLucideIcon {
      anchors.centerIn: parent
      width: Math.max(14, root.iconSize * 0.42)
      height: width
      iconName: "plus"
      iconSize: Math.round(width)
      tint: addHover.hovered || root.activeFocus ? Color.accent : Color.foreground
    }
  }

  HoverHandler {
    id: addHover
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    id: addTap
    acceptedButtons: Qt.LeftButton
    onTapped: {
      root.forceActiveFocus(Qt.MouseFocusReason)
      root.activated()
    }
  }

  DockToolTip {
    anchorItem: root
    position: root.position
    requestedVisible: addHover.hovered
    text: "Add a pinned application"
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }
}
