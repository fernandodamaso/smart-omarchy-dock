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

Item {
  id: root

  required property string configPath
  required property string runtimeMode
  property var notificationService: null
  property var launcherBadgeService: null

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

  // The installed/repository default file is shared with the CLI metadata.
  // No discovery command creates a user configuration or persists defaults.
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
      // Null-prototype storage preserves extension keys without invoking setters.
      Object.keys(parsed).forEach(function(key) { requested[key] = parsed[key] })
      showTrashSetting = TrashModel.normalizeShowTrash(parsed.showTrash)
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
    var pinned = DockModel.reorderPinnedById(
      settings.pinned, sourceDesktopId, targetDesktopId)
    if (JSON.stringify(pinned) === JSON.stringify(settings.pinned)) return
    savePinned(pinned)
  }

  function pinApplication(desktopId) {
    if (!desktopId || settings.pinned.indexOf(desktopId) >= 0) return
    var pinned = settings.pinned.slice()
    pinned.push(desktopId)
    savePinned(pinned)
  }

  function unpinApplication(desktopId) {
    var index = settings.pinned.indexOf(desktopId)
    if (index < 0) return
    var pinned = settings.pinned.slice()
    pinned.splice(index, 1)
    savePinned(pinned)
  }

  function hideApplication(desktopId) {
    var hiddenApplications = DockModel.addHiddenApplication(settings.hiddenApplications, desktopId)
    saveSetting("hiddenApplications", hiddenApplications)
  }

  function savePinned(pinned) {
    saveSetting("pinned", pinned)
  }

  function saveSetting(key, value) {
    var patch = {}
    patch[key] = value
    saveSettings(patch)
  }

  function saveSettings(patch) {
    if (!settingsLoaded || settingsReloadPending || settingsWriteState === "saving"
        || settingsLoadState === "invalid") {
      console.warn("Dock: settings are busy or invalid; change was not applied")
      return
    }
    var updated = Object.create(null)
    Object.keys(settings).forEach(function(key) { updated[key] = settings[key] })
    Object.keys(patch).forEach(function(key) { updated[key] = patch[key] })
    if (JSON.stringify(updated) === JSON.stringify(settings)) return
    showTrashSetting = TrashModel.normalizeShowTrash(updated.showTrash)
    settings = updated
    settingsRevision++
    settingsDefaultsInUse = false
    settingsPersisted = false
    writeSettings()
  }

  // Retained FDM-881 writer behavior from PR #43 @7473a23: actual saved/error
  // completion, bounded retry bytes and failed-write echo protection. The
  // Settings editor and icon stack are deliberately not imported here.
  function writeSettings() {
    var text = JSON.stringify(settings, null, 2) + "\n"
    settingsWriteBaseText = settingsLoadedText
    if (text === configFile.cachedText) text += "\n"
    settingsWriteText = text
    settingsWriteState = "saving"
    configFile.setText(text)
  }

  function reloadSettingsIfPending() {
    if (!settingsReloadPending || settingsWriteState === "saving") return
    Qt.callLater(function() {
      if (root.settingsReloadPending && root.settingsWriteState !== "saving")
        configFile.reload()
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
    saveSettings(patch)
  }

  function refreshTrash() {
    if (!TrashModel.shouldRefresh(showTrash, trashListProcess.running,
        settingsLoaded)) return
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
      if (DockModel.shouldRefreshWorkspaceState(name))
        workspaceCountsRefreshTimer.restart()
      if (DockWindowModel.shouldRefreshWindowScope(name))
        scopeRefreshController.requestRefresh()
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
      if (exitCode !== 0)
        console.warn("Dock: could not read workspace counts (hyprctl exited "
          + exitCode + ")")
      if (root.workspaceCountsRefreshPending)
        Qt.callLater(root.refreshWorkspaceCounts)
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
      if (exitCode !== 0)
        console.warn("Dock: could not inspect Trash (gio exited " + exitCode + ")")
    }
  }

  Process {
    id: trashEmptyProcess
    command: ["gio", "trash", "--empty"]
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("Dock: could not empty Trash (gio exited " + exitCode + ")")
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
    onLoaded: {
      var raw = text()
      if (root.settingsReloadPending) {
        root.settingsReloadPending = false
        if (root.settingsWriteState === "error" && raw === root.settingsWriteBaseText)
          return
      }
      root.loadSettings(raw)
    }
    onLoadFailed: error => {
      root.settingsReloadPending = false
      root.settingsLoaded = true
      root.settingsPersisted = false
      root.settingsLoadState = error === FileViewError.FileNotFound ? "missing" : "invalid"
      root.settingsLoadError = error === FileViewError.FileNotFound ? "" : FileViewError.toString(error)
      if (root.showTrash) Qt.callLater(root.refreshTrash)
    }
    onFileChanged: {
      root.settingsReloadPending = true
      root.reloadSettingsIfPending()
    }
    onSaved: {
      root.settingsWriteError = ""
      root.settingsWriteState = "saved"
      root.settingsLoadedText = root.settingsWriteText
      root.settingsLoadState = "loaded"
      root.settingsLoadError = ""
      root.settingsPersisted = true
      root.reloadSettingsIfPending()
    }
    onSaveFailed: error => {
      root.settingsWriteError = "Settings changed for this session, but could not be saved. "
        + "Retry before restarting. " + FileViewError.toString(error)
      root.settingsWriteState = "error"
      root.settingsPersisted = false
      console.warn("Dock: could not save " + root.configPath + ":", error)
      root.reloadSettingsIfPending()
    }
  }

  DockWindowActions {
    id: windowActionsController
  }

  DockBadgeTracker {
    id: badgeTrackerController
    notificationService: root.notificationService
    launcherBadgeService: root.launcherBadgeService
    launcherBadgeMode: root.settings.launcherBadgeMode === "dots-only"
      ? "dots-only" : "automatic"
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      Dock {
        required property var modelData
        screen: modelData
        settings: root.settings
        showTrash: root.showTrash
        windowActions: root.windowActions
        badgeTracker: root.badgeTracker
        trashItemCount: root.trashItemCount
        trashStateKnown: root.trashStateKnown
        workspaceWindowCounts: root.workspaceWindowCounts
        workspaceCountsReady: root.workspaceCountsReady
        workspaceCountsRevision: root.workspaceCountsRevision
        scopeRevision: root.scopeRevision
        onReorderRequested: (sourceDesktopId, targetDesktopId) => {
          root.reorderPinned(sourceDesktopId, targetDesktopId)
        }
        onPinRequested: desktopId => root.pinApplication(desktopId)
        onUnpinRequested: desktopId => root.unpinApplication(desktopId)
        onHideRequested: desktopId => root.hideApplication(desktopId)
        onAutoHideRequested: enabled => root.saveSetting("autoHide", enabled)
        onSettingChanged: (key, value) => root.saveSetting(key, value)
        onSettingsPatchRequested: patch => root.saveSettings(patch)
        onResetSettingsRequested: root.resetSettings()
        onOpenTrashRequested: root.openTrash()
        onEmptyTrashRequested: root.emptyTrash()
      }
    }
  }
}
