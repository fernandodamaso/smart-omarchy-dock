import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.TextField {
  id: root
  WidgetSemanticPalette { id: semanticPalette }
  property string validationState: "none"
  property string accessibleName: placeholderText

  implicitHeight: Math.max(34, Style.space(34))
  leftPadding: Style.space(9)
  rightPadding: Style.space(9)
  activeFocusOnTab: true
  selectByMouse: true
  echoMode: TextInput.Normal
  color: Color.foreground
  placeholderTextColor: semanticPalette.mutedText
  selectionColor: Color.accent
  selectedTextColor: Color.background
  font.family: Style.font.family
  font.pixelSize: Style.font.bodySmall

  background: Rectangle {
    radius: Math.min(3, Style.cornerRadius)
    color: Qt.darker(Color.background, 1.03)
    border.width: 1
    border.color: root.validationState === "error" ? semanticPalette.danger
      : root.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.16)
  }

  Accessible.role: Accessible.EditableText
  Accessible.name: root.accessibleName
}