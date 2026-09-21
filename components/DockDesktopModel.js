.pragma library
.import "DockModel.js" as DockModel
.import "DockWindowModel.js" as DockWindowModel
.import "DockWorkspaceModel.js" as WorkspaceModel
.import "DockWorkspaceGroupModel.js" as WorkspaceGroupModel

// Pure construction only. The caller supplies normalized settings and snapshots;
// it retains refresh scheduling, drag freeze, comparisons, badges and previews.
// Sidebar requests all-monitor native inventory without changing saved classic settings.
function build(input) {
  var sidebar = input.mode === "sidebar"
  if (!sidebar && input.mode !== "classic-flat" && input.mode !== "classic-grouped")
    throw new Error("Unsupported desktop presentation mode: " + input.mode)
  if (sidebar) input = Object.assign({}, input, {
    filteredToplevels: input.toplevels,
    settings: Object.assign({}, input.settings, {
      workspaceMonitorScope: "all", workspaceGroups: [], sortByWorkspace: false
    })
  })

  var settings = input.settings
  var records = []
  var workspacePresentation = null
  if (sidebar || input.mode === "classic-grouped") {
    var monitor = input.dockMonitor
    records = input.toplevels.map(function(toplevel) {
      return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
        toplevel, input.hyprToplevels, input.minimizedOrigins))
    })
    var baseItems = sidebar ? sidebarBaseItems(input) : DockModel.buildVisibleItems(
      settings.pinned, input.toplevels, input.applications, input.hyprToplevels,
      false, false, settings.hiddenApplications, settings.windowIconOverrides || [])
    var localizedItems = WorkspaceGroupModel.prepareWorkspaceItems(
      baseItems, records, settings.workspaceGroups)
    workspacePresentation = WorkspaceModel.buildWorkspacePresentation(
      localizedItems, records, input.hyprWorkspaces, {
        monitor: DockWindowModel.monitorIdentity(monitor),
        monitorScope: settings.workspaceMonitorScope,
        monitorOrder: settings.workspaceMonitorOrder,
        activeWorkspace: settings.workspaceMonitorScope === "all" ? input.focusedWorkspace
          : DockWindowModel.workspaceIdentity(
            DockWindowModel.monitorActiveWorkspace(monitor)),
        monitors: input.hyprMonitors,
        groupWindows: false,
        workspaceGroups: settings.workspaceGroups
      })
    workspacePresentation = WorkspaceGroupModel.decorateWorkspacePresentation(
      workspacePresentation, settings.workspaceGroups)
  }

  // Classic maintains the filtered flat snapshot even while grouped is active.
  var flatRecords = input.filteredToplevels.map(function(toplevel) {
    return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
      toplevel, input.hyprToplevels, input.minimizedOrigins))
  })
  var flatBaseItems = sidebar ? baseItems : DockModel.buildVisibleItems(
    settings.pinned, input.filteredToplevels, input.applications, input.hyprToplevels,
    false, false, settings.hiddenApplications, settings.windowIconOverrides || [])
  var visibleItems = WorkspaceGroupModel.buildFlatPresentation(
    flatBaseItems, flatRecords, settings.workspaceGroups, settings.sortByWorkspace)
  return {
    records: sidebar || input.mode === "classic-grouped" ? records : flatRecords,
    visibleItems: visibleItems,
    workspacePresentation: workspacePresentation
  }
}

// An empty Wayland appId is not evidence for matching a pin's empty StartupWMClass.
// Keep such handles reachable with neutral artwork; classic matching is unchanged.
function sidebarBaseItems(input) {
  var known = input.toplevels.filter(function(t) { return !!String(t.appId || "").trim() })
  var unknown = input.toplevels.filter(function(t) { return !String(t.appId || "").trim() })
  return DockModel.buildVisibleItems(input.settings.pinned, known, input.applications,
    input.hyprToplevels, false, false, input.settings.hiddenApplications).concat(
      DockModel.buildVisibleItems([], unknown, [], input.hyprToplevels, false, false, [], input.settings.windowIconOverrides || []))
}
