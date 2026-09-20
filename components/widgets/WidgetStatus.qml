import QtQuick
import qs.Commons

Row {
  id: root
  property string label: ""
  property string semantic: "neutral"
  property string reference: ""
  property bool compact: true
  spacing: Style.space(6)

  readonly property color tone: root.semantic === "danger" ? "#ff6b7a"
    : root.semantic === "warning" ? "#f5bd36"
    : root.semantic === "success" ? "#48d5a4"
    : root.semantic === "info" ? Color.accent : Util.alpha(Color.foreground, 0.72)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: 7
    height: 7
    radius: 4
    color: root.tone
  }

  WidgetText {
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    role: "caption"
    allowWrap: false
    muted: root.semantic === "neutral"
  }

  WidgetBadge {
    visible: root.reference !== ""
    anchors.verticalCenter: parent.verticalCenter
    text: root.reference
    semantic: root.semantic
    compact: root.compact
  }
}