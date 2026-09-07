.pragma library
.import "DockModel.js" as DockModel

function liveGroupMembers(candidates, liveToplevels) {
  var values = candidates || []
  var live = liveToplevels || []
  var result = []

  for (var i = 0; i < values.length; ++i) {
    var candidate = values[i]
    if (candidate && live.indexOf(candidate) >= 0)
      result.push(candidate)
  }

  return result
}

function activeGroupMember(candidates, activeToplevel, liveToplevels) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length === 0) return null
  if (activeToplevel && live.indexOf(activeToplevel) >= 0)
    return activeToplevel
  return live[0]
}

function cycleTargetIndex(count, originIndex, direction) {
  var size = Math.floor(Number(count))
  var value = Number(originIndex)
  var delta = Number(direction)
  if (!isFinite(size) || size < 2 || !isFinite(delta) || delta === 0)
    return -1

  var step = delta > 0 ? 1 : -1
  if (!Number.isInteger(value) || value < 0 || value >= size)
    return step > 0 ? 0 : size - 1
  return (value + step + size) % size
}

function cycleGroupMember(candidates, activeToplevel, liveToplevels, direction) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length < 2) return null

  var originIndex = activeToplevel ? live.indexOf(activeToplevel) : -1
  var targetIndex = cycleTargetIndex(live.length, originIndex, direction)
  return targetIndex >= 0 ? live[targetIndex] : null
}

function dominantVerticalWheelDelta(horizontalDelta, verticalDelta) {
  var horizontal = Number(horizontalDelta)
  var vertical = Number(verticalDelta)
  if (!isFinite(horizontal)) horizontal = 0
  if (!isFinite(vertical)) vertical = 0
  if (vertical === 0 || Math.abs(vertical) <= Math.abs(horizontal)) return 0
  return vertical
}

function accumulateWheelSteps(remainder, delta, stepSize) {
  var carried = Number(remainder)
  var input = Number(delta)
  var unit = Number(stepSize)
  if (!isFinite(carried)) carried = 0
  if (!isFinite(input)) input = 0
  if (!isFinite(unit) || unit <= 0) unit = 120

  var total = carried + input
  var steps = total < 0 ? Math.ceil(total / unit) : Math.floor(total / unit)
  return {
    steps: steps,
    remainder: total - steps * unit
  }
}

function wheelStepDirection(steps) {
  var value = Number(steps)
  if (!isFinite(value) || value === 0) return 0
  return value > 0 ? 1 : -1
}

function wheelRemainderForTimestamp(remainder, previousTimestamp,
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
    if (/^id:[0-9]+$/.test(raw)) return "id:" + String(Number(raw.slice(3)))
    if (/^(id:)?-[0-9]+$/.test(raw)) return ""
    if (/^-?[0-9]+$/.test(raw)) return "id:" + String(Number(raw))
    if (raw.indexOf("name:") === 0) return raw
    return "name:" + raw
  }

  var ipc = monitor.lastIpcObject || monitor
  var rawId = ipc.id !== undefined ? ipc.id : monitor.id
  var id = rawId === null || rawId === "" ? NaN : Number(rawId)
  if (Number.isInteger(id) && id >= 0) return "id:" + id
  var name = String(ipc.name !== undefined ? ipc.name : monitor.name || "").trim()
  return name ? "name:" + name : ""
}

// Resolve connector snapshots and IPC ids through the current monitor inventory.
function canonicalMonitorIdentity(value, monitors) {
  var identity = monitorIdentity(value)
  var values = monitors || []
  if (!identity) return ""
  for (var i = 0; i < values.length; ++i) {
    var monitor = values[i]
    if (!monitor) continue
    var ipc = monitor.lastIpcObject || monitor
    if (identity === monitorIdentity(monitor)
        || identity === monitorIdentity(ipc.name || monitor.name))
      return monitorIdentity(monitor)
  }
  return monitors === undefined ? identity : ""
}

function handleUrgent(handle) {
  if (!handle) return false
  return typeof handle.urgent === "boolean" ? handle.urgent
    : (handle.lastIpcObject || ({})).urgent === true
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
  var urgent = handleUrgent(handle)

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
      originValid: DockModel.normalizeWorkspaceTarget(origin.workspace) !== "",
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
    sticky: ipc.pinned === true,
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
    "activewindow", "activewindowv2", "fullscreen", "urgent", "pin",
    "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2"
  ].indexOf(String(eventName || "")) >= 0
}
