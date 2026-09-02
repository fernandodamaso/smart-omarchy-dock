pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Provider-neutral service contract consumed by DockBadgeTracker.
  readonly property bool providerAvailable: available
  property bool available: false
  property int revision: 0
  property var counts: ({})
  property bool providerExecutable: false
  property bool shuttingDown: false
  property int restartAttempts: 0

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") !== ""
    ? Quickshell.env("XDG_DATA_HOME")
    : Quickshell.env("HOME") + "/.local/share"
  readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR") !== ""
    ? Quickshell.env("XDG_RUNTIME_DIR")
    : Quickshell.env("XDG_CACHE_HOME") !== ""
      ? Quickshell.env("XDG_CACHE_HOME")
      : Quickshell.env("HOME") + "/.cache"
  readonly property string providerBinaryPath:
    dataHome + "/smartdock/providers/smartdock-launcher-badge-provider"
  readonly property string statePath:
    runtimeHome + "/smartdock/launcher-badges.json"

  visible: false
  width: 0
  height: 0

  function clearSnapshot() {
    if (!available && Object.keys(counts || ({})).length === 0) return
    available = false
    counts = ({})
    revision++
  }

  function applySnapshot(raw) {
    // Never accept a previous process's state file during service startup or
    // after a provider exit. A running provider must publish a fresh snapshot.
    if (!providerProcess.running) {
      clearSnapshot()
      return
    }

    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (_) {
      clearSnapshot()
      return
    }
    if (!parsed || parsed.schemaVersion !== 1
        || parsed.available !== true
        || !parsed.counts || typeof parsed.counts !== "object"
        || Array.isArray(parsed.counts)) {
      clearSnapshot()
      return
    }

    counts = parsed.counts
    available = true
    restartAttempts = 0
    var providerRevision = Number(parsed.revision)
    revision = isFinite(providerRevision) && providerRevision >= 0
      ? Math.max(revision + 1, Math.floor(providerRevision))
      : revision + 1
  }

  function startProvider() {
    if (shuttingDown || !providerExecutable || providerProcess.running) return
    providerProcess.running = true
    // FileView may have been created before the first state file existed.
    // Reload once after process start so the fresh initial snapshot also
    // establishes the file watch; subsequent updates remain event-driven.
    snapshotLoadTimer.restart()
  }

  function scheduleRestart() {
    if (shuttingDown || !providerExecutable || restartAttempts >= 3) return
    restartAttempts++
    restartTimer.interval = restartAttempts === 1
      ? 2000 : restartAttempts === 2 ? 5000 : 15000
    restartTimer.restart()
  }

  Component.onCompleted: executableProbe.running = true
  Component.onDestruction: {
    shuttingDown = true
    restartTimer.stop()
    snapshotLoadTimer.stop()
    providerProcess.running = false
  }

  Process {
    id: executableProbe

    command: ["test", "-x", root.providerBinaryPath]
    onExited: function(exitCode) {
      root.providerExecutable = exitCode === 0
      if (root.providerExecutable)
        root.startProvider()
      else
        root.clearSnapshot()
    }
  }

  Process {
    id: providerProcess

    command: [root.providerBinaryPath, "--state-file", root.statePath]
    onExited: function(exitCode) {
      snapshotLoadTimer.stop()
      root.clearSnapshot()
      if (!root.shuttingDown && root.providerExecutable && exitCode !== 0)
        console.warn("Dock: launcher badge provider exited " + exitCode)
      root.scheduleRestart()
    }
  }

  Timer {
    id: snapshotLoadTimer

    interval: 250
    repeat: false
    onTriggered: if (providerProcess.running) providerState.reload()
  }

  Timer {
    id: restartTimer

    interval: 2000
    repeat: false
    onTriggered: root.startProvider()
  }

  FileView {
    id: providerState

    path: root.statePath
    watchChanges: true
    printErrors: false
    blockWrites: true
    onLoaded: root.applySnapshot(text())
    onFileChanged: reload()
  }
}
