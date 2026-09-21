import QtQuick
import qs.Commons

Item {
  id: root
  default property alias content: body.data
  property int gap: Style.space(5)
  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight
  width: parent ? parent.width : implicitWidth

  Flow {
    id: body
    width: root.width
    spacing: root.gap
  }
}