from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one anchor, found {count}: {old[:90]!r}")
    p.write_text(text.replace(old, new, 1))


def append_once(path, anchor, addition):
    replace_once(path, anchor, anchor + addition)


# Pure scope/filter model, appended after the already-qualified FDM-808 helpers.
append_once(
    "components/DockWindowModel.js",
    '''function wheelRemainderForTimestamp(remainder, previousTimestamp,
                                    currentTimestamp, resetAfterMs) {
  var carried = Number(remainder)
  var previous = Number(previousTimestamp)
  var current = Number(currentTimestamp)
  var timeout = Number(resetAfterMs)
  if (!isFinite(carried)) carried = 0
  if (!isFinite(timeout) || timeout < 0) timeout = 220
  if (!isFinite(previous) || previous <= 0 || !isFinite(current)) return carried
  if (current < previous || current - previous > timeout) return 0
  return carried
}
''',
    '''
function windowScopeValues() {
  return ["all", "workspace", "monitor", "workspace-monitor"]
}

function windowScopeOptions() {
  return [
    { value: "all", label: "All windows" },
    { value: "workspace", label: "Current workspace" },
    { value: "monitor", label: "Current monitor" },
    { value: "workspace-monitor", label: "Workspace + monitor" }
  ]
}

function normalizeWindowScope(value) {
  var scope = String(value === undefined || value === null ? "" : value).trim()
  return windowScopeValues().indexOf(scope) >= 0 ? scope : "all"
}

function normalizeShowUrgentOutsideScope(value) {
  return typeof value === "boolean" ? value : true
}

function workspaceIdentity(workspace) {
  if (workspace === undefined || workspace === null) return ""

  if (typeof workspace === "string" || typeof workspace === "number") {
    var raw = String(workspace).trim()
    if (!raw) return ""
    if (/^id:[1-9][0-9]*$/.test(raw))
      return "id:" + String(Number(raw.slice(3)))
    if (/^[1-9][0-9]*$/.test(raw)) return "id:" + String(Number(raw))
    if (raw.indexOf("special:") === 0) return raw
    if (raw.indexOf("name:") === 0) return raw.length > 5 ? raw : ""
    return "name:" + raw
  }

  var ipc = workspace.lastIpcObject || workspace
  var name = String(ipc.name !== undefined ? ipc.name : workspace.name || "").trim()
  var id = Number(ipc.id !== undefined ? ipc.id : workspace.id)
  if (name.indexOf("special:") === 0) return name
  if (Number.isInteger(id) && id > 0) return "id:" + id
  if (name) return name.indexOf("name:") === 0 ? name : "name:" + name
  return ""
}

function monitorIdentity(monitor) {
  if (monitor === undefined || monitor === null) return ""

  if (typeof monitor === "string" || typeof monitor === "number") {
    var raw = String(monitor).trim()
    if (!raw) return ""
    if (/^-?[0-9]+$/.test(raw)) return "id:" + String(Number(raw))
    return "name:" + raw
  }

  var ipc = monitor.lastIpcObject || monitor
  var id = Number(ipc.id !== undefined ? ipc.id : monitor.id)
  if (Number.isInteger(id)) return "id:" + id
  var name = String(ipc.name !== undefined ? ipc.name : monitor.name || "").trim()
  return name ? "name:" + name : ""
}

function focusedWorkspaceIdentity(monitors, focusedWorkspace) {
  var values = monitors || []
  for (var i = 0; i < values.length; ++i) {
    var monitor = values[i]
    if (!monitor) continue
    var ipc = monitor.lastIpcObject || monitor
    if (ipc.focused !== true) continue
    var identity = workspaceIdentity(ipc.activeWorkspace)
    if (identity) return identity
  }
  return workspaceIdentity(focusedWorkspace)
}

function windowScopeContext(scope, focusedWorkspace, dockMonitor,
                            showUrgentOutsideScope) {
  return {
    scope: normalizeWindowScope(scope),
    workspace: workspaceIdentity(focusedWorkspace),
    monitor: monitorIdentity(dockMonitor),
    showUrgentOutsideScope:
      normalizeShowUrgentOutsideScope(showUrgentOutsideScope)
  }
}

function normalizedAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  if (address.slice(0, 2) === "0x") address = address.slice(2)
  return /^[0-9a-f]+$/.test(address) ? "0x" + address : ""
}

function handleForToplevel(toplevel, handles) {
  var values = handles || []
  for (var i = 0; i < values.length; ++i) {
    if (values[i] && values[i].wayland === toplevel) return values[i]
  }
  return null
}

function locationForToplevel(toplevel, handles, originSnapshot) {
  var handle = handleForToplevel(toplevel, handles)
  if (!handle) {
    return {
      address: "", workspace: "", monitor: "",
      workspaceKnown: false, monitorKnown: false,
      minimized: false, urgent: false
    }
  }

  var ipc = handle.lastIpcObject || ({})
  var address = normalizedAddress(handle.address || ipc.address)
  var workspace = workspaceIdentity(ipc.workspace || handle.workspace)
  var minimized = workspace === "special:smartdock-minimized"
  var urgent = ipc.urgent === true

  if (minimized) {
    var origins = originSnapshot || ({})
    var origin = address ? origins[address] : null
    if (!origin) {
      return {
        address: address, workspace: "", monitor: "",
        workspaceKnown: false, monitorKnown: false,
        minimized: true, urgent: urgent
      }
    }
    var originWorkspace = workspaceIdentity(origin.workspace)
    var originMonitor = monitorIdentity(origin.monitor)
    return {
      address: address,
      workspace: originWorkspace,
      monitor: originMonitor,
      workspaceKnown: originWorkspace !== "",
      monitorKnown: originMonitor !== "",
      minimized: true,
      urgent: urgent
    }
  }

  var monitor = monitorIdentity(
    ipc.monitor !== undefined ? ipc.monitor : handle.monitor)
  return {
    address: address,
    workspace: workspace,
    monitor: monitor,
    workspaceKnown: workspace !== "",
    monitorKnown: monitor !== "",
    minimized: false,
    urgent: urgent
  }
}

function dimensionMatches(known, actual, expected) {
  if (!known || !expected) return true
  return actual === expected
}

function locationMatchesContext(location, context) {
  var value = location || ({})
  var scopeContext = context || windowScopeContext("all", null, null, true)
  var scope = normalizeWindowScope(scopeContext.scope)
  if (scope === "all") return true

  var workspaceMatches = dimensionMatches(
    value.workspaceKnown === true, String(value.workspace || ""),
    String(scopeContext.workspace || ""))
  var monitorMatches = dimensionMatches(
    value.monitorKnown === true, String(value.monitor || ""),
    String(scopeContext.monitor || ""))

  if (scope === "workspace") return workspaceMatches
  if (scope === "monitor") return monitorMatches
  return workspaceMatches && monitorMatches
}

function filterToplevelsByScope(toplevels, handles, originSnapshot, context) {
  var values = toplevels || []
  var result = []
  var scopeContext = context || windowScopeContext("all", null, null, true)

  for (var i = 0; i < values.length; ++i) {
    var toplevel = values[i]
    if (!toplevel) continue
    var location = locationForToplevel(toplevel, handles, originSnapshot)
    var inScope = locationMatchesContext(location, scopeContext)
    var urgentException = scopeContext.scope !== "all"
      && scopeContext.showUrgentOutsideScope === true
      && location.urgent === true
    if (inScope || urgentException) result.push(toplevel)
  }
  return result
}

function copyOriginSnapshot(origins) {
  var result = {}
  var values = origins || ({})
  for (var address in values) {
    var normalized = normalizedAddress(address)
    if (!normalized) continue
    var origin = values[address] || ({})
    result[normalized] = {
      workspace: String(origin.workspace || ""),
      monitor: String(origin.monitor || "")
    }
  }
  return result
}

function pruneOriginSnapshot(origins, handles, liveToplevels) {
  var source = copyOriginSnapshot(origins)
  var addresses = Object.keys(source)
  if (addresses.length === 0) return source

  var handleValues = handles || []
  var live = liveToplevels || []
  if (handleValues.length === 0 && live.length > 0) return source

  var retained = {}
  for (var i = 0; i < handleValues.length; ++i) {
    var handle = handleValues[i]
    if (!handle || !handle.wayland || live.indexOf(handle.wayland) < 0) continue
    var address = normalizedAddress(handle.address
      || (handle.lastIpcObject || ({})).address)
    if (!address || source[address] === undefined) continue
    retained[address] = source[address]
  }
  return retained
}

function shouldRefreshWindowScope(eventName) {
  return [
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "workspace", "workspacev2", "createworkspace", "createworkspacev2",
    "destroyworkspace", "destroyworkspacev2", "focusedmon",
    "activewindow", "activewindowv2", "fullscreen", "urgent",
    "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2"
  ].indexOf(String(eventName || "")) >= 0
}
''')

# Host owns normalization and one debounced refresh path for all monitor docks.
replace_once(
    "DockHost.qml",
    '''import Quickshell.Hyprland
import Quickshell.Io
import "components"
import "components/DockModel.js" as DockModel''',
    '''import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "components/DockModel.js" as DockModel
import "components/DockWindowModel.js" as DockWindowModel''')

replace_once(
    "DockHost.qml",
    '''  property int workspaceCountsRevision: 0
  property bool workspaceCountsRefreshPending: false
  readonly property var windowActions: windowActionsController''',
    '''  property int workspaceCountsRevision: 0
  property bool workspaceCountsRefreshPending: false
  property int scopeRevision: 0
  readonly property var windowActions: windowActionsController''')

replace_once(
    "DockHost.qml",
    '''    sortByWorkspace: false,
    groupWindows: true,
    attentionBadgesEnabled: true,''',
    '''    sortByWorkspace: false,
    groupWindows: true,
    windowScope: "all",
    showUrgentOutsideScope: true,
    attentionBadgesEnabled: true,''')

replace_once(
    "DockHost.qml",
    '''      parsed.hiddenApplications = DockModel.normalizeSetting(
        "hiddenApplications", parsed.hiddenApplications)
      parsed.attentionBadgesEnabled = typeof parsed.attentionBadgesEnabled === "boolean"''',
    '''      parsed.hiddenApplications = DockModel.normalizeSetting(
        "hiddenApplications", parsed.hiddenApplications)
      parsed.windowScope = DockWindowModel.normalizeWindowScope(parsed.windowScope)
      parsed.showUrgentOutsideScope =
        DockWindowModel.normalizeShowUrgentOutsideScope(
          parsed.showUrgentOutsideScope)
      parsed.attentionBadgesEnabled = typeof parsed.attentionBadgesEnabled === "boolean"''')

replace_once(
    "DockHost.qml",
    '''    patch.launcherBadgeMode = "automatic"
    saveSettings(patch)''',
    '''    patch.launcherBadgeMode = "automatic"
    patch.windowScope = "all"
    patch.showUrgentOutsideScope = true
    saveSettings(patch)''')

replace_once(
    "DockHost.qml",
    '''    root.workspaceCountsRefreshPending = false
    Hyprland.refreshMonitors()
    workspaceCountsProcess.running = true''',
    '''    root.workspaceCountsRefreshPending = false
    workspaceCountsProcess.running = true''')

replace_once(
    "DockHost.qml",
    '''  Component.onCompleted: {
    refreshWorkspaceCounts()
  }''',
    '''  Component.onCompleted: {
    refreshWorkspaceCounts()
    scopeRefreshTimer.restart()
  }''')

replace_once(
    "DockHost.qml",
    '''  Timer {
    id: workspaceCountsRefreshTimer

    interval: 100
    repeat: false
    onTriggered: root.refreshWorkspaceCounts()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (DockModel.shouldRefreshWorkspaceState(event ? event.name : ""))
        workspaceCountsRefreshTimer.restart()
    }
  }''',
    '''  Timer {
    id: workspaceCountsRefreshTimer

    interval: 100
    repeat: false
    onTriggered: root.refreshWorkspaceCounts()
  }

  Timer {
    id: scopeRefreshTimer

    interval: 80
    repeat: false
    onTriggered: {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      root.scopeRevision++
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (DockModel.shouldRefreshWorkspaceState(name))
        workspaceCountsRefreshTimer.restart()
      if (DockWindowModel.shouldRefreshWindowScope(name))
        scopeRefreshTimer.restart()
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { scopeRefreshTimer.restart() }
  }''')

replace_once(
    "DockHost.qml",
    '''        workspaceCountsReady: root.workspaceCountsReady
        workspaceCountsRevision: root.workspaceCountsRevision
        onReorderRequested:''',
    '''        workspaceCountsReady: root.workspaceCountsReady
        workspaceCountsRevision: root.workspaceCountsRevision
        scopeRevision: root.scopeRevision
        onReorderRequested:''')

# Scope-aware Dock while preserving PR #18's deferred visibleItems snapshot.
replace_once(
    "components/Dock.qml",
    '''import "DockModel.js" as DockModel
import "DockBadgeModel.js" as BadgeModel''',
    '''import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel
import "DockBadgeModel.js" as BadgeModel''')

replace_once(
    "components/Dock.qml",
    '''  required property bool workspaceCountsReady
  required property int workspaceCountsRevision
  signal reorderRequested''',
    '''  required property bool workspaceCountsReady
  required property int workspaceCountsRevision
  required property int scopeRevision
  signal reorderRequested''')

replace_once(
    "components/Dock.qml",
    '''  property bool autoHideRevealed: false
  property int fullscreenStateRevision: 0
  property int workspaceStateRevision: 0
  property int badgeStateRevision: 0''',
    '''  property bool autoHideRevealed: false
  property int badgeStateRevision: 0''')

replace_once(
    "components/Dock.qml",
    '''  readonly property bool groupWindows: DockModel.normalizeSetting(
    "groupWindows", effectiveSetting("groupWindows"))
  readonly property bool attentionBadgesEnabled:''',
    '''  readonly property bool groupWindows: DockModel.normalizeSetting(
    "groupWindows", effectiveSetting("groupWindows"))
  readonly property string windowScope: DockWindowModel.normalizeWindowScope(
    effectiveSetting("windowScope"))
  readonly property bool showUrgentOutsideScope:
    DockWindowModel.normalizeShowUrgentOutsideScope(
      effectiveSetting("showUrgentOutsideScope"))
  readonly property bool attentionBadgesEnabled:''')

replace_once(
    "components/Dock.qml",
    '''  readonly property var hyprMonitors: Hyprland.monitors
    ? Hyprland.monitors.values || [] : []
  readonly property int focusedWorkspaceId: {
    var revision = workspaceStateRevision + workspaceCountsRevision
    return DockModel.focusedWorkspaceIdFromMonitors(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property var fullscreenOwnerToplevel: DockModel.fullscreenOwner(
    toplevels, hyprToplevels, focusedWorkspaceId, activeToplevel,
    fullscreenStateRevision)''',
    '''  readonly property var hyprMonitors: Hyprland.monitors
    ? Hyprland.monitors.values || [] : []
  readonly property var dockHyprMonitor: {
    var revision = scopeRevision
    return Hyprland.monitorFor(screen)
  }
  readonly property string focusedScopeWorkspace: {
    var revision = scopeRevision
    return DockWindowModel.focusedWorkspaceIdentity(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var windowScopeContext: {
    var revision = scopeRevision
    return DockWindowModel.windowScopeContext(
      windowScope, focusedScopeWorkspace, dockHyprMonitor,
      showUrgentOutsideScope)
  }
  readonly property var filteredToplevels: {
    var revision = scopeRevision
    return DockWindowModel.filterToplevelsByScope(
      toplevels, hyprToplevels,
      windowActions ? windowActions.minimizedOriginsSnapshot : ({}),
      windowScopeContext)
  }
  readonly property int focusedWorkspaceId: {
    var revision = scopeRevision + workspaceCountsRevision
    return DockModel.focusedWorkspaceIdFromMonitors(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property var fullscreenOwnerToplevel: DockModel.fullscreenOwner(
    toplevels, hyprToplevels, focusedWorkspaceId, activeToplevel,
    scopeRevision)''')

replace_once(
    "components/Dock.qml",
    '''  readonly property var visibleWorkspaceIds: {
    var revision = workspaceStateRevision + workspaceCountsRevision''',
    '''  readonly property var visibleWorkspaceIds: {
    var revision = scopeRevision + workspaceCountsRevision''')

replace_once(
    "components/Dock.qml",
    '''    var nextItems = DockModel.buildVisibleItems(
      pinned, toplevels, applications, hyprToplevels, sortByWorkspace,
      groupWindows, hiddenApplications)''',
    '''    var nextItems = DockModel.buildVisibleItems(
      pinned, filteredToplevels, applications, hyprToplevels, sortByWorkspace,
      groupWindows, hiddenApplications)''')

replace_once(
    "components/Dock.qml",
    '''  onHiddenApplicationsChanged: root.scheduleVisibleItemsRefresh()

  Component.onCompleted:''',
    '''  onHiddenApplicationsChanged: root.scheduleVisibleItemsRefresh()
  onScopeRevisionChanged: {
    root.windowPreview.dismissImmediately()
    root.scheduleVisibleItemsRefresh()
  }

  Component.onCompleted:''')

replace_once(
    "components/Dock.qml",
    '''  Timer {
    id: fullscreenStateRefreshTimer

    interval: 80
    repeat: false
    onTriggered: {
      root.fullscreenStateRevision++
      root.scheduleVisibleItemsRefresh()
    }
  }

  Timer {
    id: workspaceStateRefreshTimer

    interval: 80
    repeat: false
    onTriggered: {
      root.workspaceStateRevision++
      root.scheduleVisibleItemsRefresh()
    }
  }

''',
    '''''')

replace_once(
    "components/Dock.qml",
    '''  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (DockModel.shouldRefreshFullscreenPresentation(name)) {
        Hyprland.refreshToplevels()
        fullscreenStateRefreshTimer.restart()
      }
      if (DockModel.shouldRefreshWorkspaceState(name)) {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        workspaceStateRefreshTimer.restart()
      }
      if (["windowtitle", "windowtitlev2"].indexOf(String(name)) >= 0)
        visibleItemsRawEventTimer.restart()
    }
  }''',
    '''  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (["windowtitle", "windowtitlev2"].indexOf(String(name)) >= 0)
        visibleItemsRawEventTimer.restart()
    }
  }''')

replace_once(
    "components/Dock.qml",
    '''  Connections {
    target: Hyprland.workspaces

    function onValuesChanged() {
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.scheduleVisibleItemsRefresh()
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.monitors

    function onValuesChanged() {
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: ToplevelManager

    function onActiveToplevelChanged() {
      fullscreenStateRefreshTimer.restart()
      Hyprland.refreshMonitors()
      workspaceStateRefreshTimer.restart()
    }
  }''',
    '''  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.scheduleVisibleItemsRefresh()
    }
  }''')

# Pure origin pruning is shared with the scope model.
replace_once(
    "components/DockWindowActions.qml",
    '''  function pruneOrigins() {
    var origins = minimizedOrigins
    var addresses = Object.keys(origins)
    if (addresses.length === 0) return

    var handles = currentHandles()
    var live = currentToplevels()
    if (handles.length === 0 && live.length > 0) return

    var retained = {}
    for (var i = 0; i < handles.length; ++i) {
      var handle = handles[i]
      var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
      if (!address || origins[address] === undefined) continue
      if (!handle.wayland || live.indexOf(handle.wayland) < 0) continue
      retained[address] = origins[address]
    }

    if (Object.keys(retained).length !== addresses.length)
      minimizedOrigins = copyOrigins(retained)
  }''',
    '''  function pruneOrigins() {
    var retained = DockWindowModel.pruneOriginSnapshot(
      minimizedOrigins, currentHandles(), currentToplevels())
    if (JSON.stringify(retained) !== JSON.stringify(minimizedOrigins))
      minimizedOrigins = copyOrigins(retained)
  }''')

# Settings/config UI.
replace_once(
    "components/DockSettings.qml",
    '''import "DockModel.js" as DockModel
import "DockTrashModel.js" as TrashModel''',
    '''import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel
import "DockTrashModel.js" as TrashModel''')

replace_once(
    "components/DockSettings.qml",
    '''              DockSettingsToggleRow {
                width: parent.width
                label: "Group windows"''',
    '''              DockActionDropdown {
                width: parent.width
                label: "Window scope"
                value: DockWindowModel.normalizeWindowScope(
                  root.current("windowScope"))
                options: DockWindowModel.windowScopeOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("windowScope", value)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Show urgent outside scope"
                description: root.current("windowScope") === "all"
                  ? "All windows are already visible" : "Include truly urgent Hyprland windows from elsewhere"
                enabled: root.current("windowScope") !== "all"
                opacity: enabled ? 1 : 0.45
                checked: root.current("showUrgentOutsideScope") !== false
                onToggled: root.commit("showUrgentOutsideScope", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Group windows"''')

replace_once(
    "config/dock.json",
    '''  "sortByWorkspace": false,
  "groupWindows": true,
  "attentionBadgesEnabled": true,''',
    '''  "sortByWorkspace": false,
  "groupWindows": true,
  "windowScope": "all",
  "showUrgentOutsideScope": true,
  "attentionBadgesEnabled": true,''')

# Concise docs without importing stale four-action wording from old PR #7.
replace_once(
    "README.md",
    '''| `groupWindows` | When `true`, combine an app's open windows into one dock icon; when `false`, show one icon per window |
| `attentionBadgesEnabled` |''',
    '''| `groupWindows` | When `true`, combine an app's open windows into one dock icon; when `false`, show one icon per window |
| `windowScope` | Running-window visibility: `all`, `workspace`, `monitor`, or `workspace-monitor`; invalid/missing values use `all` |
| `showUrgentOutsideScope` | When enabled, a true Hyprland-urgent window may bypass a non-`all` scope; notification/SNI attention does not |
| `attentionBadgesEnabled` |''')

replace_once(
    "README.md",
    '''### Grouped-window wheel cycling
''',
    '''### Window scope filtering

`windowScope` filters individual running windows before grouping. `all` preserves
existing behavior; `workspace` uses the workspace active on Hyprland's focused
monitor; `monitor` uses each Dock's own screen/monitor; and
`workspace-monitor` requires both. Closed pinned launchers stay visible.

When `showUrgentOutsideScope` is enabled, only Hyprland's actual per-window
urgent state bypasses scope. Explicitly hidden applications still stay hidden.
SmartDock-minimized windows use the shared host-owned workspace/monitor origin;
unknown or transient location data fails open so the only restore affordance is
not lost. Scope refresh is debounced once in `DockHost.qml` for all monitor
Docks, with no per-Dock `hyprctl` polling.

### Grouped-window wheel cycling
''')

print("FDM-812 recovery patch applied")
