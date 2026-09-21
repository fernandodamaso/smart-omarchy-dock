import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Controls.AbstractButton {
  id: root
  WidgetSemanticPalette { id: semanticPalette }
  property string variant: "secondary"
  property string iconName: ""
  property url iconSource: ""
  property bool preserveBrandIcon: false
  property string accessibleName: text
  readonly property string visualState: !enabled ? "disabled"
    : down ? "pressed" : activeFocus ? "focus" : hovered ? "hover" : "idle"

  hoverEnabled: true
  activeFocusOnTab: true
  implicitHeight: 32
  implicitWidth: Math.max(52, content.implicitWidth + Style.space(18))
  leftPadding: Style.space(9)
  rightPadding: Style.space(9)

  readonly property color baseTone: root.variant === "primary" ? Color.accent
    : root.variant === "danger" ? semanticPalette.danger
    : root.variant === "ghost" ? "transparent"
    : Qt.tint(Color.background, Util.alpha(Color.foreground, 0.08))
  readonly property color stateTone: !root.enabled ? root.baseTone
    : root.down ? (root.variant === "primary" || root.variant === "danger"
      ? Qt.darker(root.baseTone, 1.28) : Util.alpha(Color.foreground, 0.12))
    : root.hovered ? (root.variant === "primary" || root.variant === "danger"
      ? Qt.darker(root.baseTone, 1.14) : Util.alpha(Color.foreground, 0.09))
    : root.baseTone

  background: Rectangle {
    radius: Math.min(6, Style.cornerRadius)
    color: root.stateTone
    opacity: root.enabled ? 1 : 0.44
    border.width: root.activeFocus || root.variant === "secondary" ? 1 : 0
    border.color: root.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.14)
  }

  contentItem: Row {
    id: content
    spacing: Style.space(5)

    WidgetIcon {
      visible: root.iconName !== "" || String(root.iconSource).length > 0
      anchors.verticalCenter: parent.verticalCenter
      iconName: root.iconName
      source: root.iconSource
      preserveBrand: root.preserveBrandIcon
      sizeToken: "sm"
      containerVariant: "plain"
      tint: root.variant === "primary" || root.variant === "danger"
        ? Color.background : Color.foreground
    }

    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      textFormat: Text.PlainText
      color: root.variant === "primary" || root.variant === "danger"
        ? Color.background : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.variant === "primary"
      elide: Text.ElideRight
    }
  }

  Accessible.role: Accessible.Button
  Accessible.name: root.accessibleName
}