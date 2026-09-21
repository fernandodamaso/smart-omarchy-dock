import QtQuick
import qs.Commons

Item {
  id: root
  property string label: ""
  property string value: ""
  property bool emphasized: false
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight) + Style.space(4)

  WidgetText {
    id: labelText
    anchors.left: parent.left
    anchors.right: valueText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    role: "caption"
    muted: true
    allowWrap: false
  }

  WidgetText {
    id: valueText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.value
    role: root.emphasized ? "label" : "body"
    allowWrap: false
  }
}