import QtQuick
import qs.Commons

Column {
  id: root
  default property alias content: body.data
  property int itemSpacing: 0
  width: parent ? parent.width : implicitWidth

  Column {
    id: body
    width: parent.width
    spacing: root.itemSpacing
  }
}