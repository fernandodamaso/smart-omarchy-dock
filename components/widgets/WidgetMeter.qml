import QtQuick
import qs.Commons

Column {
  id: root
  property string label: ""
  property string valueText: ""
  property real value: 0
  property string semantic: "info"
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(4)

  Row {
    width: parent.width
    WidgetText { width: Math.max(0, parent.width - meterValue.implicitWidth); text: root.label; role: "caption"; muted: true; allowWrap: false }
    WidgetText { id: meterValue; text: root.valueText; role: "caption"; allowWrap: false }
  }

  WidgetProgressBar { width: parent.width; height: 3; value: root.value; semantic: root.semantic }
}