import QtQuick
import Quickshell
import Quickshell.Io
import "." as Plugin
import "tests/fixtures" as Fixtures

// Fixture-supplied desktop snapshots, but REAL host, writer, controller, panel,
// viewport, delegates, services and compositor layer probes. No copied renderer.
// Stop the guest's normal dock first. Never run alongside a production host.
ShellRoot {
  id: root
  property var host: null
  property var widgetRequests: []
  property var savedPopup: null
  property var disposableAnchor: null
  property real windowScrollBefore: 0
  Fixtures.SidebarWidgetFixture { id: widgetOne; widgetId: "fixture.one" }
  Fixtures.SidebarWidgetFixture { id: widgetTwo; widgetId: "fixture.two" }
  Component { id: widgetAnchorFactory; Item { width:44; height:44 } }
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
        if (++root.ticks > 150) throw new Error("sidebar fixture timeout")
        if (root.probing || layers.running) return
        if (root.host && (!root.host.settingsLoaded || root.host.settingsWriteState === "saving")) return
        var h = root.host
        var controller = h ? h.sidebarController : null
        if (root.step === 0) {
          if (!h.sidebarPanel) return
          require(h.sidebarPanel.widgetArea.height === 0, "empty widget list reserved footer space")
          require(widgetOne.starts === 0 && widgetTwo.starts === 0, "disabled provider started")
          // Only the harness injects providers/requested test IDs. The production
          // writer/schema stays untouched and continues to reject these IDs.
          controller.widgetRegistry = {"fixture.one":widgetOne.descriptor,"fixture.two":widgetTwo.descriptor}
          controller.settings = Qt.binding(function() {
            return Object.assign({},root.host ? root.host.settings : {},{sidebarWidgets:root.widgetRequests})
          })
          root.widgetRequests = ["fixture.one","fixture.two","future.clock"]
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
          var footer = h.sidebarPanel.widgetArea
          require(footer.height > 0 && footer.height <= footer.layout.cap, "actual footer bounds")
          require(footer.slots.count === 3, "ordered provider slots missing")
          require(footer.slots.itemAt(0).modelData === "fixture.one", "provider order changed")
          require(footer.slots.itemAt(0).view.loadedItem !== null, "real expanded widget view missing")
          require(widgetOne.acquisitions === 1 && widgetOne.subscriptions === 1, "host lease not singular")
          root.windowScrollBefore = h.sidebarPanel.viewport.listView.contentY
          footer.scrollView.contentY = Math.min(10, Math.max(0,footer.scrollView.contentHeight-footer.height))
          require(h.sidebarPanel.viewport.listView.contentY === root.windowScrollBefore, "widget scrolling moved windows")
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
          widgetOne.publish("error")
          require(controller.widgetView("fixture.one").status === "error", "provider error not isolated")
          require(controller.toggleApplication(root.appKey), "provider error blocked window navigation")
        } else if (root.step === 3) {
          require(root.windows().length === 1, "fold did not remove only this workspace's members")
          require(root.firstDelegate === null || !Qt.isQtObject(root.firstDelegate), "folded member delegate survived removal")
          widgetOne.publish("ready")
          controller.requestCollapse()
        } else if (root.step === 4) {
          require(controller.collapsed, "collapse not accepted by the sole writer")
          require(widgetOne.subscriptions === 1 && widgetTwo.subscriptions === 1, "collapse restarted providers")
          require(h.sidebarPanel.widgetArea.slots.itemAt(0).view.presentation === "compact", "rail did not load compact factory")
          widgetOne.notify("once"); widgetOne.notify("once")
          require(widgetOne.notifications === 1, "duplicate fixture notification")
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
          require(widgetOne.stops === 1 && widgetOne.releases === 0, "classic did not suspend the retained lease")
          widgetOne.callbacks[0]({status:"ready",revision:9999,data:{text:"discarded stale fixture result"}})
          require(controller.widgetManager.diagnostics().counters.ignoredUpdates > 0, "suspended callback was accepted")
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
          require(widgetOne.acquisitions === 1 && widgetOne.subscriptions === 2, "resume reacquired or duplicated subscriptions")
          h.saveSetting("sidebarEdge","right")
        } else if (root.step === 9) {
          require(widgetOne.subscriptions === 2, "edge reflow restarted provider")
          require(h.sidebarPanel.anchors.right && h.sidebarPanel.anchors.top && h.sidebarPanel.anchors.bottom, "three-edge reservation contract")
          require(h.sidebarPanel.exclusiveZone === h.sidebarPanel.implicitWidth, "reservation differs from effective width")
          root.probe(1,0)
        } else if (root.step === 10) {
          controller.screens = [] // Simulated topology, real surface teardown.
        } else if (root.step === 11) {
          require(h.sidebarPanel === null, "zero-screen snapshot retained a surface")
          require(widgetOne.stops === 2 && widgetOne.releases === 0, "screen removal did not suspend exactly once")
          root.probe(0,0)
        } else if (root.step === 12) {
          controller.screens = Quickshell.screens
        } else if (root.step === 13) {
          require(h.sidebarPanel !== null, "topology recovery failed")
          require(h.settings.position === "bottom" && h.settings.iconSize === 42, "classic preferences changed")
          require(widgetOne.subscriptions === 3 && widgetOne.acquisitions === 1, "screen recovery lifecycle")
          var area = h.sidebarPanel.widgetArea
          area.openWidget("fixture.one",area.slots.itemAt(0).button)
          root.savedPopup = area.popupWindow
        } else if (root.step === 14) {
          var area = h.sidebarPanel.widgetArea
          require(area.popupWindow.visible && !area.popupWindow.grabFocus, "actual popup missing or grabs keyboard focus")
          require(area.popupGeometry.x + area.popupGeometry.width <= 0, "right-edge popup did not open inward")
          require(area.popupGeometry.y >= 0 && area.popupGeometry.y + area.popupGeometry.height <= h.sidebarPanel.height,
            "bottom popup escaped the available screen height")
          require(area.popupWindow.width > 0 && area.popupWindow.height > 0, "native popup geometry absent")
          area.openWidget("fixture.two",area.slots.itemAt(1).button)
        } else if (root.step === 15) {
          require(controller.widgetPopupId === "fixture.two", "second selection did not replace first popup")
          require(h.sidebarPanel.widgetArea.popupWindow === root.savedPopup, "second popup host was created")
          root.widgetRequests = ["fixture.one","future.clock"]
        } else if (root.step === 16) {
          require(!h.sidebarPanel.widgetArea.popupWindow.visible, "removed provider retained its popup")
          require(widgetTwo.releases === 1 && widgetTwo.stops === 3, "disabled provider cleanup not exactly once")
          var area = h.sidebarPanel.widgetArea
          area.availableContentHeight = 90
          area.windowRowHeight = 120 // Large-font/low-height boundary on the actual area.
        } else if (root.step === 17) {
          var area = h.sidebarPanel.widgetArea
          require(area.height === 0 && area.overflowNeeded, "tiny footer did not move to header overflow")
          require(h.sidebarPanel.widgetOverflowButton.visible, "widget header overflow unreachable")
          require(h.sidebarPanel.viewport.height > 0, "footer displaced window navigation")
          area.openOverflow(h.sidebarPanel.widgetOverflowButton)
        } else if (root.step === 18) {
          require(h.sidebarPanel.widgetArea.popupWindow.visible && controller.widgetPopupId === "*", "header overflow popup missing")
          controller.openWidgetPopup("fixture.one",controller.widgetPopupAnchor)
          require(h.sidebarPanel.widgetArea.popupWindow === root.savedPopup, "overflow created another popup host")
          root.widgetRequests = []
        } else if (root.step === 19) {
          require(h.sidebarPanel.widgetArea.height === 0 && !h.sidebarPanel.widgetOverflowButton.visible, "disabled widgets left blank gap/overflow")
          require(controller.widgetPopupId === "", "empty list kept a popup")
          require(widgetOne.releases === 1, "removed provider cleanup count")
          root.widgetRequests = ["fixture.one"]
          h.saveSetting("sidebarEdge","left") // New actual area restores normal geometry bindings.
        } else if (root.step === 20) {
          require(widgetOne.acquisitions === 2, "provider not acquired once on re-enable")
          widgetOne.callbacks[0]({status:"error",revision:99999})
          require(controller.widgetView("fixture.one").status === "ready", "old lease result poisoned re-enabled widget")
          var area = h.sidebarPanel.widgetArea
          root.disposableAnchor = widgetAnchorFactory.createObject(h.sidebarPanel.contentItem,
            {x:0,y:h.sidebarPanel.height-44,width:44,height:44})
          controller.openWidgetPopup("fixture.one",root.disposableAnchor)
        } else if (root.step === 21) {
          var area=h.sidebarPanel.widgetArea
          require(area.popupWindow.visible, "left popup missing")
          require(area.popupGeometry.x >= h.sidebarPanel.width, "left popup did not open inward")
          require(area.popupGeometry.y + area.popupGeometry.height <= h.sidebarPanel.height, "left bottom popup offscreen")
          root.disposableAnchor.destroy(); root.disposableAnchor=null
        } else if (root.step === 22) {
          require(controller.widgetPopupId === "", "destroyed anchor retained popup")
          var area=h.sidebarPanel.widgetArea
          area.openWidget("fixture.one",area.slots.itemAt(0).button)
          h.saveSetting("sidebarExpandedWidth",240)
        } else if (root.step === 23) {
          require(widgetOne.subscriptions === 4, "resize restarted backend")
          require(h.sidebarPanel.viewport.rowCount > 0, "widget popup broke window list")
          controller.requestCollapse()
        } else if (root.step === 24) {
          require(!h.sidebarPanel.widgetArea.popupWindow.visible, "collapse retained a stale anchor")
          require(widgetOne.subscriptions === 4 && widgetOne.notifications === 1, "reflow duplicated work/notification")
          widgetOne.externalOwners=1
          root.host.destroy()
          root.host = null
        } else if (root.step === 25) {
          require(widgetOne.releases === 2, "host destruction leaked/repeated lease release")
          require(widgetOne.backendRunning && widgetOne.stops === 3, "sidebar stopped shared outside owner")
          widgetOne.externalOwners=0
          root.probe(0,0)
        } else {
          console.log("sidebar: PASS (production host/panel/delegates/widget area/views/popup, bounded footer, errors, leases, rail, layers, teardown)")
          Quickshell.quit()
        }
        root.step++
      } catch (error) { root.fail(error) }
    }
  }
}
