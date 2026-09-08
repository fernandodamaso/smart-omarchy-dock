pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import "DockBadgeModel.js" as BadgeModel
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel

Item {
  id: root

  property var notificationService: null
  property var launcherBadgeService: null
  property string launcherBadgeMode: BadgeModel.BADGE_COUNT_MODE_AUTOMATIC
  property var identityAliases: ({})
  property int revision: 0
  property double focusStartedAt: 0
  property var urgentStates: ({})
  property var urgentMotionStates: ({})

  readonly property var applications: DesktopEntries.applications.values || []
  readonly property var trayItems: SystemTray.items.values || []
  readonly property var hyprToplevels: Hyprland.toplevels
    ? Hyprland.toplevels.values || [] : []

  visible: false
  width: 0
  height: 0

  PersistentProperties {
    id: persisted
    reloadableId: "smartdock-attention-badges"
    property var localNotifications: ({})
  }

  function bumpRevision() { revision++ }

  function replaceLocalNotifications(next) {
    if (JSON.stringify(next) === JSON.stringify(persisted.localNotifications))
      return false
    persisted.localNotifications = next
    bumpRevision()
    return true
  }

  function captureNotifications() {
    var service = notificationService
    var model = service && service.popupModel ? service.popupModel : null
    if (!model || typeof model.get !== "function") return
    var next = persisted.localNotifications || ({})
    var now = Date.now()
    for (var i = 0; i < Number(model.count || 0); ++i) {
      var row = model.get(i)
      if (!row) continue
      next = BadgeModel.upsertNotification(
        next, row, NotificationUrgency.Critical, now)
    }
    if (replaceLocalNotifications(next)) restartFocusDwell()
  }

  function pruneExpiredLocal() {
    replaceLocalNotifications(BadgeModel.pruneExpired(
      persisted.localNotifications, Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS))
  }

  function sniNeedsAttentionFor(desktopId, entry) {
    for (var i = 0; i < trayItems.length; ++i) {
      var item = trayItems[i]
      if (!item || item.status !== Status.NeedsAttention) continue
      if (BadgeModel.strictIdentityMatches(desktopId, entry, [
          item.id, item.title, item.tooltipTitle
        ], identityAliases)) return true
    }
    return false
  }

  function hyprUrgentFor(desktopId, entry) {
    return urgentAddressesFor(desktopId, entry).length > 0
  }

  function urgentAddressesFor(desktopId, entry) {
    var addresses = []
    for (var i = 0; i < hyprToplevels.length; ++i) {
      var handle = hyprToplevels[i]
      if (!DockWindowModel.handleUrgent(handle)) continue
      var ipc = handle.lastIpcObject || ({})
      var wayland = handle.wayland || null
      if (!BadgeModel.strictIdentityMatches(desktopId, entry, [
          wayland ? wayland.appId : "",
          ipc.class,
          ipc.initialClass
        ], identityAliases)) continue
      var address = DockModel.normalizeWindowAddress(handle.address || ipc.address)
      if (address && addresses.indexOf(address) < 0) addresses.push(address)
    }
    return addresses
  }

  function ensureUrgentState(desktopId) {
    var key = BadgeModel.normalizeIdentity(desktopId)
    if (!key || urgentStates[key]) return
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var next = BadgeModel.copyRecords(urgentStates)
    next[key] = BadgeModel.reduceWindowUrgencyState(
      null, urgentAddressesFor(desktopId, entry), false, true)
    urgentStates = next
    bumpRevision()
  }

  function reconcileUrgentStates() {
    var identities = {}
    for (var i = 0; i < applications.length; ++i) {
      var entry = applications[i]
      var key = BadgeModel.normalizeIdentity(entry ? entry.id : "")
      if (key) identities[key] = entry.id
    }
    for (var existingKey in urgentStates) {
      if (existingKey.indexOf("workspace:") === 0) continue
      if (identities[existingKey] === undefined) identities[existingKey] = existingKey
    }

    var next = BadgeModel.copyRecords(urgentStates)
    for (var key in identities) {
      var desktopId = identities[key]
      var entryForId = BadgeModel.entryForDesktopId(desktopId, applications)
      var previous = urgentStates[key]
      next[key] = BadgeModel.reduceWindowUrgencyState(
        previous,
        urgentAddressesFor(desktopId, entryForId),
        false,
        !previous)
    }
    if (JSON.stringify(next) === JSON.stringify(urgentStates)) return
    urgentStates = next
    bumpRevision()
  }

  function workspaceScopeKey(owner, presentationId) {
    return "workspace:" + JSON.stringify([String(owner), String(presentationId)])
  }

  function syncWorkspaceScopes(owner, items) {
    var prefix = "workspace:" + JSON.stringify([String(owner)]).slice(0, -1) + ","
    var next = BadgeModel.copyRecords(urgentStates)
    var motion = BadgeModel.copyRecords(urgentMotionStates)
    var retained = {}
    for (var i = 0; i < items.length; ++i) {
      var item = items[i]
      var key = workspaceScopeKey(owner, item.presentationId)
      retained[key] = true
      next[key] = BadgeModel.reduceWindowUrgencyState(
        next[key], item.urgentAddresses, true, !next[key])
      if (!motion[key]) motion[key] = BadgeModel.primeUrgentMotionState(
        null, next[key].windowUrgentRevision)
    }
    for (var key in next) {
      if (key.indexOf(prefix) === 0 && !retained[key]) {
        delete next[key]
        delete motion[key]
      }
    }
    if (JSON.stringify(motion) !== JSON.stringify(urgentMotionStates))
      urgentMotionStates = motion
    if (JSON.stringify(next) === JSON.stringify(urgentStates)) return
    urgentStates = next
    bumpRevision()
  }

  function urgentStateFor(desktopId, primaryOwner, scopeKey) {
    var stateRevision = revision
    var key = scopeKey || BadgeModel.normalizeIdentity(desktopId)
    var state = urgentStates[key]
    if (!state) {
      var entry = BadgeModel.entryForDesktopId(desktopId, applications)
      state = BadgeModel.reduceWindowUrgencyState(
        null, scopeKey ? [] : urgentAddressesFor(desktopId, entry), primaryOwner, true)
    }
    return {
      windowUrgent: state.windowUrgent === true,
      primaryOwner: primaryOwner === true,
      windowUrgentRevision: Number(state.windowUrgentRevision || 0)
    }
  }

  function primeUrgentMotion(desktopId, urgentRevision, scopeKey) {
    var key = scopeKey || BadgeModel.normalizeIdentity(desktopId)
    if (!key || (scopeKey && (!urgentStates[key] || urgentMotionStates[key]))) return
    var next = BadgeModel.copyRecords(urgentMotionStates)
    next[key] = BadgeModel.primeUrgentMotionState(
      urgentMotionStates[key], urgentRevision)
    urgentMotionStates = next
  }

  function requestUrgentMotion(desktopId, input, scopeKey) {
    var key = scopeKey || BadgeModel.normalizeIdentity(desktopId)
    if (!key || (scopeKey && !urgentStates[key])) return false
    var reduced = BadgeModel.reduceUrgentMotion(urgentMotionStates[key], input)
    var next = BadgeModel.copyRecords(urgentMotionStates)
    next[key] = reduced.state
    urgentMotionStates = next
    return reduced.play === true
  }

  function launcherCountFor(desktopId) {
    var service = launcherBadgeService
    var providerRevision = service ? Number(service.revision || 0) : 0
    var counts = service && service.counts ? service.counts : ({})
    return BadgeModel.launcherCountState(
      counts, desktopId, !!(service && service.available))
  }

  function motionAttentionFor(desktopId, scope) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    return BadgeModel.motionAttentionEligible(
      (!scope || scope.primaryOwner === true) && sniNeedsAttentionFor(desktopId, entry),
      scope ? scope.localUrgent === true : hyprUrgentFor(desktopId, entry),
      !scope || scope.primaryOwner === true ? local : BadgeModel.BADGE_NONE)
  }

  function badgeFor(desktopId, scope) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    var severity = BadgeModel.scopedBadgeSeverity(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry), local, scope)
    return BadgeModel.applicationBadgeToken(
      true, launcherBadgeMode, !scope || scope.primaryOwner === true
        ? launcherCountFor(desktopId) : null, severity)
  }

  function focusedEntry() {
    var active = ToplevelManager.activeToplevel
    if (!active) return null
    return BadgeModel.entryForStrictSource(
      [active.appId], applications, identityAliases)
  }

  function restartFocusDwell() {
    focusDwell.stop()
    focusStartedAt = 0
    if (!ToplevelManager.activeToplevel) return
    focusStartedAt = Date.now()
    focusDwell.start()
  }

  function clearFocusedLocal() {
    if (!BadgeModel.shouldClearFocused(
        focusStartedAt, Date.now(), BadgeModel.FOCUS_DWELL_MS)) return
    var entry = focusedEntry()
    if (!entry) return
    replaceLocalNotifications(BadgeModel.clearMatchingNotifications(
      persisted.localNotifications, entry.id, entry, identityAliases))
  }

  Component.onCompleted: {
    captureNotifications()
    pruneExpiredLocal()
    reconcileUrgentStates()
    restartFocusDwell()
  }

  onNotificationServiceChanged: Qt.callLater(captureNotifications)
  onLauncherBadgeServiceChanged: bumpRevision()
  onLauncherBadgeModeChanged: bumpRevision()
  onApplicationsChanged: {
    reconcileUrgentStates()
    bumpRevision()
    restartFocusDwell()
  }

  Timer {
    id: focusDwell
    interval: BadgeModel.FOCUS_DWELL_MS
    repeat: false
    onTriggered: root.clearFocusedLocal()
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.pruneExpiredLocal()
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      root.bumpRevision()
      root.restartFocusDwell()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event ? event.name : "")
      if (["urgent", "activewindow", "activewindowv2", "openwindow", "closewindow"]
          .indexOf(name) < 0) return
      Hyprland.refreshToplevels()
      Qt.callLater(root.reconcileUrgentStates)
      root.bumpRevision()
    }
  }

  Connections {
    target: Hyprland.toplevels
    ignoreUnknownSignals: true
    function onValuesChanged() {
      root.reconcileUrgentStates()
      root.bumpRevision()
    }
  }

  Connections {
    target: SystemTray.items
    ignoreUnknownSignals: true
    function onValuesChanged() { root.bumpRevision() }
  }

  Connections {
    target: root.notificationService && root.notificationService.popupModel
      ? root.notificationService.popupModel : null
    ignoreUnknownSignals: true
    function onCountChanged() { root.captureNotifications() }
    function onDataChanged() { root.captureNotifications() }
    function onRowsInserted() { root.captureNotifications() }
  }

  Connections {
    target: root.launcherBadgeService
    ignoreUnknownSignals: true
    function onRevisionChanged() { root.bumpRevision() }
    function onAvailableChanged() { root.bumpRevision() }
    function onCountsChanged() { root.bumpRevision() }
  }

  Repeater {
    model: root.trayItems
    delegate: Item {
      required property var modelData
      visible: false
      width: 0
      height: 0
      Connections {
        target: modelData
        ignoreUnknownSignals: true
        function onStatusChanged() { root.bumpRevision() }
        function onIdChanged() { root.bumpRevision() }
        function onTitleChanged() { root.bumpRevision() }
        function onTooltipTitleChanged() { root.bumpRevision() }
      }
    }
  }

  Repeater {
    model: root.hyprToplevels
    delegate: Item {
      required property var modelData
      visible: false
      width: 0
      height: 0
      Connections {
        target: modelData
        ignoreUnknownSignals: true
        function onUrgentChanged() {
          root.reconcileUrgentStates()
          root.bumpRevision()
        }
        function onLastIpcObjectChanged() {
          root.reconcileUrgentStates()
          root.bumpRevision()
        }
        function onWaylandHandleChanged() {
          root.reconcileUrgentStates()
          root.bumpRevision()
        }
      }
    }
  }
}
