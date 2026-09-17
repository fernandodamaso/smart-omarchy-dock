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
  readonly property var persistentGeometry: SidebarModel.screenGeometry(selectedScreen,
    settings.sidebarExpandedWidth, collapsed)
  property bool resizeActive: false
  property real resizeStartGlobalX: 0
  property int resizeStartWidth: 0
  property int resizePreviewWidth: 0
  property int resizeRequestedAtStart: 320
  property bool resizeCollapsedAtStart: false
  property string resizeEdgeAtStart: "left"
  property string resizeConnectorAtStart: ""
  readonly property var geometry: resizeActive
    ? SidebarModel.screenGeometry(selectedScreen, resizePreviewWidth, false)
    : persistentGeometry
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

  function clearResizeState() {
    root.resizeActive = false
    root.resizeStartGlobalX = 0
    root.resizeStartWidth = 0
    root.resizePreviewWidth = 0
    root.resizeConnectorAtStart = ""
    root.interactionBusy = false
  }

  function cancelResize(reason) {
    if (!root.resizeActive) return false
    root.clearResizeState()
    root.scheduleRefresh()
    return true
  }

  function invalidateSurface() {
    root.cancelResize("surface-invalidated")
    root.surfaceInvalidated()
    root.interactionBusy = false
    root.scheduleRefresh()
  }

  function beginResize(globalX) {
    if (root.mode !== "sidebar" || root.collapsed || !root.selectedScreen
        || !root.persistentGeometry.mapped || root.interactionBusy || root.resizeActive)
      return false
    var pointer = Number(globalX)
    if (!isFinite(pointer)) return false
    root.resizeStartGlobalX = pointer
    root.resizeStartWidth = root.persistentGeometry.expandedWidth
    root.resizePreviewWidth = root.resizeStartWidth
    root.resizeRequestedAtStart = DockModel.normalizeSetting(
      "sidebarExpandedWidth", root.settings.sidebarExpandedWidth)
    root.resizeCollapsedAtStart = root.collapsed
    root.resizeEdgeAtStart = root.edge
    root.resizeConnectorAtStart = root.selectedConnector
    root.resizeActive = true
    root.interactionBusy = true
    root.mutationFeedback = ""
    return true
  }

  function updateResize(globalX) {
    if (!root.resizeActive || !root.selectedScreen
        || root.selectedConnector !== root.resizeConnectorAtStart) return false
    root.resizePreviewWidth = SidebarModel.resizeWidth(root.resizeStartWidth,
      root.resizeStartGlobalX, Number(globalX), root.resizeEdgeAtStart,
      SidebarModel.logicalScreenWidth(root.selectedScreen))
    return true
  }

  function hostIntent(key, value, expectedValue) {
    if (root.host && typeof root.host.saveSettingIntent === "function")
      return root.host.saveSettingIntent(key, value, expectedValue)
    var reply = root.host.saveSetting(key, value)
    var applied = !!(reply && reply.data && reply.data.applied === true)
    return { accepted: !!(reply && (reply.ok || applied)),
      pending: applied && !reply.ok && reply.error && reply.error.code === "E_BUSY",
      reply: reply }
  }

  function finishResize(cancelled) {
    if (!root.resizeActive)
      return {accepted:false,pending:false,reply:{ok:false,error:{code:"E_STATE",message:"No resize is active."},data:{applied:false}}}
    var finalWidth = root.resizePreviewWidth
    var startWidth = root.resizeStartWidth
    var expected = root.resizeRequestedAtStart
    root.clearResizeState()
    if (cancelled === true || finalWidth === startWidth) {
      root.scheduleRefresh()
      return {accepted:true,pending:false,noop:true,
        reply:{ok:true,data:{applied:false,persisted:true,changedKeys:[]},warnings:[]}}
    }
    var result = root.hostIntent("sidebarExpandedWidth", finalWidth, expected)
    if (!result.accepted)
      root.mutationFeedback = String(result.reply && result.reply.error && result.reply.error.message
        || "Preference changed elsewhere; resize was not saved.")
    else root.mutationFeedback = ""
    root.scheduleRefresh()
    return result
  }

  function resizePreferenceConflict() {
    return root.resizeActive && (
      DockModel.normalizeSetting("sidebarExpandedWidth", root.settings.sidebarExpandedWidth) !== root.resizeRequestedAtStart
      || DockModel.normalizeSetting("sidebarCollapsed", root.settings.sidebarCollapsed) !== root.resizeCollapsedAtStart)
  }

  function refresh() {
    if (!root.initialized) return
    root.registry = SidebarModel.reconcileHandles(root.registry, root.toplevels)
    var next = root.mode === "sidebar" ? SidebarModel.selectScreen(root.screens, root.monitors,
      root.settings.workspaceMonitorOrder || [],
      DockModel.normalizeSetting("sidebarMonitor", root.settings.sidebarMonitor),
      root.selectedConnector, root.interactionBusy) : null
    if (next !== root.selectedScreen) {
      root.cancelResize("host-changed")
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
    if (root.resizeActive) root.cancelResize("collapse")
    if (root.interactionBusy) return {ok:false,error:{code:"E_BUSY",message:"Finish the active interaction."},data:{applied:false}}
    var expected = root.collapsed
    var intent = root.hostIntent("sidebarCollapsed", !root.collapsed, expected)
    var reply = intent.reply
    root.mutationFeedback = intent.accepted ? "" : String(reply && reply.error && reply.error.message || "Preference was not accepted.")
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

  onSettingsChanged: {
    if (root.resizePreferenceConflict()) root.cancelResize("preference-conflict")
    root.scheduleRefresh()
  }
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
