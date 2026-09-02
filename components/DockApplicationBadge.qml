import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string severity

  visible: severity === "attention" || severity === "urgent"
  width: 10
  height: 10
  radius: width / 2
  color: severity === "urgent" ? Color.urgent : Color.accent
  border.width: Style.normalBorderWidth
  border.color: Color.background
  z: 4
}
