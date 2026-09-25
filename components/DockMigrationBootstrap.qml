import QtQuick
import Quickshell
import Quickshell.Io

// One bounded startup coordinator. Production hosts consume only its validated
// result; they do not implement their own SmartDock/Dockrail fallback chains.
Item {
  id: root

  required property string runtimeMode
  property bool ready: false
  property bool failed: false
  property string errorText: ""
  property string configPath: ""
  property string dataRoot: ""
  property string clientRoot: ""
  property string cacheRoot: ""
  property string selectionProvenance: ""
  property string migrationId: ""
  property bool migrated: false
  property bool replySeen: false
  property string stderrText: ""

  readonly property string helperPath: localPath(
    Qt.resolvedUrl("../scripts/dockrail_migrate.py"))

  visible: false
  width: 0
  height: 0

  function localPath(url) {
    var value = String(url || "")
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : value
  }

  function fail(message) {
    if (root.ready || root.failed) return
    root.failed = true
    root.errorText = String(message || "Dockrail migration bootstrap failed.").slice(0, 4096)
    timeout.stop()
    if (migrationProcess.running) migrationProcess.running = false
    console.warn("Dockrail: " + root.errorText)
  }

  function acceptLine(line) {
    if (root.replySeen || root.ready || root.failed) return
    if (typeof line !== "string" || line.length > 1024 * 1024) {
      root.fail("Migration helper returned an invalid response.")
      return
    }
    var reply
    try {
      reply = JSON.parse(line)
    } catch (error) {
      root.fail("Migration helper returned invalid JSON.")
      return
    }
    root.replySeen = true
    if (!reply || reply.apiVersion !== 1 || reply.ok !== true || !reply.data
        || reply.data.ready !== true || typeof reply.data.configPath !== "string"
        || typeof reply.data.dataRoot !== "string" || typeof reply.data.clientRoot !== "string"
        || typeof reply.data.cacheRoot !== "string" || typeof reply.data.migrationId !== "string") {
      var message = reply && reply.error && typeof reply.error.message === "string"
        ? reply.error.message : "Migration helper did not establish a ready state."
      root.fail(message)
      return
    }
    root.configPath = reply.data.configPath
    root.dataRoot = reply.data.dataRoot
    root.clientRoot = reply.data.clientRoot
    root.cacheRoot = reply.data.cacheRoot
    root.selectionProvenance = String(reply.data.selectionProvenance || "")
    root.migrationId = reply.data.migrationId
    root.migrated = reply.data.migrated === true
    root.ready = true
    timeout.stop()
  }

  function start() {
    if (root.ready || root.failed || migrationProcess.running) return
    if (!root.helperPath) {
      root.fail("Bundled migration helper path is unavailable.")
      return
    }
    root.replySeen = false
    root.stderrText = ""
    migrationProcess.command = [
      "python3", "-B", root.helperPath, "startup", "--runtime", root.runtimeMode
    ]
    migrationProcess.running = true
    timeout.restart()
  }

  Process {
    id: migrationProcess
    running: false
    stdout: SplitParser {
      onRead: data => root.acceptLine(data)
    }
    stderr: SplitParser {
      onRead: data => {
        if (root.stderrText.length < 4096)
          root.stderrText = (root.stderrText + String(data || "")).slice(0, 4096)
      }
    }
    onExited: function(exitCode) {
      timeout.stop()
      if (root.ready || root.failed) return
      root.fail(root.stderrText || ("Migration helper exited with status " + exitCode + "."))
    }
  }

  Timer {
    id: timeout
    interval: 10000
    repeat: false
    onTriggered: root.fail("Migration helper timed out; Dockrail host activation was blocked.")
  }

  Component.onCompleted: Qt.callLater(root.start)
}
