import QtQuick

QtObject {
  id: root

  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null

  signal started()
  signal exited(int exitCode)
  signal finished(int exitCode)

  function start() {
    running = true
    started()
    running = false
    exited(0)
    finished(0)
  }

  function startDetached() {}
}
