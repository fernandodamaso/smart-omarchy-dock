import QtQuick
import qs.Commons

Row {
  id: root
  property string iconName: ""
  property url iconSource: ""
  property string text: ""
  property bool muted: false
  property bool preserveBrand: false
  spacing: Style.space(6)

  WidgetIcon {
    anchors.verticalCenter: parent.verticalCenter
    iconName: root.iconName
    source: root.iconSource
    preserveBrand: root.preserveBrand
    sizeToken: "sm"
    containerVariant: "plain"
  }

  WidgetText {
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    muted: root.muted
    allowWrap: false
  }
}