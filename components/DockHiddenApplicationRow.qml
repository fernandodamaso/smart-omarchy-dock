pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string desktopId
  required property string applicationName
  required property string applicationIcon
  signal showRequested()

  implicitHeight: Style.space(56)

  IconImage {
    id: applicationIconImage

    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(36)
    height: width
    source: Quickshell.iconPath(root.applicationIcon, true)
    asynchronous: true
  }

  Column {
    anchors.left: applicationIconImage.right
    anchors.leftMargin: Style.spacing.md
    anchors.right: showButton.left
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      text: root.applicationName
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: root.applicationName !== root.desktopId
      width: parent.width
      text: root.desktopId
      color: Util.alpha(Color.menu.text, 0.48)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Button {
    id: showButton

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: "Show"
    focusable: true
    bordered: true
    foreground: Color.menu.text
    background: "transparent"
    accent: Color.accent
    onClicked: root.showRequested()
  }
}
