import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons

Item {
  id: root

  required property string iconName
  property color tint: Color.menu.text
  property real iconSize: Style.font.icon

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: sourceImage
    anchors.fill: parent
    source: Qt.resolvedUrl("../assets/lucide/" + root.iconName + ".svg")
    sourceSize: Qt.size(width * 2, height * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    visible: false
    layer.enabled: true
  }

  ColorOverlay {
    anchors.fill: sourceImage
    source: sourceImage
    color: root.tint
  }
}
