pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string label
  required property string connector
  required property bool focused
  required property string position
  required property int slotSize

  readonly property string displayText: {
    var value = String(root.label || "").trim()
    if (value) return value
    var fallback = String(root.connector || "").trim()
    return fallback || "Monitor"
  }
  readonly property string accessibilityText: {
    var connectorText = String(root.connector || "").trim()
    if (!connectorText || connectorText === root.displayText) return root.displayText
    return root.displayText + " — " + connectorText
  }
  readonly property real contentWidth: monitorGlyph.width
    + Style.spacing.controlGap + monitorText.implicitWidth
  readonly property real maximumWidth: 156

  implicitWidth: Math.min(maximumWidth, Math.max(54, contentWidth))
  width: implicitWidth
  height: root.slotSize + 10

  Accessible.role: Accessible.StaticText
  Accessible.name: root.accessibilityText

  OpticalGlyph {
    id: monitorGlyph

    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.ceil(Style.font.bodySmall * 1.35)
    height: width
    text: "󰍺"
    fontSize: Style.font.bodySmall
    color: root.focused ? Color.foreground : Color.muted
  }

  Text {
    id: monitorText

    anchors.left: monitorGlyph.right
    anchors.leftMargin: Style.spacing.controlGap
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.displayText
    elide: Text.ElideRight
    maximumLineCount: 1
    wrapMode: Text.NoWrap
    color: root.focused
      ? Util.alpha(Color.foreground, 0.9)
      : Util.alpha(Color.muted, 0.88)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  HoverHandler {
    id: labelHover
  }

  DockToolTip {
    anchorItem: root
    position: root.position
    requestedVisible: labelHover.hovered
    text: root.accessibilityText
    fontFamily: Style.font.family
    fontSize: Style.font.bodySmall
  }
}
