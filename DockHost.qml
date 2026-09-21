pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "components/DockModel.js" as DockModel
import "components/DockWindowModel.js" as DockWindowModel
import "components/DockTrashModel.js" as TrashModel
import "components/DockConfigModel.js" as ConfigModel

Item {
  id: root

  required property string configPath
  required property string runtimeMode
  property var notificationService: null
  property var launcherBadgeService: null
  property var browserProfileService: null
  property var herdrService: null
  readonly property var applications: DesktopEntries.applications.values || []
  property int iconReloadRevision: 0
  readonly property var connectedScreens: Quickshell.screens
  readonly property var hyprMonitors: Hyprland.monitors ? Hyprland.monitors.values || [] : []
  readonly property var hyprWorkspaces: Hyprland.workspaces ? Hyprland.workspaces.values || [] : []
  readonly property var desktopToplevels: ToplevelManager.toplevels.values || []
  readonly property var hyprToplevels: Hyprland.toplevels ? Hyprland.toplevels.values || [] : []
  // Branch-only synthetic Widget fixtures are combined with internal source-owned
  // providers. Neither accepts commands, paths, or credentials from settings.
  readonly property var sidebarWidgetRegistry: {
    var registry = {}
    var demoDescriptors = demoWidgetRegistry.descriptors
    Object.keys(demoDescriptors).forEach(function(widgetId) {
      registry[widgetId] = demoDescriptors[widgetId]
    })
    if (root.herdrService) {
      registry["herdr.agents"] = {
        id: "herdr.agents",
        label: "Coding agents",
        available: root.herdrService.available !== false,
        revision: 1,
        acquire: function(owner) { return root.herdrService.acquire(owner) },
        expandedView: herdrExpandedView,
        compactView: herdrCompactView,
        popupView: herdrPopupView
      }
    }
    return registry
  }
  readonly property var sidebarController: sidebarState
  readonly property var sidebarPanels: rendererMode === "sidebar" && presentationLoader.item
    ? presentationLoader.item.panels : []
  // Primary surface for harnesses that still expect a single panel reference.
  readonly property var sidebarPanel: sidebarPanels.length ? sidebarPanels[0] : null
  property bool rendererInitialized: false
  property bool rendererReady: false
  property string rendererMode: "classic"
  property string rendererEdge: "left"
  property var rendererScreen: null

  function syncRenderer() {
    if (!root.rendererInitialized) return
    var mode = DockModel.normalizeSetting("presentationMode", root.settings.presentationMode)
    var edge = mode === "sidebar" ? DockModel.normalizeSetting("sidebarEdge", root.settings.sidebarEdge) : "left"
    // Mode/edge recreate the Loader. Screen membership is owned by Variants over
    // mappedScreens and must not tear every panel down on hotplug or preference.
    if (mode !== root.rendererMode || edge !== root.rendererEdge) {
      // Synchronous Loader teardown precedes deferred creation of the new branch.
      // The old Dock/Sidebar owns its popup, drag and badge-scope destruction.
      root.rendererReady = false
      root.rendererMode = mode
      root.rendererEdge = edge
    }
    root.rendererScreen = mode === "sidebar" ? sidebarState.selectedScreen : null
    Qt.callLater(root.activateRenderer)
  }

  function activateRenderer() {
    var mode = DockModel.normalizeSetting("presentationMode", root.settings.presentationMode)
    var edge = mode === "sidebar" ? DockModel.normalizeSetting("sidebarEdge", root.settings.sidebarEdge) : "left"
    if (mode !== root.rendererMode || edge !== root.rendererEdge) {
      root.syncRenderer()
      return
    }
    root.rendererScreen = mode === "sidebar" ? sidebarState.selectedScreen : null
    root.rendererReady = mode === "classic"
      || (sidebarState.mappedScreens && sidebarState.mappedScreens.length > 0)
  }

  onSettingsChanged: if (rendererInitialized) Qt.callLater(root.syncRenderer)

  property int trashItemCount: 0
  property bool trashStateKnown: false
  property bool settingsLoaded: false
  property bool showTrashSetting: true
  property string settingsLoadState: "missing"
  property string settingsLoadError: ""
  property int settingsRevision: 0
  property bool settingsDefaultsInUse: true
  property bool settingsPersisted: false
  property string settingsWriteState: "idle"
  property string settingsWriteError: ""
  property bool settingsReloadPending: false
  property string settingsLoadedText: ""
  property string settingsWriteBaseText: ""
  property string settingsWriteText: ""
  property var workspaceWindowCounts: ({})
  property bool workspaceCountsReady: false
  property int workspaceCountsRevision: 0
  property bool workspaceCountsRefreshPending: false
  property int scopeRevision: scopeRefreshController.revision
  readonly property var windowActions: windowActionsController
  readonly property var workspaceMonitorDrag: workspaceMonitorDragController
  readonly property var badgeTracker: badgeTrackerController
  readonly property bool showTrash: showTrashSetting

  // Shared with the read-only CLI metadata; defaults are never persisted merely
  // by discovery or by loading a host whose user configuration does not exist.
  property var settings: dockControl.defaults

  function loadSettings(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
          || !Array.isArray(parsed.pinned))
        throw new Error("Configuration must be an object with a 'pinned' array")
      var requested = Object.create(null)
      Object.keys(dockControl.defaults).forEach(function(key) {
        requested[key] = dockControl.defaults[key]
      })
      Object.keys(parsed).forEach(function(key) { requested[key] = parsed[key] })
      showTrashSetting = TrashModel.normalizeShowTrash(parsed.showTrash)
      if (ConfigModel.iconsChanged(settings.iconOverrides, requested.iconOverrides)) iconReloadRevision++
      if (JSON.stringify(settings) !== JSON.stringify(requested)) settingsRevision++
      settings = requested
      settingsLoadState = "loaded"
      settingsLoadError = ""
      settingsLoadedText = raw
      settingsDefaultsInUse = false
      settingsPersisted = true
      settingsWriteState = "idle"
      settingsWriteError = ""
    } catch (error) {
      settingsLoadState = "invalid"
      settingsLoadError = String(error)
      settingsPersisted = false
      console.warn("Dock: could not load " + configPath + ":", error)
    }
    settingsLoaded = true
    if (showTrash) Qt.callLater(root.refreshTrash)
  }

  function reorderPinned(sourceDesktopId, targetDesktopId) {
    var pins = Array.isArray(settings.pinned) ? settings.pinned : []
    var sourceKey = ConfigModel.canonicalApplicationId(sourceDesktopId)
    var targetKey = ConfigModel.canonicalApplicationId(targetDesktopId)
    var sourceIndex = ConfigModel.identityIndex(pins, sourceKey)
    var targetIndex = ConfigModel.identityIndex(pins, targetKey)
    if (sourceKey && targetKey && sourceIndex >= 0 && sourceIndex === targetIndex)
      return saveSettings({}, false)
    // A forward drop occupies the target's old slot (after it once removed);
    // a backward drop goes before it. Use the same legacy-preserving primitive
    // as CLI moves instead of revalidating every untouched stored pin.
    var args = { id: sourceDesktopId }
    args[sourceIndex < targetIndex ? "after" : "before"] = targetDesktopId
    return changeApplication("move", args)
  }

  function pinApplication(desktopId) {
    return changeApplication("pin", { id: desktopId })
  }

  function unpinApplication(desktopId) {
    return changeApplication("unpin", { id: desktopId })
  }

  function hideApplication(desktopId) {
    return changeApplication("hide", { id: desktopId })
  }

  function groupWorkspaceApplication(desktopId, workspace) {
    return changeWorkspaceGroup("group", desktopId, workspace)
  }

  function ungroupWorkspaceApplication(desktopId, workspace) {
    return changeWorkspaceGroup("ungroup", desktopId, workspace)
  }

  function changeWorkspaceGroup(action, desktopId, workspace) {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    return commitSettings(ConfigModel.workspaceGroupIntent(
      settings, applications, action,
      { desktopId: desktopId, workspace: workspace }), false)
  }

  function toggleBrowserActivityMute(serviceId) {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    var current = DockModel.normalizeSetting(
      "browserActivityMutedServices", settings.browserActivityMutedServices)
    return saveSetting("browserActivityMutedServices",
      DockModel.toggleBrowserActivityServiceMute(current, serviceId))
  }

  function changeApplication(action, args) {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    return commitSettings(ConfigModel.applicationIntent(settings, applications, action, args), false)
  }

  function iconResult(reply, reloaded) {
    reply.data.iconReloadRevision = iconReloadRevision
    reply.data.reloaded = reloaded
    reply.data.renderVerified = false
    reply.warnings.push("Artwork is referenced in place. Saving or requesting a reload does not verify decoding or rendering.")
    return reply
  }

  function saveIconOverride(desktopId, sourceUrl) {
    var blocked = mutationBlocked()
    if (blocked) return iconResult(blocked, false)
    var source = sourceUrl === "" ? null : sourceUrl
    var result = ConfigModel.iconIntent(settings, desktopId, source)
    var revision = iconReloadRevision
    var reply = commitSettings(result, false)
    // Same-path Apply deliberately reloads bytes, but never creates a redundant
    // config write. Failed persistence still leaves the accepted live intent.
    if (result.ok && source !== null && iconReloadRevision === revision) iconReloadRevision++
    return iconResult(reply, iconReloadRevision !== revision)
  }

  function saveWindowIconOverride(action, args) {
    var blocked = mutationBlocked()
    if (blocked) return iconResult(blocked, false)
    var result = ConfigModel.windowIconIntent(settings, action, args)
    var revision = iconReloadRevision
    var reply = commitSettings(result, false)
    // A same-source set is an explicit byte reload without a redundant settings write.
    if (result.ok && action === "set" && iconReloadRevision === revision) iconReloadRevision++
    return iconResult(reply, iconReloadRevision !== revision)
  }

  function reloadIcon(desktopId) {
    var blocked = mutationBlocked()
    if (blocked) return iconResult(blocked, false)
    var key = ConfigModel.canonicalApplicationId(desktopId)
    var configured = ConfigModel.effectiveIcons(settings.iconOverrides)
    if (!key || !Object.prototype.hasOwnProperty.call(configured, key))
      return iconResult(dockControl.failure("E_VALIDATION", "Reload requires an existing local icon mapping."), false)
    // The retained renderer uses one host revision; other mapped icons can also
    // refresh. No file watch, settings revision or persistence write is involved.
    iconReloadRevision++
    return iconResult(mutationOutcome(dockControl.mutationData(settings, settings, [], false, false)), true)
  }

  function savePinned(pinned) {
    return saveSetting("pinned", pinned)
  }

  function saveSetting(key, value) {
    var patch = Object.create(null)
    patch[key] = value
    return saveSettings(patch, false)
  }

  // Gesture-owned preferences need one small adapter around the sole writer.
  // It distinguishes a rejected preflight/stale intent from a live intent that
  // was accepted but whose async FileView persistence is still pending.
  function saveSettingIntent(key, value, expectedValue) {
    var blocked = mutationBlocked()
    if (blocked) return { accepted: false, pending: false, reply: blocked }
    if (settings[key] !== expectedValue) {
      var stale = dockControl.mutationData(settings, settings, [], false, false)
      stale.currentValue = settings[key]
      stale.expectedValue = expectedValue
      return { accepted: false, pending: false,
        reply: dockControl.failure("E_STALE",
          "Preference changed after the interaction started; refresh before retrying.", stale) }
    }
    var reply = saveSetting(key, value)
    var applied = !!(reply && reply.data && reply.data.applied === true)
    var accepted = !!(reply && (reply.ok || applied))
    var pending = accepted && !reply.ok && !!reply.error && reply.error.code === "E_BUSY"
    return { accepted: accepted, pending: pending, reply: reply }
  }

  function mutationBlocked() {
    var data = dockControl.mutationData(settings, settings, [], false, false)
    if (!settingsLoaded || settingsReloadPending || settingsWriteState === "saving")
      return dockControl.failure("E_BUSY", "Settings are loading or saving. Read status before retrying.", data)
    if (settingsLoadState === "invalid")
      return dockControl.failure("E_CONFIG_INVALID", "Repair the invalid existing config externally before changing settings: " + settingsLoadError, data)
    return null
  }

  function mutationOutcome(data) {
    if (settingsWriteState === "error")
      return dockControl.failure("E_PERSISTENCE", settingsWriteError, data)
    if (settingsWriteState === "saving" || settingsReloadPending)
      return dockControl.failure("E_BUSY", "Live intent accepted; save/readback has not completed. Read status before retrying.", data)
    var warnings = data.persisted ? [] : ["Live settings are not confirmed persisted."]
    return dockControl.success(data, warnings)
  }

  function saveSettings(patch, dryRun) {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    return commitSettings(ConfigModel.applyPatch(settings, patch,
      dockControl.validationMetadata()), dryRun)
  }

  // Only validated config/app/icon model results reach this common live commit.
  // IPC never accepts a prevalidated result or a full replacement snapshot.
  function commitSettings(result, dryRun) {
    var before = settings
    if (!result.ok) {
      var rejected = dockControl.mutationData(before, before, [], false, false)
      rejected.validationErrors = result.errors
      return dockControl.failure(result.errorCode || "E_VALIDATION",
        result.errorCode === "E_CONFLICT"
          ? "Window icon rule changed while the edit was open; refresh before retrying."
          : "Patch rejected; no values were changed.", rejected)
    }
    if (dryRun === true)
      return dockControl.success(dockControl.mutationData(before, result.settings, result.changedKeys, true, false),
        ["Dry run only. Theme-owned/token colors and theme-owned border width are unresolved null values."])
    if (result.changedKeys.length === 0)
      return mutationOutcome(dockControl.mutationData(before, before, [], false, false))
    showTrashSetting = TrashModel.normalizeShowTrash(result.settings.showTrash)
    if (ConfigModel.iconsChanged(before.iconOverrides, result.settings.iconOverrides)
        || ConfigModel.windowIconsChanged(before.windowIconOverrides, result.settings.windowIconOverrides))
      iconReloadRevision++
    settings = result.settings
    settingsRevision++
    settingsDefaultsInUse = false
    settingsPersisted = false
    writeSettings()
    return mutationOutcome(dockControl.mutationData(before, settings, result.changedKeys, false, true))
  }

  function retrySettings() {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    if (settingsPersisted)
      return dockControl.success(dockControl.mutationData(settings, settings, [], false, false))
    // Retry persists the complete current snapshot, including later successful
    // intents. It does not replay a stale failed patch or create another revision.
    writeSettings()
    return mutationOutcome(dockControl.mutationData(settings, settings, [], false, true))
  }

  // Retained FDM-881 writer behavior from PR #43 @7473a23: actual saved/error
  // completion, bounded retry bytes and failed-write echo protection. One write
  // path is shared by CLI and existing dock-menu intents.
  function writeSettings() {
    var text = JSON.stringify(settings, null, 2) + "\n"
    settingsWriteBaseText = settingsLoadedText
    if (text === configFile.cachedText) text += "\n"
    settingsWriteText = text
    settingsWriteState = "saving"
    configFile.setText(text)
  }

  function settingsFileLoaded(raw) {
    if (settingsReloadPending) {
      settingsReloadPending = false
      if (settingsWriteState === "error" && raw === settingsWriteBaseText) return
    }
    loadSettings(raw)
  }

  function settingsLoadFailed(error) {
    settingsReloadPending = false
    settingsLoaded = true
    settingsPersisted = false
    settingsLoadState = error === FileViewError.FileNotFound ? "missing" : "invalid"
    settingsLoadError = error === FileViewError.FileNotFound ? "" : FileViewError.toString(error)
    if (showTrash) Qt.callLater(root.refreshTrash)
  }

  function settingsSaved() {
    settingsWriteError = ""
    settingsWriteState = "saved"
    settingsLoadedText = settingsWriteText
    settingsLoadState = "loaded"
    settingsLoadError = ""
    settingsDefaultsInUse = false
    settingsPersisted = true
    reloadSettingsIfPending()
  }

  function settingsSaveFailed(error) {
    settingsWriteError = "Settings changed for this session, but could not be saved. "
      + "Retry before restarting. " + FileViewError.toString(error)
    settingsWriteState = "error"
    settingsPersisted = false
    console.warn("Dock: could not save " + configPath + ":", error)
    reloadSettingsIfPending()
  }

  function reloadSettingsIfPending() {
    if (!settingsReloadPending || settingsWriteState === "saving") return
    Qt.callLater(function() {
      if (root.settingsReloadPending && root.settingsWriteState !== "saving") configFile.reload()
    })
  }

  function refreshTrash() {
    if (!TrashModel.shouldRefresh(showTrash, trashListProcess.running, settingsLoaded)) return
    trashListProcess.running = true
  }

  function refreshWorkspaceCounts() {
    if (workspaceCountsProcess.running) {
      root.workspaceCountsRefreshPending = true
      return
    }
    root.workspaceCountsRefreshPending = false
    workspaceCountsProcess.running = true
  }

  function openTrash() {
    Quickshell.execDetached(["gio", "open", "trash:///"])
  }

  function emptyTrash() {
    if (!trashEmptyProcess.running) trashEmptyProcess.running = true
  }

  DockDemoWidgetRegistry { id: demoWidgetRegistry }

  DockControl {
    id: dockControl
    host: root
  }

  DockScopeRefreshController {
    id: scopeRefreshController
    toplevelModel: Hyprland.toplevels
    monitorModel: Hyprland.monitors
    workspaceModel: Hyprland.workspaces
    refreshSource: Hyprland
  }

  onShowTrashChanged: {
    if (!settingsLoaded || !showTrash) return
    trashStateKnown = false
    Qt.callLater(root.refreshTrash)
  }

  Component.onCompleted: {
    rendererInitialized = true
    Qt.callLater(root.syncRenderer)
    refreshWorkspaceCounts()
    scopeRefreshController.requestRefresh()
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.settingsLoaded && root.showTrash
    onTriggered: root.refreshTrash()
  }

  Timer {
    id: workspaceCountsRefreshTimer
    interval: 100
    repeat: false
    onTriggered: root.refreshWorkspaceCounts()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (DockModel.shouldRefreshWorkspaceState(name)) workspaceCountsRefreshTimer.restart()
      if (DockWindowModel.shouldRefreshWindowScope(name)) scopeRefreshController.requestRefresh()
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      scopeRefreshController.invalidate()
      scopeRefreshController.requestRefresh()
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      workspaceCountsRefreshTimer.restart()
    }
  }

  Process {
    id: workspaceCountsProcess
    command: ["hyprctl", "workspaces", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var counts = DockModel.parseWorkspaceWindowCounts(text)
        if (counts) {
          root.workspaceWindowCounts = counts
          root.workspaceCountsReady = true
          root.workspaceCountsRevision++
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Dock: could not read workspace counts (hyprctl exited " + exitCode + ")")
      if (root.workspaceCountsRefreshPending) Qt.callLater(root.refreshWorkspaceCounts)
    }
  }

  Process {
    id: trashListProcess
    command: ["gio", "trash", "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.trashItemCount = DockModel.trashItemCount(text)
        root.trashStateKnown = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Dock: could not inspect Trash (gio exited " + exitCode + ")")
    }
  }

  Process {
    id: trashEmptyProcess
    command: ["gio", "trash", "--empty"]
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Dock: could not empty Trash (gio exited " + exitCode + ")")
      root.refreshTrash()
    }
  }

  FileView {
    id: configFile
    readonly property string cachedText: text()
    path: root.configPath
    watchChanges: true
    printErrors: false
    blockWrites: true
    atomicWrites: true
    onLoaded: root.settingsFileLoaded(text())
    onLoadFailed: error => root.settingsLoadFailed(error)
    onFileChanged: {
      root.settingsReloadPending = true
      root.reloadSettingsIfPending()
    }
    onSaved: root.settingsSaved()
    onSaveFailed: error => root.settingsSaveFailed(error)
  }

  DockWindowActions {
    id: windowActionsController
    applicationMutationController: root
  }

  DockWorkspaceMonitorDrag {
    id: workspaceMonitorDragController
    windowActions: root.windowActions
  }

  DockBadgeTracker {
    id: badgeTrackerController
    notificationService: root.notificationService
    launcherBadgeService: root.launcherBadgeService
    browserProfileService: root.browserProfileService
    browserActivityMutedServices: DockModel.normalizeSetting(
      "browserActivityMutedServices", root.settings.browserActivityMutedServices)
    launcherBadgeMode: root.settings.launcherBadgeMode === "dots-only" ? "dots-only" : "automatic"
  }

  Component { id: herdrExpandedView; DockHerdrAgentsView {} }
  Component { id: herdrCompactView; DockHerdrAgentsView {} }
  Component { id: herdrPopupView; DockHerdrAgentsView {} }

  DockSidebarController {
    id: sidebarState
    widgetRegistry: root.sidebarWidgetRegistry
    host: root
    settings: root.settings
    screens: root.connectedScreens
    monitors: root.hyprMonitors
    workspaces: root.hyprWorkspaces
    applications: root.applications
    toplevels: root.desktopToplevels
    hyprToplevels: root.hyprToplevels
    minimizedOrigins: root.windowActions.minimizedOriginsSnapshot
    scopeRevision: root.scopeRevision
    focusedWorkspace: {
      var revision = root.scopeRevision
      return DockWindowModel.focusedWorkspaceIdentity(root.hyprMonitors, Hyprland.focusedWorkspace)
    }
    onSelectedScreenChanged: root.rendererScreen = selectedScreen
    onMappedScreensChanged: if (root.rendererInitialized) Qt.callLater(root.activateRenderer)
    onSurfaceInvalidated: {
      if (root.rendererMode === "sidebar") root.rendererReady = false
      Qt.callLater(root.syncRenderer)
    }
  }

  Loader {
    id: presentationLoader
    active: root.rendererReady
    sourceComponent: root.rendererMode === "sidebar" ? sidebarPresentation : classicPresentation
  }

  Component {
    id: sidebarPresentation
    Item {
      id: sidebarRoot
      readonly property var panels: sidebarVariants.instances
      readonly property var panel: panels.length ? panels[0] : null
      Variants {
        id: sidebarVariants
        model: sidebarState.mappedScreens
        delegate: Component {
          DockSidebar {
            required property var modelData
            screen: modelData
            host: root
            controller: sidebarState
          }
        }
      }
    }
  }

  Component {
    id: classicPresentation
    Item {
      Variants {
        model: Quickshell.screens
        delegate: Component {
          Dock {
            required property var modelData
            screen: modelData
            settings: root.settings
            iconOverrides: root.settings.iconOverrides || ({})
            iconReloadRevision: root.iconReloadRevision
            browserProfileService: root.browserProfileService
            browserProfileBadgesEnabled: root.settings.browserProfileBadgesEnabled !== false
            showTrash: root.showTrash
            windowActions: root.windowActions
            workspaceMonitorDrag: workspaceMonitorDragController
            badgeTracker: root.badgeTracker
            trashItemCount: root.trashItemCount
            trashStateKnown: root.trashStateKnown
            workspaceWindowCounts: root.workspaceWindowCounts
            workspaceCountsReady: root.workspaceCountsReady
            workspaceCountsRevision: root.workspaceCountsRevision
            scopeRevision: root.scopeRevision
            onReorderRequested: (sourceDesktopId, targetDesktopId) => root.reorderPinned(sourceDesktopId, targetDesktopId)
            onPinRequested: desktopId => root.pinApplication(desktopId)
            onUnpinRequested: desktopId => root.unpinApplication(desktopId)
            onHideRequested: desktopId => root.hideApplication(desktopId)
            onBrowserActivityMuteToggled: serviceId => root.toggleBrowserActivityMute(serviceId)
            onAutoHideRequested: enabled => root.saveSetting("autoHide", enabled)
            onPositionRequested: (position, expectedPosition) => {
              // Dragging the bottom dock's empty background left switches to
              // the sidebar mode; the classic dock itself is bottom-only.
              if (position === "left")
                root.saveSettingIntent("presentationMode", "sidebar",
                  root.settings.presentationMode)
              else
                root.saveSettingIntent("position", position, expectedPosition)
            }
            onOpenTrashRequested: root.openTrash()
            onEmptyTrashRequested: root.emptyTrash()
          }
        }
      }
    }
  }
}
