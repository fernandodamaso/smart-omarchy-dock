pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string label
  required property string value
  required property var options
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color popupBorder: Color.menu.border
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight

  signal changed(string value)

  implicitHeight: actionLabel.implicitHeight + Style.spacing.xs + rowHeight

  Text {
    id: actionLabel

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Dropdown {
    id: nativeDropdown

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: actionLabel.bottom
    anchors.topMargin: Style.spacing.xs
    height: root.rowHeight
    value: root.value
    options: root.options
    foreground: root.foreground
    background: root.background
    popupBorder: root.popupBorder
    accent: root.accent
    fontFamily: root.fontFamily
    rowHeight: root.rowHeight
    popupRowHeight: root.popupRowHeight
    showLabel: false

    onChanged: function(selectedValue) {
      root.changed(selectedValue)
      // Native Dropdown assigns its own value before emitting changed(), which
      // removes the declarative binding. Restore it so settings remain the
      // source of truth for later reloads and Reset without write-back loops.
      nativeDropdown.value = Qt.binding(function() { return root.value })
    }
  }
}
