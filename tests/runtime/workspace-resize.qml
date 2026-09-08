import QtQuick
import Quickshell
import "components" as Components

// Requires Quickshell's Wayland panel backend; the test never shows a window.
ShellRoot {
  function settle(item) {
    for (var child of item.children || []) settle(child)
    if (typeof item.forceLayout === "function") item.forceLayout()
  }

  Components.DockWindowActions { id: actions }

  Components.Dock {
    id: dock
    visible: false
    // Feed a fixed presentation so live desktop events cannot alter the fixture.
    function refreshVisibleItems() {}
    screen: Quickshell.screens[0]
    settings: ({ workspaceLayout: "grouped", iconSize: 24, pinned: [] })
    showTrash: false
    windowActions: actions
    badgeTracker: null
    trashItemCount: 0
    trashStateKnown: true
    workspaceWindowCounts: ({})
    workspaceCountsReady: true
    workspaceCountsRevision: 0
    scopeRevision: 0
  }

  Timer {
    interval: 200
    running: true
    onTriggered: {
      settle(dock.contentItem)
      var before = dock.implicitWidth
      var groups = []
      for (var i = 1; i <= 8; ++i)
        groups.push({ identity: "id:" + i, label: String(i), count: 0,
          active: i === 1, items: [], urgent: false })
      dock.workspacePresentation = { groups: groups, globalLaunchers: [],
        fallbackItems: [], renderedItems: [] }
      finish.start()
      finish.before = before
    }
  }

  Timer {
    id: finish
    property real before
    interval: 100
    onTriggered: {
      settle(dock.contentItem)
      if (dock.implicitWidth !== before)
        throw new Error("Workspace updates resized the native panel: "
          + before + " -> " + dock.implicitWidth)
      var region = dock.mask.item
      if (region.width !== dock.compactPanelExtent || region.width >= dock.implicitWidth
          || region.x * 2 + region.width !== dock.width)
        throw new Error("Compact input region must stay centered and exclude transparent sides")
      dock.workspacePresentation = { groups: [], globalLaunchers: [],
        fallbackItems: [], renderedItems: [] }
      settle(dock.contentItem)
      if (dock.implicitWidth !== before || region.width !== dock.compactPanelExtent)
        throw new Error("Removing workspaces must shrink only the compact content and input region")
      console.log("workspace-resize: PASS")
      Qt.quit()
    }
  }
}
