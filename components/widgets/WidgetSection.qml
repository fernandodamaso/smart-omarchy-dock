import QtQuick
import qs.Commons

Column {
  id: root
  default property alias content: body.data
  property string title: ""
  property string subtitle: ""
  spacing: Style.space(6)
  width: parent ? parent.width : implicitWidth

  WidgetText {
    visible: root.title !== ""
    width: parent.width
    text: root.title
    role: "label"
    allowWrap: false
  }

  WidgetText {
    visible: root.subtitle !== ""
    width: parent.width
    text: root.subtitle
    role: "caption"
    muted: true
    maxLines: 2
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)
  }
}