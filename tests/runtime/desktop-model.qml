import QtQuick
import Quickshell
import "components" as Components
import "components/DockModel.js" as DockModel
import "components/DockDesktopModel.js" as DesktopModel
import "components/DockWorkspaceModel.js" as WorkspaceModel

// Run only in an isolated Omarchy/Quickshell session. Unlike the geometry
// fixture, this instantiates the actual Dock and never overrides its refresh.
ShellRoot {
  id: root
  property var dock: null
  property int step: 0
  property var cases: [
    ["bottom", "grouped", "all"], ["top", "grouped", "current-monitor"],
    ["left", "grouped", "all"], ["right", "grouped", "current-monitor"],
    ["bottom", "flat", "all"], ["bottom", "grouped", "all"]
  ]

  Components.DockWindowActions { id: actions }
  Components.DockWorkspaceMonitorDrag { id: monitorDrag; windowActions: actions }
  Components.DockBadgeTracker { id: tracker }
  Component {
    id: dockComponent
    Components.Dock {
      visible: false
      screen: Quickshell.screens[0]
      settings: ({ position: "bottom", workspaceLayout: "grouped", pinned: [],
        workspaceMonitorScope: "all", interfaceAnimationsEnabled: false })
      showTrash: false
      windowActions: actions
      workspaceMonitorDrag: monitorDrag
      badgeTracker: tracker
      trashItemCount: 0
      trashStateKnown: true
      workspaceWindowCounts: ({})
      workspaceCountsReady: true
      workspaceCountsRevision: 0
      scopeRevision: 0
    }
  }

  function require(condition, message) {
    if (!condition) throw new Error("desktop-model: " + message)
  }

  function checkSnapshot() {
    var item = root.dock
    item.refreshVisibleItems()
    var result = DesktopModel.build({
      mode: item.groupedRequested ? "classic-grouped" : "classic-flat",
      settings: {
        pinned: item.pinned, hiddenApplications: item.hiddenApplications,
        workspaceGroups: item.workspaceGroups, workspaceMonitorScope: item.workspaceMonitorScope,
        workspaceMonitorOrder: item.workspaceMonitorOrder, sortByWorkspace: item.sortByWorkspace
      },
      applications: item.applications, toplevels: item.toplevels,
      hyprToplevels: item.hyprToplevels, hyprWorkspaces: item.hyprWorkspaces,
      hyprMonitors: item.hyprMonitors, minimizedOrigins: actions.minimizedOriginsSnapshot,
      focusedWorkspace: item.focusedScopeWorkspace, dockMonitor: item.dockHyprMonitor,
      filteredToplevels: item.filteredToplevels
    })
    require(DockModel.visibleItemsEqual(item.visibleItems, result.visibleItems), "flat parity")
    if (item.groupedRequested)
      require(WorkspaceModel.presentationsEqual(item.workspacePresentation,
        result.workspacePresentation), "grouped parity")
    var flat = item.visibleItems
    var grouped = item.workspacePresentation
    item.refreshVisibleItems()
    require(item.visibleItems === flat && item.workspacePresentation === grouped,
      "unchanged refresh replaced an imperative snapshot")
    require(monitorDrag.docks.length === 1, "actual Dock must register exactly once")
    if (!item.groupedRequested)
      require(Object.keys(tracker.urgentStates).every(function(key) {
        return key.indexOf("workspace:") !== 0
      }), "leaving grouped mode leaked badge scopes")
  }

  Component.onCompleted: {
    require(Quickshell.screens.length > 0, "isolated session needs a screen")
    root.dock = dockComponent.createObject(root)
    require(root.dock !== null, "real Dock construction failed")
  }

  Timer {
    interval: 150
    repeat: true
    running: true
    onTriggered: {
      try {
        if (root.step < root.cases.length) {
          var entry = root.cases[root.step]
          root.dock.settings = Object.assign({}, root.dock.settings, {
            position: entry[0], workspaceLayout: entry[1], workspaceMonitorScope: entry[2]
          })
          require(root.dock.groupedRequested ===
            (entry[1] === "grouped" && entry[0] !== "left" && entry[0] !== "right"),
            "classic edge/group policy")
          checkSnapshot()
        } else if (root.step === root.cases.length) {
          root.dock.destroy()
          root.dock = null
        } else {
          require(monitorDrag.docks.length === 0, "Dock destruction leaked a drag registration")
          require(Object.keys(tracker.urgentStates).every(function(key) {
            return key.indexOf("workspace:") !== 0
          }), "Dock destruction leaked badge scopes")
          console.log("desktop-model: PASS (real Dock refresh, mode switches, teardown)")
          Quickshell.quit()
        }
        root.step++
      } catch (error) {
        console.error(String(error))
        Quickshell.quit()
      }
    }
  }
}
