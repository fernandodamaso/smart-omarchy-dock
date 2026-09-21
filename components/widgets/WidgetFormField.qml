import QtQuick
import qs.Commons

Column {
  id: root
  WidgetSemanticPalette { id: semanticPalette }
  default property alias content: controlHost.data
  property string label: ""
  property string helperText: ""
  property string errorText: ""
  property bool requiredField: false
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(4)

  WidgetText {
    visible: root.label !== ""
    width: parent.width
    text: root.label + (root.requiredField ? " *" : "")
    role: "label"
    allowWrap: false
  }

  Item {
    id: controlHost
    width: parent.width
    implicitHeight: children.length ? children[0].implicitHeight : 0
    height: implicitHeight
  }

  WidgetText {
    visible: root.errorText !== "" || root.helperText !== ""
    width: parent.width
    text: root.errorText !== "" ? root.errorText : root.helperText
    role: "caption"
    muted: root.errorText === ""
    color: root.errorText !== "" ? semanticPalette.danger : Util.alpha(Color.foreground, 0.62)
    maxLines: 2
  }
}