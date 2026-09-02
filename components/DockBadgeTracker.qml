pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import "DockBadgeModel.js" as BadgeModel

Item {
  id: root

  // Omarchy injects this service through Overlay.qml. Standalone mode leaves
  // it null; the SNI and Hyprland sources remain fully functional.
  property var notificationService: null
  // Aliases are deliberately explicit. Badge identity never uses substring,
  // punctuation-stripping, web-app URL, or other fuzzy matching.
  property var identityAliases: ({})
  property int revision: 0
  property double focusStartedAt: 0

  readonly property var applications: DesktopEntries.applications.values || []
  readonly property var trayItems: SystemTray.items.values || []
  readonly property var hyprToplevels: Hyprland.toplevels
    ? Hyprland.toplevels.values || [] : []

  visible: false
  width: 0
  height: 0

  // PersistentProperties survives QML reloads inside this process. There is
  // intentionally no FileView or other disk persistence for attention state.
  PersistentProperties {
    id: persisted

    reloadableId: "smartdock-attention-badges"
    property var localNotifications: ({})
  }

  function bumpRevision() {
    revision++
  }

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
    // A notification may arrive while its application is already focused.
    // Start a fresh dwell only when local state actually changed, so the new
    // attention clears after ~800ms of continuous focus instead of lingering
    // until the next focus transition. Popup dismissal itself is not a read.
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
    for (var i = 0; i < hyprToplevels.length; ++i) {
      var handle = hyprToplevels[i]
      if (!handle || handle.urgent !== true) continue
      var ipc = handle.lastIpcObject || ({})
      var wayland = handle.wayland || null
      if (BadgeModel.strictIdentityMatches(desktopId, entry, [
          wayland ? wayland.appId : "",
          ipc.class,
          ipc.initialClass
        ], identityAliases)) return true
    }
    return false
  }

  function badgeFor(desktopId) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications,
      desktopId,
      entry,
      identityAliases,
      Date.now(),
      BadgeModel.LOCAL_ATTENTION_TTL_MS)
    return BadgeModel.badgeSeverity(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry),
      local)
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
    restartFocusDwell()
  }

  onNotificationServiceChanged: Qt.callLater(captureNotifications)
  onApplicationsChanged: {
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
      if ([
          "urgent",
          "activewindow",
          "activewindowv2",
          "openwindow",
          "closewindow"
        ].indexOf(name) < 0) return
      Hyprland.refreshToplevels()
      root.bumpRevision()
    }
  }

  Connections {
    target: Hyprland.toplevels
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.bumpRevision()
    }
  }

  Connections {
    target: SystemTray.items
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.bumpRevision()
    }
  }

  Connections {
    target: root.notificationService && root.notificationService.popupModel
      ? root.notificationService.popupModel : null
    ignoreUnknownSignals: true

    function onCountChanged() { root.captureNotifications() }
    function onDataChanged() { root.captureNotifications() }
    function onRowsInserted() { root.captureNotifications() }
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

        function onUrgentChanged() { root.bumpRevision() }
        function onLastIpcObjectChanged() { root.bumpRevision() }
        function onWaylandHandleChanged() { root.bumpRevision() }
      }
    }
  }
}
