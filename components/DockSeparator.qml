import QtQuick
import qs.Commons

Item {
  id: root

  required property bool vertical
  required property int slotSize
  required property int iconSize

  width: vertical ? slotSize + 6 : 12
  height: vertical ? 12 : slotSize + 6

  Rectangle {
    anchors.centerIn: parent
    width: root.vertical ? Math.max(18, root.iconSize * 0.62) : 1
    height: root.vertical ? 1 : Math.max(18, root.iconSize * 0.62)
    color: Util.alpha(Color.menu.border, 0.52)
  }
}
