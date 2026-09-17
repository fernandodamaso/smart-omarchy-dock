import QtQuick
import Quickshell
import Quickshell.Io
import "." as Plugin

// Fixture-supplied desktop snapshots, but REAL host, writer, controller, panel,
// viewport, delegates, services and compositor layer probes. No copied renderer.
// Stop the guest's normal dock first. Never run alongside a production host.
ShellRoot {
  id: root
  property var host: null
  property int step: 0
  property int ticks: 0
  property bool probing: false
  property int expectedSidebar: 0
  property int expectedClassic: 0
  property var firstDelegate: null
  property var firstPanel: null
  property string firstKey: ""
  property string appKey: ""
  property var windowKeys: []
  QtObject { id: a; property string appId: "fixture.browser"; property string title: "Alpha"; property bool activated: false }
  QtObject { id: b; property string appId: "fixture.browser"; property string title: "Beta"; property bool activated: false }
  QtObject { id: c; property string appId: "fixture.browser"; property string title: "Other workspace"; property bool activated: false }
  Component {
    id: hostFactory
    Plugin.DockHost { configPath: Qt.resolvedUrl("fixture-config.json"); runtimeMode: "standalone" }
  }
  function require(value, message) {
    if (!value) throw new Error("sidebar fixture: " + message)
  }
  function fail(error) { console.error(String(error)); Quickshell.quit() }
  function windows() { return root.host.sidebarController.projection.rows.filter(function(r) { return r.kind === "window" }) }
  function delegateFor(key) {
    var panel = root.host.sidebarPanel
    var rows = root.host.sidebarController.projection.rows
    var index = rows.findIndex(function(r) { return r.key === key })
    require(index >= 0, "row key missing")
    var list = panel.viewport.listView
    list.positionViewAtIndex(index, ListView.Contain)
    list.forceLayout()
    return list.itemAtIndex(index)
  }
  function probe(sidebar, classic) {
    root.expectedSidebar = sidebar
    root.expectedClassic = classic
    root.probing = true
    layers.running = true
  }
  function checkLayers(text) {
    try {
      var sidebar = 0, classic = 0
      function visit(value) {
        if (!value || typeof value !== "object") return
        if (value.namespace === "smartdock-sidebar") ++sidebar
        if (value.namespace === "smartdock") ++classic
        Object.keys(value).forEach(function(key) { visit(value[key]) })
      }
      visit(JSON.parse(text))
      require(sidebar === root.expectedSidebar, "actual sidebar layer count " + sidebar + " != " + root.expectedSidebar)
      require(classic === root.expectedClassic, "actual classic layer count " + classic + " != " + root.expectedClassic)
      root.probing = false
    } catch (error) { root.fail(error) }
  }
  Process {
    id: layers
    command: ["hyprctl", "-j", "layers"]
    stdout: StdioCollector { onStreamFinished: root.checkLayers(text) }
  }
  Component.onCompleted: {
    try {
      require(Quickshell.screens.length > 0, "requires an isolated Wayland screen")
      root.host = hostFactory.createObject(root)
      require(root.host !== null, "actual host construction failed")
    } catch (error) { root.fail(error) }
  }
  Timer {
    interval: 250
    running: true
    repeat: true
    onTriggered: {
      try {
        if (++root.ticks > 80) throw new Error("sidebar fixture timeout")
        if (root.probing || layers.running) return
        if (root.host && (!root.host.settingsLoaded || root.host.settingsWriteState === "saving")) return
        var h = root.host
        var controller = h ? h.sidebarController : null
        if (root.step === 0) {
          if (!h.sidebarPanel) return
          // Replace injected snapshot bindings, never production refresh/functions.
          controller.monitors = [{id:0,name:Quickshell.screens[0].name,x:0,y:0,activeWorkspace:{id:1}}]
          controller.workspaces = [{id:1,monitorID:0},{id:2,monitorID:0}]
          controller.toplevels = [a,b,c]
          controller.applications = [{id:"fixture.browser",name:"Fixture browser",icon:"application-x-executable"}]
          controller.hyprToplevels = [
            {wayland:a,address:"",lastIpcObject:{workspace:{id:1},monitor:0}},
            {wayland:b,address:"",lastIpcObject:{workspace:{id:1},monitor:0}},
            {wayland:c,address:"0xc",lastIpcObject:{workspace:{id:2},monitor:0}}]
          controller.focusedWorkspace = "id:1"
          controller.refresh()
        } else if (root.step === 1) {
          require(h.sidebarPanel !== null, "sidebar surface missing")
          require(h.workspaceMonitorDrag.docks.length === 0, "classic docks also exist")
          require(root.windows().length === 3, "three actual window rows required")
          root.windowKeys = root.windows().map(function(r) {return r.key})
          root.firstKey = root.windowKeys[0]
          root.firstDelegate = root.delegateFor(root.firstKey)
          require(root.firstDelegate !== null, "production delegate not created")
          require(root.firstDelegate.kind === "window", "wrong production delegate")
          root.appKey = controller.rowsByKey[root.firstKey].applicationKey
          a.title = "<literal title, not markup>"
          a.activated = true
          root.probe(1,0)
        } else if (root.step === 2) {
          require(root.delegateFor(root.firstKey) === root.firstDelegate, "title update recreated the delegate")
          require(root.firstDelegate.liveTitle === a.title, "live title binding did not update")
          require(root.firstDelegate.focusedWindow, "focus style did not update")
          controller.toggleApplication(root.appKey)
        } else if (root.step === 3) {
          require(root.windows().length === 1, "fold did not remove only this workspace's members")
          require(root.firstDelegate === null || !Qt.isQtObject(root.firstDelegate), "folded member delegate survived removal")
          controller.requestCollapse()
        } else if (root.step === 4) {
          require(controller.collapsed, "collapse not accepted by the sole writer")
          require(JSON.stringify(root.windows().map(function(r) {return r.key})) === JSON.stringify(root.windowKeys), "rail lost/reordered members")
          root.windowKeys.forEach(function(key) {
            var row = root.delegateFor(key)
            require(row !== null && row.collapsed, "actual rail delegate missing")
          })
          require(controller.folds[root.appKey] === true, "rail erased expanded fold state")
          require(h.sidebarPanel.exclusiveZone === Math.min(56,h.sidebarPanel.screen.width), "rail reservation")
          controller.requestCollapse()
        } else if (root.step === 5) {
          require(!controller.collapsed && root.windows().length === 1, "expanded fold state not restored")
          require(h.settings.sidebarExpandedWidth === 320, "collapse changed requested width")
          root.firstPanel = h.sidebarPanel
          h.saveSetting("presentationMode","classic")
        } else if (root.step === 6) {
          require(h.sidebarPanel === null, "old sidebar surface survived classic switch")
          require(root.firstPanel === null || !Qt.isQtObject(root.firstPanel), "old panel object not destroyed")
          require(h.workspaceMonitorDrag.docks.length === Quickshell.screens.length, "classic registration mismatch")
          require(Object.keys(h.badgeTracker.urgentStates).every(function(key) {
            return key.indexOf('workspace:["smartdock-sidebar",') !== 0
          }), "sidebar badge scopes leaked")
          root.probe(0,Quickshell.screens.length)
        } else if (root.step === 7) {
          h.saveSetting("presentationMode","sidebar")
        } else if (root.step === 8) {
          require(h.sidebarPanel !== null && h.workspaceMonitorDrag.docks.length === 0, "renderer branches overlap")
          h.saveSetting("sidebarEdge","right")
        } else if (root.step === 9) {
          require(h.sidebarPanel.anchors.right && h.sidebarPanel.anchors.top && h.sidebarPanel.anchors.bottom, "three-edge reservation contract")
          require(h.sidebarPanel.exclusiveZone === h.sidebarPanel.implicitWidth, "reservation differs from effective width")
          root.probe(1,0)
        } else if (root.step === 10) {
          controller.screens = [] // Simulated topology, real surface teardown.
        } else if (root.step === 11) {
          require(h.sidebarPanel === null, "zero-screen snapshot retained a surface")
          root.probe(0,0)
        } else if (root.step === 12) {
          controller.screens = Quickshell.screens
        } else if (root.step === 13) {
          require(h.sidebarPanel !== null, "topology recovery failed")
          require(h.settings.position === "bottom" && h.settings.iconSize === 42, "classic preferences changed")
          root.host.destroy()
          root.host = null
        } else if (root.step === 14) {
          root.probe(0,0)
        } else {
          console.log("sidebar: PASS (production host/panel/delegates, literal live title, rail parity, layers, teardown)")
          Quickshell.quit()
        }
        root.step++
      } catch (error) { root.fail(error) }
    }
  }
}
