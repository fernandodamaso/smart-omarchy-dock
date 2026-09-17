import QtQuick
import "DockModel.js" as DockModel
import "DockWindowModel.js" as WindowModel
import "DockDesktopModel.js" as DesktopModel
import "DockSidebarModel.js" as SidebarModel
import "DockSidebarInteractionModel.js" as InteractionModel
import "DockSidebarWidgetModel.js" as SidebarWidgetModel

// Host-owned session/view state. All compositor data and action/writer services
// are injected. Widget leases belong to this host session, never to a view.
// This object adds no compositor watcher, notification daemon or config writer.
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
  readonly property var windowActions: host ? host.windowActions || null : null
  property var dragSession: null
  property var dragTarget: null
  property var focusReturnTarget: null
  readonly property bool rowDragActive: dragSession !== null
  property bool interactionBusy: false
  property bool refreshPending: false
  property bool initialized: false
  property var selectedScreen: null
  readonly property string selectedConnector: selectedScreen ? selectedScreen.name : ""
  readonly property string mode: DockModel.normalizeSetting("presentationMode", settings.presentationMode)
  readonly property string edge: DockModel.normalizeSetting("sidebarEdge", settings.sidebarEdge)
  readonly property string preferredConnector: DockModel.normalizeSetting("sidebarMonitor", settings.sidebarMonitor)
  readonly property bool collapsed: DockModel.normalizeSetting("sidebarCollapsed", settings.sidebarCollapsed)
  readonly property var persistentGeometry: SidebarModel.screenGeometry(selectedScreen,
    settings.sidebarExpandedWidth, collapsed)
property bool resizeActive: false
  property real resizeStartGlobalX: 0
  property int resizeStartWidth: 0
  property int resizePreviewWidth: 0
  property var resizeExpectedWidthAtStart: undefined
  property var resizeExpectedCollapseAtStart: undefined
  property string resizeEdgeAtStart: "left"
  property string resizeConnectorAtStart: ""
  readonly property var geometry: resizeActive
    ? SidebarModel.screenGeometry(selectedScreen, resizePreviewWidth, false)
    : persistentGeometry
  // Source-registered factories only. Tests inject a registry here, never through
  // settings/CLI. Production DockHost supplies its own (initially empty) registry.
  property var widgetRegistry: ({})
  property var widgetManager: null
  property var widgetIds: []
  property int widgetRevision: 0
  property string widgetPopupId: ""
  property Item widgetPopupAnchor: null
  readonly property bool widgetWorkActive: mode === "sidebar" && selectedScreen !== null && geometry.mapped
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
  signal widgetAnchorChanged()

  function widgetView(id) {
    var revision = root.widgetRevision
    return root.widgetManager ? root.widgetManager.view(id) : null
  }

  function widgetsChanged() {
    if (!root.initialized || !root.widgetManager) return
    var ids = root.widgetManager.ids()
    // Snapshot updates must not reset the delegate model or popup anchor.
    if (JSON.stringify(ids) !== JSON.stringify(root.widgetIds)) root.widgetIds = ids
    root.widgetRevision = (root.widgetRevision + 1) % 1000000000
    if (!root.widgetPopupId) return
    var view = root.widgetManager.view(root.widgetPopupId)
    if (!ids.length || root.widgetPopupId !== "*" && (!view || !view.registered || !view.available))
      root.closeWidgetPopup()
  }

  function syncWidgets() {
    if (!root.initialized || !root.widgetManager) return
    root.widgetManager.reconcile(root.settings.sidebarWidgets, root.widgetRegistry,
      root.widgetWorkActive, root)
    root.widgetsChanged()
  }

  function openWidgetPopup(id, anchor) {
    if (!root.widgetWorkActive || !anchor || !anchor.visible || !root.widgetIds.length) return false
    var view = root.widgetView(id)
    // Unknown imported IDs may display their unavailable status in overflow, but
    // they cannot execute a factory or open a provider popup.
    if (id !== "*" && (!view || !view.registered || !view.available)) return false
    root.widgetPopupAnchor = anchor
    root.widgetPopupId = id
    root.widgetAnchorChanged()
    return true
  }

  function closeWidgetPopup() {
    root.widgetPopupId = ""
    root.widgetPopupAnchor = null
  }

  function widgetViewFailed(id, expected) {
    if (root.widgetManager) root.widgetManager.viewFailed(id, expected)
  }

  Connections {
    target: root.widgetPopupAnchor
    ignoreUnknownSignals: true
    function onDestroyed() { root.closeWidgetPopup() }
    function onVisibleChanged() { if (!root.widgetPopupAnchor || !root.widgetPopupAnchor.visible) root.closeWidgetPopup() }
    function onXChanged() { root.widgetAnchorChanged() }
    function onYChanged() { root.widgetAnchorChanged() }
    function onWidthChanged() { root.widgetAnchorChanged() }
    function onHeightChanged() { root.widgetAnchorChanged() }
  }
  onWidgetPopupAnchorChanged: if (!root.widgetPopupAnchor) root.closeWidgetPopup()
  onWidgetRegistryChanged: root.syncWidgets()
  onWidgetWorkActiveChanged: root.syncWidgets()
  onCollapsedChanged: root.closeWidgetPopup()
  onSurfaceInvalidated: root.closeWidgetPopup()

  function scheduleRefresh() {
    if (initialized) Qt.callLater(root.refresh)
  }

  function clearResizeState() {
    root.resizeActive = false
    root.resizeStartGlobalX = 0
    root.resizeStartWidth = 0
    root.resizePreviewWidth = 0
    root.resizeExpectedWidthAtStart = undefined
    root.resizeExpectedCollapseAtStart = undefined
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
    root.cancelRowDrag("surface-invalidated")
    root.focusReturnTarget = null
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
    // Capture the exact host values for the stale check. Effective geometry may
    // normalize compatible legacy bytes, but that must not manufacture a conflict.
    root.resizeExpectedWidthAtStart = root.settings.sidebarExpandedWidth
    root.resizeExpectedCollapseAtStart = root.settings.sidebarCollapsed
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
    var expected = root.resizeExpectedWidthAtStart
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
      root.settings.sidebarExpandedWidth !== root.resizeExpectedWidthAtStart
      || root.settings.sidebarCollapsed !== root.resizeExpectedCollapseAtStart)
  }

  function refresh() {
    if (!root.initialized) return
    if (root.dragSession && !root.rowDragIsCurrent()) root.cancelRowDrag("source-or-topology-changed")
    root.registry = SidebarModel.reconcileHandles(root.registry, root.toplevels)
    var next = root.mode === "sidebar" ? SidebarModel.selectScreen(root.screens, root.monitors,
      root.settings.workspaceMonitorOrder || [], root.preferredConnector,
      root.selectedConnector, root.interactionBusy) : null
    if (next !== root.selectedScreen) {
      root.cancelRowDrag("host-changed")
      root.cancelResize("host-changed")
      root.surfaceInvalidated()
      root.interactionBusy = false
      root.selectedScreen = next
    }
    root.syncWidgets()
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


  // Captured on pointer press/menu open, not looked up by title/index on release.
  function captureTarget(key) {
    var row = root.rowsByKey[key]
    if (!row || !root.windowActions) return null
    var target = {key:row.key, kind:row.kind, desktopId:row.desktopId || "",
      workspaceIdentity:row.workspaceIdentity || "", monitorIdentity:row.monitorIdentity || ""}
    if (row.kind === "window") {
      var entry = SidebarModel.handleEntry(root.registry, row.toplevel)
      if (!entry || entry.key !== key || !root.windowActions.isAlive(row.toplevel)) return null
      target.toplevel = row.toplevel
      target.address = String(root.windowActions.addressFor(row.toplevel) || "")
    } else if (row.kind === "workspace") {
      var destination = root.windowActions.resolveWorkspaceDropTarget(target.workspaceIdentity)
      if (!destination) return null
      target.monitorIdentity = destination.monitor
    } else if (row.kind !== "application" && row.kind !== "launcher") return null
    return target
  }

  function targetIsCurrent(target) {
    if (!target || !root.windowActions || root.mode !== "sidebar") return false
    var row = root.rowsByKey[target.key]
    if (target.desktopId && DockModel.normalizeSetting("hiddenApplications", root.settings.hiddenApplications)
        .map(DockModel.normalizedId).indexOf(DockModel.normalizedId(target.desktopId)) >= 0) return false
    if (!row || row.kind !== target.kind) return false
    if (target.kind === "window") {
      var entry = SidebarModel.handleEntry(root.registry, target.toplevel)
      return !!entry && entry.key === target.key && row.toplevel === target.toplevel
        && root.windowActions.isAlive(target.toplevel)
        && String(root.windowActions.addressFor(target.toplevel) || "") === target.address
    }
    if (target.kind === "workspace") {
      var current = root.windowActions.resolveWorkspaceDropTarget(target.workspaceIdentity)
      return !!current && current.monitor === target.monitorIdentity
        && row.workspaceIdentity === target.workspaceIdentity
    }
    return row.desktopId === target.desktopId
  }

  function activateTarget(target, control, clickedConnector) {
    if (root.interactionBusy || !root.targetIsCurrent(target)) return false
    var accepted = false
    if (target.kind === "window") {
      // FDM-954's deliberate Ctrl route. Missing/untrusted modifier state cannot
      // authorize a move; no frozen workspace override and no focus-derived monitor.
      var monitor = control === true ? String(clickedConnector || "") : ""
      if (control === true && (!monitor || monitor !== root.selectedConnector)) return false
      if (control === true) {
        monitor = root.windowActions.canonicalMonitorIdentity(monitor)
        if (!monitor) return false
      }
      accepted = root.windowActions.activateToplevel(target.toplevel, true, monitor, true)
    } else if (target.kind === "workspace") {
      accepted = root.windowActions.focusWorkspaceInPlace(target.workspaceIdentity)
    } else if (target.kind === "application") {
      return root.toggleApplication(target.key)
    } else if (target.kind === "launcher") {
      var row = root.rowsByKey[target.key]
      var entry = row.item ? row.item.entry : null
      if (entry && typeof entry.execute === "function") { entry.execute(); accepted = true }
    }
    if (accepted) root.focusReturnTarget = null
    return accepted
  }

  function rememberNavigationFocus() {
    if (root.focusReturnTarget || !root.windowActions) return
    var active = root.windowActions.activeToplevel
    if (root.windowActions.isAlive(active)) root.focusReturnTarget = {
      toplevel:active, address:String(root.windowActions.addressFor(active) || "")}
  }

  function releaseNavigationFocus() {
    var target = root.focusReturnTarget
    root.focusReturnTarget = null
    if (!target || !root.windowActions || !root.windowActions.isAlive(target.toplevel)
        || String(root.windowActions.addressFor(target.toplevel) || "") !== target.address) return false
    return root.windowActions.activateToplevel(target.toplevel, true, "", true)
  }

  function topologyStamp() {
    return JSON.stringify((root.monitors || []).map(function(m) {
      var ipc = m.lastIpcObject || m
      return [ipc.id, ipc.name, ipc.x, ipc.y, ipc.width, ipc.height, ipc.scale]
    }).concat((root.screens || []).map(function(s) {
      return [s.name, s.x, s.y, s.width, s.height]
    })))
  }

  function dragSourceLocation(target) {
    if (!root.targetIsCurrent(target)) return null
    if (target.kind === "workspace")
      return root.windowActions.resolveWorkspaceDropTarget(target.workspaceIdentity)
    if (target.kind !== "window" || !target.address) return null
    var location = root.windowActions.workspaceMoveLocation(target.toplevel, target.address)
    if (!location) return null
    var identity = root.windowActions.canonicalWorkspaceIdentity(location.workspace)
    var owner = root.windowActions.resolveWorkspaceDropTarget(identity)
    if (!owner) return null
    return {identity:identity, monitor:owner.monitor, minimized:location.minimized === true}
  }

  function beginRowDrag(target) {
    if (root.interactionBusy || root.resizeActive || root.dragSession) return false
    var location = root.dragSourceLocation(target)
    if (!location || !root.selectedConnector) return false
    root.dragSession = {target:target, location:location, connector:root.selectedConnector,
      topology:root.topologyStamp()}
    root.dragTarget = null
    root.interactionBusy = true
    return true
  }

  function rowDragIsCurrent() {
    var session = root.dragSession
    if (!session || session.connector !== root.selectedConnector
        || session.topology !== root.topologyStamp()) return false
    var current = root.dragSourceLocation(session.target)
    return !!current && current.identity === session.location.identity
      && current.monitor === session.location.monitor
      && current.minimized === session.location.minimized
  }

  function dragDestination(key) {
    var session = root.dragSession
    var row = root.rowsByKey[key]
    if (!session || !row || !root.rowDragIsCurrent()) return null
    if (session.target.kind === "workspace") {
      if (row.kind !== "monitor" || !row.monitorIdentity) return null
      var monitor = root.windowActions.canonicalMonitorIdentity(row.connector || row.monitorIdentity)
      if (!monitor || !root.windowActions.canMoveWorkspaceToMonitor(
          session.location.identity, monitor)) return null
      return {key:key, identity:session.location.identity, monitor:monitor}
    }
    if (["workspace", "application", "window"].indexOf(row.kind) < 0
        || !row.workspaceIdentity) return null
    if (row.kind === "window" && root.windowActions.reliableWorkspaceForToplevel(row.toplevel)
        !== row.workspaceIdentity) return null
    var destination = root.windowActions.resolveWorkspaceDropTarget(row.workspaceIdentity)
    if (!destination || !root.windowActions.workspaceMoveWouldChange(
        [session.target], destination.identity)) return null
    return {key:key, identity:destination.identity, monitor:destination.monitor}
  }

  function updateRowDrag(key) {
    if (!root.rowDragIsCurrent()) { root.cancelRowDrag("stale-source"); return false }
    root.dragTarget = root.dragDestination(key)
    return root.dragTarget !== null
  }

  function cancelRowDrag(reason) {
    if (!root.dragSession) return false
    root.dragSession = null
    root.dragTarget = null
    root.interactionBusy = false
    root.scheduleRefresh()
    return true
  }

  function finishRowDrag(key) {
    if (!root.dragSession) return false
    var session = root.dragSession
    var hovered = root.dragTarget
    var destination = root.dragDestination(key)
    if (destination && hovered && hovered.key === key
        && (hovered.identity !== destination.identity || hovered.monitor !== destination.monitor))
      destination = null
    // Clear state before dispatch; a synchronous host refresh cannot commit twice.
    root.cancelRowDrag("release")
    if (!destination) return false
    if (session.target.kind === "workspace")
      return root.windowActions.moveWorkspaceToMonitor(session.location.identity, destination.monitor)
    return root.windowActions.moveCapturedToplevels([session.target], destination.identity)
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
    var intent = root.hostIntent("sidebarCollapsed", !root.collapsed, root.settings.sidebarCollapsed)
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
    root.syncWidgets()
    root.scheduleRefresh()
  }
  onModeChanged: root.invalidateSurface()
  onEdgeChanged: root.invalidateSurface()
  onCollapsedChanged: root.invalidateSurface()
  onPreferredConnectorChanged: root.invalidateSurface()
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
  Component.onCompleted: {
    root.widgetManager = SidebarWidgetModel.createManager(function() { root.widgetsChanged() })
    root.initialized = true
    root.refresh()
  }
  Component.onDestruction: {
    root.initialized = false
    root.closeWidgetPopup()
    if (root.widgetManager) root.widgetManager.dispose()
  }
}
