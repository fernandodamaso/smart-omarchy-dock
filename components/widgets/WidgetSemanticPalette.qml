import QtQuick
import qs.Commons

// Central semantic palette for Widget primitives. Hue conveys meaning while
// luminance adapts to the active Omarchy background so semantic surfaces remain
// legible across light and dark themes without fixture-specific body colors.
QtObject {
  id: root

  readonly property real backgroundLuminance:
    0.2126 * Color.background.r + 0.7152 * Color.background.g + 0.0722 * Color.background.b
  readonly property bool darkBackground: root.backgroundLuminance < 0.5

  readonly property color danger: Qt.hsla(0.985, 0.78, root.darkBackground ? 0.68 : 0.46, 1)
  readonly property color warning: Qt.hsla(0.115, 0.82, root.darkBackground ? 0.66 : 0.42, 1)
  readonly property color success: Qt.hsla(0.43, 0.62, root.darkBackground ? 0.62 : 0.36, 1)
  readonly property color info: Color.accent
  readonly property color neutral: Color.foreground

  function tone(semantic) {
    return semantic === "danger" ? root.danger
      : semantic === "warning" ? root.warning
      : semantic === "success" ? root.success
      : semantic === "info" ? root.info : root.neutral
  }

  function surface(semantic, alpha) {
    return Qt.tint(Color.background, Util.alpha(root.tone(semantic), alpha))
  }
}
