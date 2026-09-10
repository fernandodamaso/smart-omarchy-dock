pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "components/DockModel.js" as DockModel
import "components/DockIconModel.js" as DockIconModel
import "components/DockWindowModel.js" as DockWindowModel
import "components/DockTrashModel.js" as TrashModel

Item {
  id: root

  required property string configPath
  property var notificationService: null
  property var launcherBadgeService: null

  property int trashItemCount: 0
  property bool trashStateKnown: false
  property int iconReloadRevision: 0
  property string settingsWriteState: "idle"
  property string settingsWriteError: ""
  property bool settingsReloadPending: false
  property string settingsLoadedText: ""
  property string settingsWriteBaseText: ""
  property bool settingsLoaded: false
  property bool showTrashSetting: true
  property var workspaceWindowCounts: ({})
  property bool workspaceCountsReady: false
  property int workspaceCountsRevision: 0
  property bool workspaceCountsRefreshPending: false
  property int scopeRevision: scopeRefreshController.revision
  readonly property var windowActions: windowActionsController
  readonly property var badgeTracker: badgeTrackerController
  readonly property bool showTrash: showTrashSetting

  property var settings: ({
    iconOverrides: {},
    iconSize: 42,
    magnification: 1.2,
    magnificationRadius: 95,
    hoverGlowEnabled: true,
    hoverGlowOpacity: 0.72,
    hoverGlowRadius: 28,
    showPreviews: true,
    showTrash: true,
    margin: 10,
    backgroundOpacity: 0.88,
    backgroundColorEnabled: false,
    backgroundColor: "",
    borderColorEnabled: false,
    borderColor: "",
    workspaceBadgeBackgroundColorEnabled: false,
    workspaceBadgeBackgroundColor: "",
    workspaceBadgeTextColorEnabled: false,
    workspaceBadgeTextColor: "",
    borderWidthEnabled: false,
    borderWidth: 2,
    position: "bottom",
    fullLength: false,
    reserveSpace: true,
    autoHide: false,
    clickAction: "focus-or-launch",
    middleClickAction: "none",
    scrollAction: "none",
    controlCommand: "omarchy-menu toggle apps",
    sortByWorkspace: false,
    workspaceLayout: "flat",
    workspaceMonitorScope: "all",
    groupWindows: true,
    interfaceAnimationsEnabled: true,
    windowScope: "all",
    showUrgentOutsideScope: true,
    attentionBadgesEnabled: true,
    urgentWindowAnimationEnabled: true,
    launcherBadgeMode: "automatic",
    hiddenApplications: [],
    pinned: [
      "org.gnome.Nautilus",
      "com.mitchellh.ghostty",
      "com.google.Chrome",
      "code",
      "obsidian",
      "chatgpt"
    ]
  })

  function loadSettings(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed.pinned || !Array.isArray(parsed.pinned))
        throw new Error("'pinned' must be an array")
      parsed.showTrash = TrashModel.normalizeShowTrash(parsed.showTrash)
      parsed.hiddenApplications = DockModel.normalizeSetting(
        "hiddenApplications", parsed.hiddenApplications)
      parsed.windowScope = DockWindowModel.normalizeWindowScope(parsed.windowScope)
      parsed.showUrgentOutsideScope =
        DockWindowModel.normalizeShowUrgentOutsideScope(
          parsed.showUrgentOutsideScope)
      parsed.attentionBadgesEnabled = typeof parsed.attentionBadgesEnabled === "boolean"
        ? parsed.attentionBadgesEnabled : true
      parsed.urgentWindowAnimationEnabled =
        typeof parsed.urgentWindowAnimationEnabled === "boolean"
          ? parsed.urgentWindowAnimationEnabled : true
      parsed.interfaceAnimationsEnabled = DockModel.normalizeSetting(
        "interfaceAnimationsEnabled", parsed.interfaceAnimationsEnabled)
      parsed.launcherBadgeMode = parsed.launcherBadgeMode === "dots-only"
        ? "dots-only" : "automatic"
      parsed.iconOverrides = DockIconModel.normalizeOverrides(parsed.iconOverrides)
      var previous = DockIconModel.normalizeOverrides(settings.iconOverrides)
      var keys = Object.keys(parsed.iconOverrides)
      var iconsChanged = keys.length !== Object.keys(previous).length
        || keys.some(function(key) { return parsed.iconOverrides[key] !== previous[key] })
      if (iconsChanged) iconReloadRevision++
      showTrashSetting = parsed.showTrash
      settings = parsed
    } catch (error) {
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

  function saveIconOverride(desktopId, sourceUrl) {
    var source = sourceUrl === "" ? null : sourceUrl
    var result = DockIconModel.applyOverride(settings.iconOverrides, desktopId, source)
    if (!result.ok) return result
    if (source !== null || result.changed) {
      saveSettings({ iconOverrides: result.overrides })
      iconReloadRevision++
    }
    return result
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
    var updated = DockModel.mergeSettings(settings, patch)

    updated.showTrash = TrashModel.normalizeShowTrash(updated.showTrash)
    showTrashSetting = updated.showTrash
    settings = updated
    writeSettings()
  }

  function writeSettings() {
    var text = JSON.stringify(settings, null, 2) + "\n"
    settingsWriteBaseText = settingsLoadedText
    // FileView suppresses identical text, including bytes cached by a failed
    // write. One optional blank line forces a real attempt without changing
    // JSON values, reloading old disk state, or growing the payload on Retry.
    if (text === configFile.cachedText) text += "\n"
    // blockWrites stays enabled: completion can fire inside setText(). Keep
    // outcomes in its handlers, never infer success from returning here.
    settingsWriteState = "saving"
    configFile.setText(text)
  }

  function retrySettingsWrite() {
    // Serialize current complete settings, even if Restore removed the row.
    writeSettings()
  }

  function reloadSettingsIfPending() {
    if (!settingsReloadPending || settingsWriteState === "saving") return
    Qt.callLater(function() {
      if (root.settingsReloadPending
          && root.settingsWriteState !== "saving")
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
    onLoaded: {
      var raw = text()
      if (root.settingsReloadPending) {
        root.settingsReloadPending = false
        if (raw === root.settingsWriteBaseText) return
      }
      root.settingsLoadedText = raw
      root.loadSettings(raw)
    }
    onFileChanged: {
      root.settingsReloadPending = true
      root.reloadSettingsIfPending()
    }
    onSaved: {
      // Results describe the complete configuration, never an editor target.
      root.settingsWriteError = ""
      root.settingsWriteState = "saved"
      root.reloadSettingsIfPending()
    }
    onSaveFailed: error => {
      root.settingsWriteError = "Settings changed for this session, but could not be saved. "
        + "Retry before restarting. " + FileViewError.toString(error)
      root.settingsWriteState = "error"
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
        iconOverrides: root.settings.iconOverrides || ({})
        iconReloadRevision: root.iconReloadRevision
        settingsWriteState: root.settingsWriteState
        settingsWriteError: root.settingsWriteError
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
        onIconOverrideRequested: (desktopId, sourceUrl) => {
          root.saveIconOverride(desktopId, sourceUrl)
        }
        onSettingsWriteRetryRequested: root.retrySettingsWrite()
        onResetSettingsRequested: root.resetSettings()
        onOpenTrashRequested: root.openTrash()
        onEmptyTrashRequested: root.emptyTrash()
      }
    }
  }
}
