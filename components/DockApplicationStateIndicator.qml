import QtQuick
import "DockModel.js" as DockModel

Item {
  id: root

  required property string position
  required property real iconWidth
  required property real iconHeight
  required property bool running
  required property bool focused
  required property color runningColor
  required property color focusedColor

  readonly property var indicatorGeometry:
    DockModel.applicationStateIndicatorGeometry(
      position, iconWidth, iconHeight, running, focused)
  readonly property color markerColor: focused ? focusedColor : runningColor

  visible: indicatorGeometry.visible
  x: indicatorGeometry.x
  y: indicatorGeometry.y
  width: indicatorGeometry.width
  height: indicatorGeometry.height
  z: 2

  Rectangle {
    anchors.fill: parent
    radius: root.indicatorGeometry.radius
    color: root.markerColor
    opacity: root.focused ? 1.0 : 0.72
  }
}
