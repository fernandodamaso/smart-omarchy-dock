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

  Components.DockWorkspaceGroup {
    id: transitionGroup
    label: "3"
    count: hasApp ? 1 : 0
    active: true
    slotSize: 24
    property bool hasApp: false
    property real appWidth: 24
    Loader {
      width: transitionGroup.hasApp ? transitionGroup.appWidth : 0
      height: 24
      active: transitionGroup.hasApp
      sourceComponent: Rectangle { width: 24; height: 24 }
    }
  }

  function checkCompactLabels() {
    var originalLabel = transitionGroup.label
    transitionGroup.label = "*"
    settle(transitionGroup)
    var starHeaderWidth = transitionGroup.headerWidth
    var cases = [
      ["1", "1"], ["2", "2"], ["12", "12"], ["01", "01"], ["0", "0"],
      ["Design work", "*"], ["Notes", "*"], ["日本語", "*"],
      ["Other windows", "*"], ["special:scratchpad", "*"],
      ["1:dev", "*"], ["1.5", "*"], ["", "*"], ["3", "3"]
    ]
    for (var i = 0; i < cases.length; ++i) {
      transitionGroup.label = cases[i][0]
      settle(transitionGroup)
      if (transitionGroup.displayLabel !== cases[i][1]
          || transitionGroup.label !== cases[i][0])
        throw new Error("Workspace display label mismatch: " + cases[i][0])
      if (cases[i][1] === "*" && transitionGroup.headerWidth !== starHeaderWidth)
        throw new Error("Non-numeric header retained expanded width: " + cases[i][0])
    }
    transitionGroup.label = originalLabel
    settle(transitionGroup)
  }

  function dividerFor(group) {
    for (var i = 0; i < group.children.length; ++i) {
      var child = group.children[i]
      if (child.width === 1 && child.height >= 18) return child
    }
    return null
  }

  Timer {
    interval: 200
    running: true
    onTriggered: {
      settle(dock.contentItem)
      settle(transitionGroup)
      checkCompactLabels()
      var divider = dividerFor(transitionGroup)
      if (!divider || divider.visible)
        throw new Error("Empty workspace cards must hide their internal divider")
      var emptyWidth = transitionGroup.width
      transitionGroup.hasApp = true
      settle(transitionGroup)
      if (!divider.visible || divider.x + divider.width > transitionGroup.width)
        throw new Error("Populated workspace cards must retain an internal divider")
      var fullWidth = transitionGroup.width
      transitionGroup.appWidth = 0.01
      settle(transitionGroup)
      if (transitionGroup.width - emptyWidth > 0.1)
        throw new Error("First icon added padding discontinuously")
      transitionGroup.appWidth = 12
      settle(transitionGroup)
      if (Math.abs(transitionGroup.width - (emptyWidth + fullWidth) / 2) > 0.1)
        throw new Error("Workspace padding must follow icon occupancy")
      transitionGroup.hasApp = false
      settle(transitionGroup)
      if (divider.visible)
        throw new Error("Removing the last app must hide the internal divider")
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
