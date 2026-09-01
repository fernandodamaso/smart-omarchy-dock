import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string text
  property string iconName: ""
  property string iconText: ""
  property string iconFont: Style.font.family
  property real iconSize: Style.font.icon
  property bool keyboardActive: false
  property bool isDockMenuAction: true
  property bool autoTriggerOnHover: false
  signal triggered()

  readonly property bool hasIcon: root.iconName !== "" || root.iconText !== ""
  readonly property bool highlighted: hover.hovered || root.keyboardActive

  implicitWidth: Style.space(168)
  implicitHeight: Style.spacing.popupRowHeight
  radius: Style.cornerRadius
  color: root.highlighted && enabled
    ? Style.hoverFillFor(Color.menu.text, Color.accent)
    : "transparent"
  borderSpec: root.highlighted && enabled
    ? Border.controlSpec("hover-cursor", Color.menu.text, Color.accent)
    : Border.none()
  opacity: enabled ? 1 : 0.42

  Item {
    id: actionIcon

    visible: root.hasIcon
    width: Style.space(24)
    height: root.iconSize
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter

    Image {
      id: lucideSource

      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      source: root.iconName === ""
        ? ""
        : Qt.resolvedUrl("../assets/lucide/" + root.iconName + ".svg")
      sourceSize: Qt.size(width * 2, height * 2)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      visible: false
      layer.enabled: true
    }

    ColorOverlay {
      visible: root.iconName !== ""
      anchors.fill: lucideSource
      source: lucideSource
      color: root.highlighted && root.enabled ? Color.accent : Color.menu.text
      opacity: 1.0

      Behavior on color { ColorAnimation { duration: 100 } }
    }

    Text {
      visible: root.iconName === "" && root.iconText !== ""
      anchors.fill: parent
      text: root.iconText
      color: root.highlighted && root.enabled ? Color.accent : Color.menu.text
      font.family: root.iconFont
      font.pixelSize: root.iconSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  Text {
    anchors {
      verticalCenter: parent.verticalCenter
      left: root.hasIcon ? actionIcon.right : parent.left
      leftMargin: root.hasIcon ? Style.spacing.controlGap : Style.spacing.controlPaddingX
      right: parent.right
      rightMargin: Style.spacing.controlPaddingX
    }
    text: root.text
    color: root.highlighted && root.enabled ? Color.accent : Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  HoverHandler {
    id: hover
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor

    onHoveredChanged: {
      if (hovered && root.autoTriggerOnHover && root.enabled)
        root.triggered()
    }
  }

  TapHandler {
    enabled: root.enabled
    acceptedButtons: Qt.LeftButton
    onTapped: root.triggered()
  }
}
