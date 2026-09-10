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
  readonly property var applications: DesktopEntries.applications.values || []
  property int iconReloadRevision: 0

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
    var pinned = DockModel.reorderPinnedById(settings.pinned, sourceDesktopId, targetDesktopId)
    return savePinned(pinned)
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
    return commitSettings(ConfigModel.applyPatch(settings, patch, dockControl.metadata), dryRun)
  }

  // Only validated config/app/icon model results reach this common live commit.
  // IPC never accepts a prevalidated result or a full replacement snapshot.
  function commitSettings(result, dryRun) {
    var before = settings
    if (!result.ok) {
      var rejected = dockControl.mutationData(before, before, [], false, false)
      rejected.validationErrors = result.errors
      return dockControl.failure("E_VALIDATION", "Patch rejected; no values were changed.", rejected)
    }
    if (dryRun === true)
      return dockControl.success(dockControl.mutationData(before, result.settings, result.changedKeys, true, false),
        ["Dry run only. Theme-owned/token colors and theme-owned border width are unresolved null values."])
    if (result.changedKeys.length === 0)
      return mutationOutcome(dockControl.mutationData(before, before, [], false, false))
    showTrashSetting = TrashModel.normalizeShowTrash(result.settings.showTrash)
    if (ConfigModel.iconsChanged(before.iconOverrides, result.settings.iconOverrides)) iconReloadRevision++
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
  // path is shared by CLI and existing menu/Settings intents.
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

  function resetSettings() {
    var patch = DockModel.resetSettingsPatch()
    patch.attentionBadgesEnabled = true
    patch.urgentWindowAnimationEnabled = true
    patch.interfaceAnimationsEnabled = true
    patch.launcherBadgeMode = "automatic"
    patch.windowScope = "all"
    patch.showUrgentOutsideScope = true
    return saveSettings(patch, false)
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
  }

  DockBadgeTracker {
    id: badgeTrackerController
    notificationService: root.notificationService
    launcherBadgeService: root.launcherBadgeService
    launcherBadgeMode: root.settings.launcherBadgeMode === "dots-only" ? "dots-only" : "automatic"
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      Dock {
        required property var modelData
        screen: modelData
        settings: root.settings
        iconOverrides: root.settings.iconOverrides || ({})
        iconReloadRevision: root.iconReloadRevision
        showTrash: root.showTrash
        windowActions: root.windowActions
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
        onAutoHideRequested: enabled => root.saveSetting("autoHide", enabled)
        onSettingChanged: (key, value) => root.saveSetting(key, value)
        onSettingsPatchRequested: patch => root.saveSettings(patch, false)
        onResetSettingsRequested: root.resetSettings()
        onOpenTrashRequested: root.openTrash()
        onEmptyTrashRequested: root.emptyTrash()
      }
    }
  }
}
