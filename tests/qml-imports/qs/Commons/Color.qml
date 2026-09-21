pragma Singleton
import QtQuick

QtObject {
  readonly property color foreground: "#f0f2f8"
  readonly property color background: "#171a22"
  readonly property color accent: "#7d8cff"
  readonly property QtObject menu: QtObject {
    readonly property color text: "#f0f2f8"
    readonly property color background: "#20242e"
    readonly property color border: "#3a4150"
  }
}
