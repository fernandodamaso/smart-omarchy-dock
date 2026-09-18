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
}
