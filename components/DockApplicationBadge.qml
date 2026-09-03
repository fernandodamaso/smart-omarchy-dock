import QtQuick
import qs.Commons

Rectangle {
  id: root

  // FDM-809 severity strings remain valid. FDM-811 extends the same narrow
  // rendering contract with count:<value>:<severity> tokens so Dock.qml keeps
  // the existing grouped/ungrouped primary-item ownership gate unchanged.
  required property string severity

  readonly property var tokenParts: String(severity || "").split(":")
  readonly property bool numeric: tokenParts.length >= 2
    && tokenParts[0] === "count"
    && isFinite(Number(tokenParts[1]))
    && Number(tokenParts[1]) > 0
  readonly property int count: numeric ? Math.floor(Number(tokenParts[1])) : 0
  readonly property string sourceSeverity: numeric && tokenParts.length >= 3
    ? tokenParts[2] : severity
  readonly property bool urgent: sourceSeverity === "urgent"
  readonly property bool attention: sourceSeverity === "attention"

  visible: numeric || attention || urgent
  width: numeric ? Math.max(18, countText.implicitWidth + 8) : 10
  height: numeric ? 18 : 10
  radius: height / 2
  color: urgent ? Color.urgent : Color.accent
  border.width: Style.normalBorderWidth
  border.color: Color.background
  z: 4

  Text {
    id: countText

    anchors.centerIn: parent
    visible: root.numeric
    text: root.count > 99 ? "99+" : String(root.count)
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
