import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string label
  property string description: ""
  property bool checked: false
  property color foreground: Color.menu.text
  signal toggled()

  activeFocusOnTab: enabled
  implicitHeight: description === "" ? Style.spacing.controlHeight
    : Math.max(Style.spacing.controlHeight, labels.implicitHeight)

  Keys.onReturnPressed: root.toggled()
  Keys.onEnterPressed: root.toggled()
  Keys.onSpacePressed: root.toggled()

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: toggle.left
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: root.description !== ""
      width: parent.width
      text: root.description
      color: Util.alpha(root.foreground, 0.56)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    foreground: root.foreground
    accent: Color.accent
    interactive: false
  }

  TapHandler {
    enabled: root.enabled
    onTapped: root.toggled()
  }
}
