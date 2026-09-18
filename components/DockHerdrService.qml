import QtQuick
import Quickshell
import Quickshell.Io

// One demand-driven Herdr owner for every SmartDock consumer. Merely loading
// this component starts no process. Active leases share one provider process.
Item {
  id: root

  readonly property int ownerCount: leases.length
  property var leases: []
  property int activeCount: 0
  property var latestSnapshot: null
  property string sourceEpoch: ""
  property int sourceRevision: -1
  property int restartDelay: 1000
  property bool stoppingForIdle: false
  readonly property bool running: providerProcess.running
  readonly property bool available: providerPath.length > 0
  readonly property string providerPath: localPath(
    Qt.resolvedUrl("../provider/herdr/bin/smartdock-herdr-provider"))

  function localPath(url) {
    var value = String(url || "")
    return value.indexOf("file://") === 0 ? decodeURIComponent(value.slice(7)) : value
  }

  function publishLease(lease, status, data) {
    if (!lease || lease.released || !lease.active || typeof lease.publish !== "function") return
    lease.revision++
    lease.publish({
      status: status,
      revision: lease.revision,
      data: status === "ready" ? data : null
    })
  }

  function broadcast(status, data) {
    root.leases.slice().forEach(function(lease) {
      root.publishLease(lease, status, data)
    })
  }

  function acquire(owner) {
    var lease = {
      owner: owner || null,
      provider: root,
      active: false,
      released: false,
      publish: null,
      revision: 0,
      setActive: function(active, publish) {
        if (lease.released) return
        active = active === true
        if (active) {
          lease.publish = typeof publish === "function" ? publish : null
          lease.revision = 0
          if (!lease.active) {
            lease.active = true
            root.activeCount++
          }
          root.publishLease(lease, "loading", null)
          if (root.activeCount === 1) root.startProvider()
          else if (root.latestSnapshot) root.publishLease(lease, "ready", root.latestSnapshot)
        } else {
          lease.publish = null
          if (lease.active) {
            lease.active = false
            root.activeCount = Math.max(0, root.activeCount - 1)
            if (root.activeCount === 0) root.stopProvider()
          }
        }
      },
      release: function() {
        if (lease.released) return
        if (lease.active) {
          lease.active = false
          root.activeCount = Math.max(0, root.activeCount - 1)
        }
        lease.publish = null
        lease.released = true
        root.leases = root.leases.filter(function(candidate) {
          return candidate !== lease
        })
        if (root.activeCount === 0) root.stopProvider()
      }
    }
    root.leases = root.leases.concat([lease])
    return lease
  }

  function startProvider() {
    if (root.activeCount <= 0 || providerProcess.running) return
    restartTimer.stop()
    root.stoppingForIdle = false
    root.latestSnapshot = null
    root.sourceEpoch = ""
    root.sourceRevision = -1
    root.broadcast("loading", null)
    providerProcess.command = ["python3", "-B", root.providerPath]
    providerProcess.running = true
    startupTimer.restart()
  }

  function stopProvider() {
    restartTimer.stop()
    startupTimer.stop()
    root.stoppingForIdle = true
    root.latestSnapshot = null
    root.sourceEpoch = ""
    root.sourceRevision = -1
    root.restartDelay = 1000
    if (providerProcess.running) {
      providerProcess.write("quit\n")
      providerProcess.running = false
    }
  }

  function refresh() {
    if (root.activeCount > 0 && providerProcess.running)
      providerProcess.write("refresh\n")
  }

  function acceptLine(line) {
    if (root.activeCount <= 0 || !line || line.length > 1048576) return
    var value
    try {
      value = JSON.parse(line)
    } catch (error) {
      root.broadcast("error", null)
      return
    }
    if (!value || value.schemaVersion !== 1
        || typeof value.providerEpoch !== "string"
        || typeof value.revision !== "number"
        || !isFinite(value.revision)
        || Math.floor(value.revision) !== value.revision
        || value.revision < 0) {
      root.broadcast("error", null)
      return
    }
    if (root.sourceEpoch && value.providerEpoch !== root.sourceEpoch) return
    if (root.sourceRevision >= 0 && value.revision <= root.sourceRevision) return
    root.sourceEpoch = value.providerEpoch
    root.sourceRevision = value.revision
    root.latestSnapshot = value
    root.restartDelay = 1000
    root.broadcast("ready", value)
  }

  function providerStopped(exitCode) {
    startupTimer.stop()
    if (root.stoppingForIdle || root.activeCount <= 0) return
    root.latestSnapshot = null
    root.sourceEpoch = ""
    root.sourceRevision = -1
    root.broadcast("error", null)
    if (!restartTimer.running) {
      restartTimer.interval = root.restartDelay
      root.restartDelay = Math.min(30000, root.restartDelay * 2)
      restartTimer.restart()
    }
  }

  Process {
    id: providerProcess
    running: false
    stdinEnabled: true
    stdout: SplitParser {
      onRead: data => root.acceptLine(data)
    }
    // Drain stderr without surfacing private provider/session data in logs.
    stderr: SplitParser {
      onRead: function(data) {}
    }
    onExited: function(exitCode) {
      root.providerStopped(exitCode)
    }
  }

  Timer {
    id: startupTimer
    interval: 750
    repeat: false
    onTriggered: {
      if (root.activeCount > 0 && !providerProcess.running)
        root.providerStopped(-1)
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    repeat: false
    onTriggered: root.startProvider()
  }

  Component.onDestruction: {
    root.leases.slice().forEach(function(lease) {
      lease.publish = null
      lease.released = true
    })
    root.leases = []
    root.activeCount = 0
    root.stopProvider()
  }
}
