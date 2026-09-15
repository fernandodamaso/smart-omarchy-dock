import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  required property string text
  property string iconName: ""
  property string iconText: ""
  property string iconFont: Style.font.family
  property real iconSize: Style.font.icon
  property bool checked: false
  property bool submenu: false
  property bool isDockMenuAction: true

  signal triggered()
  signal cursorRequested()

  readonly property bool hasIcon: root.iconName !== "" || root.iconText !== ""

  foreground: Color.menu.text
  accent: Color.accent
  current: root.checked

  implicitWidth: Style.space(168)
  implicitHeight: Style.spacing.popupRowHeight
  opacity: enabled ? 1.0 : 0.42

  Item {
    id: iconSlot

    visible: root.hasIcon
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(24)
    height: root.iconSize

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
      color: root.foreground
      opacity: 1.0
    }

    Text {
      visible: root.iconName === "" && root.iconText !== ""
      anchors.fill: parent
      text: root.iconText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.iconFont
      font.pixelSize: root.iconSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  Text {
    id: actionLabel
    anchors.left: root.hasIcon ? iconSlot.right : parent.left
    anchors.right: trailing.left
    anchors.leftMargin: root.hasIcon
      ? Style.spacing.controlGap : Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlGap
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Text {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? implicitWidth : 0
    visible: root.checked || root.submenu
    text: root.submenu ? "›" : "✓"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  HoverHandler {
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: {
      if (hovered)
        root.cursorRequested()
    }
  }

  TapHandler {
    enabled: root.enabled
    acceptedButtons: Qt.LeftButton
    onTapped: root.triggered()
  }
}
