import QtQuick
import "DockModel.js" as DockModel
import "DockWindowModel.js" as WindowModel
import "DockDesktopModel.js" as DesktopModel
import "DockSidebarModel.js" as SidebarModel

// Host-owned session/view state. All compositor data and action/writer services
// are injected; this object never adds a watcher, provider, timer or config file.
Item {
  id: root
  required property var host
  property var settings: ({})
  property var screens: []
  property var monitors: []
  property var workspaces: []
  property var applications: []
  property var toplevels: []
  property var hyprToplevels: []
  property var minimizedOrigins: ({})
  property string focusedWorkspace: ""
  property int scopeRevision: 0
  property bool interactionBusy: false
  property bool refreshPending: false
  property bool initialized: false
  property var selectedScreen: null
  readonly property string selectedConnector: selectedScreen ? selectedScreen.name : ""
  readonly property string mode: DockModel.normalizeSetting("presentationMode", settings.presentationMode)
  readonly property string edge: DockModel.normalizeSetting("sidebarEdge", settings.sidebarEdge)
  readonly property bool collapsed: DockModel.normalizeSetting("sidebarCollapsed", settings.sidebarCollapsed)
  readonly property var geometry: SidebarModel.geometry(selectedScreen ? selectedScreen.width : 0,
    settings.sidebarExpandedWidth, collapsed)
  property var registry: ({ nextToken: 1, entries: [] })
  property var folds: ({})
  property var projection: SidebarModel.emptyProjection()
  property var scrollAnchor: ({key:"",offset:0})
  property string focusedRowKey: ""
  property string mutationFeedback: ""
  readonly property var rowsByKey: {
    var result = Object.create(null)
    projection.rows.forEach(function(row) { result[row.key] = row })
    return result
  }
  signal aboutToRefresh()
  signal refreshed()
  signal surfaceInvalidated()

  function scheduleRefresh() {
    if (initialized) Qt.callLater(root.refresh)
  }

  function invalidateSurface() {
    root.surfaceInvalidated()
    root.interactionBusy = false
    root.scheduleRefresh()
  }

  function refresh() {
    if (!root.initialized) return
    root.registry = SidebarModel.reconcileHandles(root.registry, root.toplevels)
    var next = root.mode === "sidebar" ? SidebarModel.selectScreen(root.screens, root.monitors,
      root.settings.workspaceMonitorOrder || [],
      DockModel.normalizeSetting("sidebarMonitor", root.settings.sidebarMonitor),
      root.selectedConnector, root.interactionBusy) : null
    if (next !== root.selectedScreen) {
      root.surfaceInvalidated()
      root.interactionBusy = false
      root.selectedScreen = next
    }
    if (root.interactionBusy && next) {
      root.refreshPending = true
      return
    }
    root.refreshPending = false
    root.aboutToRefresh()
    var previous = root.projection.rows.map(function(row) { return row.key })
    if (root.mode !== "sidebar" || !next) {
      root.projection = SidebarModel.emptyProjection()
      root.refreshed()
      return
    }
    var desktop = DesktopModel.build({
      mode: "sidebar", settings: {
        pinned: root.settings.pinned || [], hiddenApplications: DockModel.normalizeSetting(
          "hiddenApplications", root.settings.hiddenApplications), workspaceGroups: [],
        workspaceMonitorScope: "all", workspaceMonitorOrder: DockModel.normalizeSetting(
          "workspaceMonitorOrder", root.settings.workspaceMonitorOrder), sortByWorkspace: false
      }, applications: root.applications, toplevels: root.toplevels,
      filteredToplevels: root.toplevels, hyprToplevels: root.hyprToplevels,
      hyprWorkspaces: root.workspaces, hyprMonitors: root.monitors,
      dockMonitor: WindowModel.monitorForScreen(next, root.monitors),
      minimizedOrigins: root.minimizedOrigins, focusedWorkspace: root.focusedWorkspace
    })
    var projected = SidebarModel.project({desktop: desktop, screens: root.screens,
      monitors: root.monitors, monitorOrder: root.settings.workspaceMonitorOrder || [],
      pinned: root.settings.pinned || [], registry: root.registry,
      folds: root.folds, collapsed: root.collapsed})
    root.scrollAnchor = SidebarModel.recoverAnchor(root.scrollAnchor, previous, projected.rows)
    if (root.focusedRowKey) root.focusedRowKey = SidebarModel.recoverAnchor(
      {key:root.focusedRowKey,offset:0}, previous, projected.rows).key
    // Prune vanished applications; no preferences are written by session folds.
    var liveFolds = Object.create(null)
    projected.monitorSections.forEach(function(m) {
      m.workspaces.forEach(function(w) {
        w.applications.forEach(function(a) { if (root.folds[a.key]) liveFolds[a.key] = true })
      })
    })
    root.folds = liveFolds
    root.projection = projected
    root.refreshed()
  }

  function toggleApplication(key) {
    if (root.interactionBusy || root.collapsed) return false
    var row = root.rowsByKey[key]
    if (!row || row.kind !== "application") return false
    var next = Object.assign({}, root.folds)
    if (next[key]) delete next[key]
    else next[key] = true
    root.folds = next
    root.scheduleRefresh()
    return true
  }

  function requestCollapse() {
    if (root.interactionBusy) return {ok:false,error:{code:"E_BUSY",message:"Finish the active interaction."},data:{applied:false}}
    var reply = root.host.saveSetting("sidebarCollapsed", !root.collapsed)
    // An E_BUSY after acceptance describes persistence, not a rejected intent.
    // Bind to host settings, never queue/replay a previous snapshot or roll back.
    var applied = reply.data && reply.data.applied === true
    root.mutationFeedback = reply.ok || applied ? "" : String(reply.error && reply.error.message || "Preference was not accepted.")
    return reply
  }

  function addressesForRow(row) {
    return (row.members || []).map(function(toplevel) {
      return WindowModel.locationForToplevel(toplevel, root.hyprToplevels, root.minimizedOrigins).address
    }).filter(function(address) { return !!address })
  }

  function profileForRow(row) {
    var service = root.host ? root.host.browserProfileService : null
    var revision = service ? service.revision : 0
    if (!service || !service.available || !row.members || !row.members.length) return null
    var addresses = root.addressesForRow(row)
    if (addresses.length !== row.members.length) return null
    var key = service.profileKeyForAddress(addresses[0])
    if (!key || addresses.some(function(a) { return service.profileKeyForAddress(a) !== key })) return null
    return {key:key, entry:service.profileFor(key)}
  }

  function badgeForRow(row) {
    var tracker = root.host ? root.host.badgeTracker : null
    var revision = tracker ? tracker.revision : 0
    if (!tracker || root.settings.attentionBadgesEnabled === false || !row.item) return "none"
    if (row.kind === "application" && !row.folded) return "none"
    var service = root.host ? root.host.browserProfileService : null
    var serviceRevision = service ? service.revision : 0
    var addresses = root.addressesForRow(row)
    var activities = service && service.available && typeof service.activityRowsForAddresses === "function"
      ? service.activityRowsForAddresses(addresses) : []
    return tracker.badgeFor(row.desktopId,
      {localUrgent:row.urgent === true,primaryOwner:row.primaryOwner === true}, activities)
  }

  onSettingsChanged: root.scheduleRefresh()
  onModeChanged: root.invalidateSurface()
  onEdgeChanged: root.invalidateSurface()
  onScreensChanged: root.refresh()
  onMonitorsChanged: root.scheduleRefresh()
  onWorkspacesChanged: root.scheduleRefresh()
  onApplicationsChanged: root.scheduleRefresh()
  onToplevelsChanged: root.scheduleRefresh()
  onHyprToplevelsChanged: root.scheduleRefresh()
  onMinimizedOriginsChanged: root.scheduleRefresh()
  onFocusedWorkspaceChanged: root.scheduleRefresh()
  onScopeRevisionChanged: root.scheduleRefresh()
  onInteractionBusyChanged: if (!interactionBusy) root.scheduleRefresh()
  Component.onCompleted: { initialized = true; root.refresh() }
}
