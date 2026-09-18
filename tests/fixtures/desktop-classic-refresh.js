// Frozen verbatim from components/Dock.qml at
// 1a81fe650f686f1b8dfb10b25f5c0d1de6a4bab8. Test oracle only; never ship/import in QML.
  function refreshVisibleItems() {
    if (root.workspaceDragActive) {
      root.workspacePresentationDirty = true
      return
    }
    if (groupedRequested) {
      var monitor = dockHyprMonitor
      var ipc = monitor ? monitor.lastIpcObject || monitor : ({})
      var records = toplevels.map(function(toplevel) {
        return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
          toplevel, hyprToplevels, windowActions ? windowActions.minimizedOriginsSnapshot : ({})))
      })
      var baseItems = DockModel.buildVisibleItems(
        pinned, toplevels, applications, hyprToplevels,
        false, false, hiddenApplications)
      var localizedItems = WorkspaceGroupModel.prepareWorkspaceItems(
        baseItems, records, workspaceGroups)
      var nextPresentation = WorkspaceModel.buildWorkspacePresentation(
        localizedItems, records, hyprWorkspaces, {
          monitor: DockWindowModel.monitorIdentity(monitor),
          monitorScope: workspaceMonitorScope,
          monitorOrder: workspaceMonitorOrder,
          activeWorkspace: workspaceMonitorScope === "all" ? focusedScopeWorkspace
            : DockWindowModel.workspaceIdentity(ipc.activeWorkspace
            || (monitor ? monitor.activeWorkspace : null)),
          monitors: hyprMonitors,
          groupWindows: false,
          workspaceGroups: workspaceGroups
        })
      nextPresentation = WorkspaceGroupModel.decorateWorkspacePresentation(
        nextPresentation, workspaceGroups)
      if (badgeTracker && screen)
        badgeTracker.syncWorkspaceScopes(screen.name,
          nextPresentation.groups.reduce(function(items, group) {
            return items.concat(group.items)
          }, []).concat(nextPresentation.globalLaunchers, nextPresentation.fallbackItems))
      if (!WorkspaceModel.presentationsEqual(workspacePresentation, nextPresentation)) {
        windowPreview.dismissImmediately()
        workspacePresentation = nextPresentation
      }
    }
    var flatRecords = filteredToplevels.map(function(toplevel) {
      return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
        toplevel, hyprToplevels, windowActions ? windowActions.minimizedOriginsSnapshot : ({})))
    })
    var flatBaseItems = DockModel.buildVisibleItems(
      pinned, filteredToplevels, applications, hyprToplevels, false,
      false, hiddenApplications)
    var nextItems = WorkspaceGroupModel.buildFlatPresentation(
      flatBaseItems, flatRecords, workspaceGroups, sortByWorkspace)
    if (!DockModel.visibleItemsEqual(visibleItems, nextItems)) {
      windowPreview.dismissImmediately()
      visibleItems = nextItems
    }
    if (root.revealAfterWorkspaceDrag) {
      root.revealAfterWorkspaceDrag = false
      Qt.callLater(root.revealActiveWorkspace)
    }
  }
