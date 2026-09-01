pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string title
  required property string iconName
  property string description: ""
  property alias headerAccessory: headerAccessorySlot.data
  default property alias contentData: body.data

  implicitWidth: Style.space(360)
  implicitHeight: sectionColumn.implicitHeight + Style.spacing.huge * 2
  radius: Style.cornerRadius
  color: Util.alpha(Color.accent, 0.035)
  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

  Column {
    id: sectionColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.huge
    spacing: Style.spacing.md

    Item {
      width: parent.width
      height: Math.max(iconBadge.height, titleBlock.implicitHeight,
        headerAccessorySlot.implicitHeight)

      BorderSurface {
        id: iconBadge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: width
        radius: Style.cornerRadius
        color: Util.alpha(Color.accent, 0.12)
        borderSpec: Border.controlSpec("selected", Color.menu.text, Color.accent)

        DockLucideIcon {
          anchors.centerIn: parent
          iconName: root.iconName
          iconSize: Style.space(18)
          tint: Color.accent
        }
      }

      Column {
        id: titleBlock
        anchors.left: iconBadge.right
        anchors.right: headerAccessorySlot.left
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          text: root.title
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: root.description !== ""
          width: parent.width
          text: root.description
          color: Util.alpha(Color.menu.text, 0.56)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: headerAccessorySlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.sm
    }
  }
}
