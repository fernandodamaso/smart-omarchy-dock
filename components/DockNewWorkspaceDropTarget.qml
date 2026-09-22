pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

Item {
  id: root

  required property string monitorIdentity
  required property int slotSize
  property bool highlighted: false
  property bool animationsEnabled: true

  objectName: "dock-new-workspace-target"
  implicitWidth: Math.max(root.slotSize + 18,
    plusIcon.width + targetLabel.implicitWidth + Style.space(24))
  width: visible ? implicitWidth : 0
  height: root.slotSize + 10
  enabled: false
  Accessible.role: Accessible.Button
  Accessible.name: "Move to new workspace"

  Rectangle {
    anchors.fill: parent
    radius: Math.max(12, Style.cornerRadius - 4)
    color: root.highlighted
      ? Util.alpha(Color.accent, 0.20)
      : Util.alpha(Color.foreground, 0.06)
    border.width: 1
    border.color: root.highlighted
      ? Color.accent
      : Util.alpha(Color.foreground, 0.18)

    Behavior on color {
      enabled: root.animationsEnabled
      ColorAnimation { duration: 120 }
    }
    Behavior on border.color {
      enabled: root.animationsEnabled
      ColorAnimation { duration: 120 }
    }
  }

  DockLucideIcon {
    id: plusIcon
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: 14
    height: 14
    iconName: "plus"
    iconSize: 14
    tint: root.highlighted ? Color.accent : Color.foreground
  }

  Text {
    id: targetLabel
    anchors.left: plusIcon.right
    anchors.leftMargin: Style.space(7)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: "New workspace"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.highlighted ? Color.accent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }
}
