pragma Singleton
import QtQuick

QtObject {
  property color foreground: "#f0f2f8"
  property color background: "#171a22"
  property color accent: "#7d8cff"
  property color urgent: "#e06c75"
  property color muted: "#7f8490"
  readonly property QtObject menu: QtObject {
    readonly property color text: "#f0f2f8"
    readonly property color background: "#20242e"
    readonly property color border: "#3a4150"
  }

  function flatColor(value, fallback) {
    var text = String(value || "").trim()
    return text.charAt(0) === "#" ? Qt.color(text) : fallback
  }
}
