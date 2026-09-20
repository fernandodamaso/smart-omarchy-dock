import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.TextArea {
  id: root
  property string validationState: "none"
  property string accessibleName: placeholderText

  implicitHeight: 82
  leftPadding: Style.space(9)
  rightPadding: Style.space(9)
  topPadding: Style.space(8)
  bottomPadding: Style.space(8)
  activeFocusOnTab: true
  selectByMouse: true
  wrapMode: TextEdit.Wrap
  color: Color.foreground
  placeholderTextColor: Util.alpha(Color.foreground, 0.46)
  selectionColor: Color.accent
  selectedTextColor: Color.background
  font.family: Style.font.family
  font.pixelSize: Style.font.bodySmall

  background: Rectangle {
    radius: Math.min(6, Style.cornerRadius)
    color: Qt.darker(Color.background, 1.03)
    border.width: 1
    border.color: root.validationState === "error" ? "#ff6b7a"
      : root.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.16)
  }

  Accessible.role: Accessible.EditableText
  Accessible.name: root.accessibleName
}