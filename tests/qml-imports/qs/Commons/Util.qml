pragma Singleton
import QtQuick

QtObject {
  function alpha(value, opacity) {
    var c = Qt.color(value)
    return Qt.rgba(c.r, c.g, c.b, opacity)
  }
}
