import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  required property string text
  property string iconName: ""
  property string iconText: ""
  property string iconFontFamily: Style.font.family
  property int iconSize: Style.font.body
  property bool checked: false
  property bool submenu: false
  property bool isDockMenuAction: true

  signal triggered()
  signal cursorRequested()

  foreground: Color.menu.text
  accent: Color.accent
  current: root.checked

  implicitWidth: Style.space(168)
  implicitHeight: Style.spacing.popupRowHeight
  opacity: enabled ? 1.0 : 0.42

  Item {
    id: iconSlot
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    width: Style.font.title
    height: width

    Image {
      id: iconImage
      anchors.fill: parent
      source: root.iconName !== ""
        ? Quickshell.iconPath("lucide-" + root.iconName, true) : ""
      sourceSize.width: root.iconSize
      sourceSize.height: root.iconSize
      visible: root.iconName !== "" && status === Image.Ready
      fillMode: Image.PreserveAspectFit
    }

    ColorOverlay {
      anchors.fill: iconImage
      source: iconImage
      color: root.foreground
      visible: iconImage.visible
    }

    Text {
      anchors.centerIn: parent
      visible: !iconImage.visible && root.iconText !== ""
      text: root.iconText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.iconFontFamily
      font.pixelSize: root.iconSize
    }
  }

  Text {
    id: actionLabel
    anchors.left: iconSlot.right
    anchors.right: trailing.left
    anchors.leftMargin: Style.spacing.controlGap
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
