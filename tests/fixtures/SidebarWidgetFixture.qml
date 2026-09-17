import QtQuick

// TEST ONLY. Never registered by DockHost, the production schema or the CLI.
// The reference-counted backend is deliberately shared with an optional outside
// owner so tests can detect a sidebar accidentally stopping someone else's work.
Item {
  id: root
  property string widgetId: "fixture.one"
  property int acquisitions: 0
  property int releases: 0
  property int starts: 0
  property int stops: 0
  property int subscriptions: 0
  property int notifications: 0
  property int externalOwners: 0
  property bool backendRunning: false
  property bool throwOnAcquire: false
  property var leases: []
  property var callbacks: []
  property var seenEvents: ({})
  property int snapshotRevision: 0
  property string snapshotStatus: "ready"
  readonly property var descriptor: ({id: root.widgetId, label: "Test widget", available: true,
    status: "loading", revision: 1, expandedView: expanded, compactView: compact, popupView: popup,
    acquire: function(owner) { return root.acquire(owner) }})

  function syncBackend() {
    var next = root.externalOwners > 0 || root.leases.some(function(lease) { return lease.active && !lease.released })
    if (next === root.backendRunning) return
    root.backendRunning = next
    if (next) { root.starts++; root.subscriptions++ }
    else root.stops++
  }
  function acquire(owner) {
    root.acquisitions++
    if (root.throwOnAcquire) throw new Error("private provider failure must not enter diagnostics")
    var lease = {provider:root, active:false, released:false, callback:null,
      setActive:function(active, publish) {
        if (lease.released) throw new Error("released lease reused")
        lease.active = active
        lease.callback = active ? publish : null
        root.syncBackend()
        if (active) {
          root.callbacks = root.callbacks.concat([publish])
          publish({status:root.snapshotStatus, revision:root.snapshotRevision, data:{text:"Fixture content"}})
        }
      },
      release:function() {
        if (lease.released) throw new Error("lease released twice")
        lease.released = true
        lease.active = false
        lease.callback = null
        root.releases++
        root.leases = root.leases.filter(function(candidate) { return candidate !== lease })
        root.syncBackend()
      }}
    root.leases = root.leases.concat([lease])
    return lease
  }
  function publish(status) {
    root.snapshotStatus = status
    root.snapshotRevision++
    root.leases.forEach(function(lease) {
      if (lease.callback) lease.callback({status:status,revision:root.snapshotRevision,
        data:{text:"Fixture content", privateToken:"never-log-this"}})
    })
  }
  function notify(eventId) {
    if (!root.backendRunning || Object.prototype.hasOwnProperty.call(root.seenEvents, eventId)) return
    var next = Object.assign({}, root.seenEvents)
    next[eventId] = true
    root.seenEvents = next
    root.notifications++
  }
  onExternalOwnersChanged: root.syncBackend()

  Component {
    id: expanded
    Item {
      property var widgetContext: ({})
      implicitHeight: 64
      Text { anchors.centerIn: parent; text: parent.widgetContext.data ? parent.widgetContext.data.text : ""; textFormat: Text.PlainText }
    }
  }
  Component {
    id: compact
    Item {
      property var widgetContext: ({})
      implicitHeight: 44
      Text { anchors.centerIn: parent; text: "T"; textFormat: Text.PlainText }
    }
  }
  Component {
    id: popup
    Item {
      property var widgetContext: ({})
      implicitHeight: 128
      Text { anchors.centerIn: parent; text: "Test-only popup"; textFormat: Text.PlainText }
    }
  }
}
