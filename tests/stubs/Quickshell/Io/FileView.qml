import QtQuick

QtObject {
  id: root

  property url path
  property bool watchChanges: false
  property bool printErrors: false
  property bool blockLoading: false

  signal loaded()
  signal loadFailed(var error)
  signal fileChanged()

  function text() {
    return ""
  }

  function reload() {
    // Absent files fail closed so Omarchy Color/Style keep built-in defaults.
    loadFailed("stub-missing")
  }

  Component.onCompleted: Qt.callLater(function() { root.reload() })
}
