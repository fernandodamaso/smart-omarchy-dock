import QtQuick
import QtTest
import "../components"

TestCase {
  name: "SidebarController"
  when: windowShown
  width: 600; height: 400
  QtObject {
    id: writer
    property var writes: []
    property bool busy: false
    function saveSetting(key, value) {
      if (busy) return {ok:false,error:{code:"E_BUSY"},data:{applied:false}}
      writes = writes.concat([{key:key,value:value}])
      return {ok:false,error:{code:"E_BUSY"},data:{applied:true,persisted:false}}
    }
  }
  Component { id: factory; DockSidebarController { host: writer } }
  Component {
    id: toplevelFactory
    QtObject {
      property string appId: "browser"
      property string title: ""
    }
  }
  function test_actual_controller_identity_folds_and_collapse_intent() {
    // Native toplevel handles must keep QObject identity across property injection.
    var a = createTemporaryObject(toplevelFactory, this, {title:"A"})
    var b = createTemporaryObject(toplevelFactory, this, {title:"B"})
    var screen = {name:"DP-1",width:1920,height:1080}
    var c = createTemporaryObject(factory, this, {
      settings: {presentationMode:"sidebar",pinned:[],workspaceGroups:[],sidebarCollapsed:false},
      screens:[screen], monitors:[{id:0,name:"DP-1",activeWorkspace:{id:1}}],
      workspaces:[{id:1,monitorID:0}], toplevels:[a,b],
      hyprToplevels:[{wayland:a,address:"0xa",lastIpcObject:{workspace:{id:1},monitor:0}},
        {wayland:b,address:"0xb",lastIpcObject:{workspace:{id:1},monitor:0}}]
    })
    verify(c !== null)
    verify(c.toplevels[0] === a)
    verify(c.hyprToplevels[0].wayland === a)
    c.refresh()
    compare(c.selectedConnector,"DP-1")
    compare(c.registry.entries.length,2)
    var windows = c.projection.rows.filter(function(r) {return r.kind === "window"})
    compare(windows.length,2)
    var first = windows[0].key
    compare(windows[0].workspaceIdentity,"id:1")
    var apps = c.projection.rows.filter(function(r) {return r.kind === "application"})
    compare(apps.length,1)
    var app = apps[0]
    c.toggleApplication(app.key); c.refresh()
    compare(c.projection.rows.filter(function(r) {return r.kind === "window"}).length,0)
    // Shared projection stays expanded; fold still hides members. Rail chrome is
    // per-panel via collapsedFor, not a second projection mode.
    verify(c.folds[app.key])
    compare(c.collapsedFor(screen), false)
    c.settings = Object.assign({}, c.settings, {
      sidebarCollapsedByMonitor: { "DP-1": true }
    })
    compare(c.collapsedFor(screen), true)
    compare(c.collapsedFor({name:"HDMI-A-1"}), false)
    writer.writes=[]; writer.busy=false
    var reply=c.requestCollapse(screen)
    verify(reply.data.applied)
    compare(writer.writes.length,1)
    compare(writer.writes[0].key,"sidebarCollapsedByMonitor")
    compare(writer.writes[0].value["DP-1"], false)
    writer.busy=true; c.requestCollapse(screen)
    compare(writer.writes.length,1)
    c.toplevels=[b]; c.refresh()
    compare(c.registry.entries.length,1)
    c.screens=[]; c.refresh()
    compare(c.selectedScreen,null)
    compare(c.projection.rows.length,0)
  }

  Component {
    id: herdrServiceFactory
    QtObject {
      id: svc
      property var writes: []
      property string sourceEpoch: "epoch-1"
      property int sourceRevision: 1
      property bool running: true
      property var latestSnapshot: null
      property int activeCount: 0
      property var leases: []
      function setWindowProcesses(revision, pids) {
        svc.writes = svc.writes.concat([{ revision: revision, pids: pids.slice() }])
        return true
      }
      function acquire(owner) {
        var lease = {
          provider: svc, active: false, released: false, publish: null, revision: 0,
          setActive: function(active, publish) {
            if (lease.released) return
            active = active === true
            if (active) {
              lease.publish = publish
              if (!lease.active) {
                lease.active = true
                svc.activeCount++
              }
              if (svc.latestSnapshot && publish)
                publish({ status: "ready", revision: ++lease.revision, data: svc.latestSnapshot })
            } else {
              lease.publish = null
              if (lease.active) {
                lease.active = false
                svc.activeCount = Math.max(0, svc.activeCount - 1)
              }
            }
          },
          release: function() {
            if (lease.released) return
            if (lease.active) {
              lease.active = false
              svc.activeCount = Math.max(0, svc.activeCount - 1)
            }
            lease.publish = null
            lease.released = true
          }
        }
        svc.leases = svc.leases.concat([lease])
        return lease
      }
      function publishSnapshot(snap) {
        svc.latestSnapshot = snap
        svc.sourceEpoch = snap.providerEpoch
        svc.sourceRevision = snap.revision
        svc.running = true
        svc.leases.forEach(function(lease) {
          if (lease.publish)
            lease.publish({ status: "ready", revision: ++lease.revision, data: snap })
        })
      }
      function simulateRestart() {
        svc.running = false
        svc.sourceEpoch = ""
        svc.sourceRevision = -1
        svc.latestSnapshot = null
        svc.leases.forEach(function(lease) {
          if (lease.publish)
            lease.publish({ status: "error", revision: ++lease.revision, data: null })
        })
        svc.running = true
        svc.leases.forEach(function(lease) {
          if (lease.publish)
            lease.publish({ status: "loading", revision: ++lease.revision, data: null })
        })
      }
    }
  }

  function test_herdr_window_process_identity_revision_and_gating() {
    var service = createTemporaryObject(herdrServiceFactory, this)
    verify(service !== null)
    var a = createTemporaryObject(toplevelFactory, this, { title: "A" })
    var b = createTemporaryObject(toplevelFactory, this, { title: "B" })
    var screen = { name: "DP-1", width: 1920, height: 1080 }
    var c = createTemporaryObject(factory, this, {
      widgetRegistry: {
        "herdr.agents": {
          id: "herdr.agents",
          available: true,
          acquire: function(owner) { return service.acquire(owner) }
        }
      },
      settings: {
        presentationMode: "sidebar",
        pinned: [],
        workspaceGroups: [],
        sidebarCollapsed: false,
        sidebarWidgets: ["herdr.agents"]
      },
      screens: [screen],
      monitors: [{ id: 0, name: "DP-1", activeWorkspace: { id: 1 } }],
      workspaces: [{ id: 1, monitorID: 0 }],
      toplevels: [a],
      hyprToplevels: [{
        wayland: a, address: "0xa",
        lastIpcObject: { workspace: { id: 1 }, monitor: 0, pid: 40 }
      }]
    })
    verify(c !== null)
    c.refresh()
    compare(service.writes.length, 1)
    compare(service.writes[0].revision, 1)
    compare(service.writes[0].pids, [40])
    var firstKey = c.registry.entries[0].key
    compare(c.windowProcessRevision, 1)

    // Workspace move alone does not bump identity revision.
    c.hyprToplevels = [{
      wayland: a, address: "0xa",
      lastIpcObject: { workspace: { id: 2 }, monitor: 0, pid: 40 }
    }]
    c.refresh()
    compare(c.windowProcessRevision, 1)
    compare(service.writes.length, 1)

    // Replacement handle with same PID bumps revision and reissues.
    c.toplevels = [b]
    c.hyprToplevels = [{
      wayland: b, address: "0xb",
      lastIpcObject: { workspace: { id: 1 }, monitor: 0, pid: 40 }
    }]
    c.refresh()
    compare(c.windowProcessRevision, 2)
    compare(service.writes.length, 2)
    compare(service.writes[1].revision, 2)
    var secondKey = c.registry.entries[0].key
    verify(secondKey !== firstKey)

    // Obsolete reply for revision 1 is withheld after replacement.
    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: 10,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: { revision: 1, identities: [{ pid: 40, startTime: 40 }] }
    })
    wait(0)
    compare(JSON.stringify(c.herdrAssociations.byWindowKey), "{}")

    // Matching revision+epoch applies the association.
    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: 11,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: { revision: 2, identities: [{ pid: 40, startTime: 40 }] }
    })
    wait(0)
    var assoc = c.herdrAssociations.byWindowKey
    compare(assoc[secondKey], "local-a")
  }

  function test_herdr_associations_cleared_on_provider_restart() {
    var service = createTemporaryObject(herdrServiceFactory, this)
    verify(service !== null)
    var a = createTemporaryObject(toplevelFactory, this, { title: "A" })
    var screen = { name: "DP-1", width: 1920, height: 1080 }
    var c = createTemporaryObject(factory, this, {
      widgetRegistry: {
        "herdr.agents": {
          id: "herdr.agents",
          available: true,
          acquire: function(owner) { return service.acquire(owner) }
        }
      },
      settings: {
        presentationMode: "sidebar",
        pinned: [],
        workspaceGroups: [],
        sidebarCollapsed: false,
        sidebarWidgets: ["herdr.agents"]
      },
      screens: [screen],
      monitors: [{ id: 0, name: "DP-1", activeWorkspace: { id: 1 } }],
      workspaces: [{ id: 1, monitorID: 0 }],
      toplevels: [a],
      hyprToplevels: [{
        wayland: a, address: "0xa",
        lastIpcObject: { workspace: { id: 1 }, monitor: 0, pid: 40 }
      }]
    })
    verify(c !== null)
    c.refresh()
    var windowKey = c.registry.entries[0].key
    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: 5,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: { revision: 1, identities: [{ pid: 40, startTime: 40 }] }
    })
    wait(0)
    compare(c.herdrAssociations.byWindowKey[windowKey], "local-a")

    // Provider exit without handle change must withhold the previous map.
    service.simulateRestart()
    wait(0)
    compare(JSON.stringify(c.herdrAssociations.byWindowKey), "{}")
    compare(JSON.stringify(c.herdrAssociations.unmatchedServerIds), "[]")

    // New epoch with unmatched metadata revision still withholds.
    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-2",
      revision: 1,
      servers: [],
      windowProcesses: { revision: 0, identities: [] }
    })
    wait(0)
    compare(JSON.stringify(c.herdrAssociations.byWindowKey), "{}")

    // Restored only after a matching current-epoch reply.
    var requestRevision = c.windowProcessRevision
    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-2",
      revision: 2,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: {
        revision: requestRevision,
        identities: [{ pid: 40, startTime: 40 }]
      }
    })
    wait(0)
    compare(c.herdrAssociations.byWindowKey[windowKey], "local-a")
  }

  function test_herdr_empty_targets_unresolved_fallback_then_resolve() {
    var service = createTemporaryObject(herdrServiceFactory, this)
    verify(service !== null)
    var screen = { name: "DP-1", width: 1920, height: 1080 }
    var c = createTemporaryObject(factory, this, {
      widgetRegistry: {
        "herdr.agents": {
          id: "herdr.agents",
          available: true,
          acquire: function(owner) { return service.acquire(owner) }
        }
      },
      settings: {
        presentationMode: "sidebar",
        pinned: [],
        workspaceGroups: [],
        sidebarCollapsed: false,
        sidebarWidgets: ["herdr.agents"]
      },
      screens: [screen],
      monitors: [{ id: 0, name: "DP-1", activeWorkspace: { id: 1 } }],
      workspaces: [{ id: 1, monitorID: 0 }],
      toplevels: [],
      hyprToplevels: []
    })
    verify(c !== null)
    c.refresh()
    compare(c.windowProcessRevision, 1)
    compare(service.writes.length, 1)
    compare(service.writes[0].revision, 1)
    compare(service.writes[0].pids.length, 0)

    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: 3,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: { revision: 1, identities: [] }
    })
    wait(0)
    compare(JSON.stringify(c.herdrAssociations.byWindowKey), "{}")
    compare(JSON.stringify(c.herdrAssociations.unmatchedServerIds), '["local-a"]')

    var win = createTemporaryObject(toplevelFactory, this, { title: "Term" })
    c.toplevels = [win]
    c.hyprToplevels = [{
      wayland: win, address: "0xc",
      lastIpcObject: { workspace: { id: 1 }, monitor: 0, pid: 40 }
    }]
    c.refresh()
    compare(c.windowProcessRevision, 2)
    compare(service.writes.length, 2)
    compare(service.writes[1].pids, [40])
    var key = c.registry.entries[0].key

    service.publishSnapshot({
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: 4,
      servers: [{
        id: "local-a",
        clients: [{ pid: 41, startTime: 41, ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      windowProcesses: { revision: 2, identities: [{ pid: 40, startTime: 40 }] }
    })
    wait(0)
    compare(c.herdrAssociations.byWindowKey[key], "local-a")
    compare(JSON.stringify(c.herdrAssociations.unmatchedServerIds), "[]")
  }
}
