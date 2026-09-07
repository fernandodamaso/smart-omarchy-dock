import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel

Item {
  id: root

  readonly property string minimizedWorkspace: "special:smartdock-minimized"
  property var minimizedOrigins: ({})
  readonly property var minimizedOriginsSnapshot: copyOrigins(minimizedOrigins)
  readonly property var activeToplevel: ToplevelManager.activeToplevel

  function currentToplevels() {
    return ToplevelManager.toplevels
      ? ToplevelManager.toplevels.values || [] : []
  }

  function currentHandles() {
    return Hyprland.toplevels ? Hyprland.toplevels.values || [] : []
  }

  function copyOrigins(source) {
    var result = {}
    var values = source || ({})
    for (var address in values) {
      var origin = values[address] || ({})
      result[address] = {
        workspace: String(origin.workspace || ""),
        monitor: String(origin.monitor || "")
      }
    }
    return result
  }

  function handleFor(toplevel) {
    if (!isAlive(toplevel)) return null

    var handles = currentHandles()
    for (var i = 0; i < handles.length; ++i) {
      if (handles[i] && handles[i].wayland === toplevel)
        return handles[i]
    }
    return null
  }

  function addressFor(toplevel) {
    var handle = handleFor(toplevel)
    return DockModel.normalizeWindowAddress(handle ? handle.address : "")
  }

  function isAlive(toplevel) {
    if (!toplevel) return false
    return currentToplevels().indexOf(toplevel) >= 0
  }

  function workspaceForHandle(handle) {
    if (!handle) return null
    var ipc = handle.lastIpcObject || ({})
    return ipc.workspace || handle.workspace || null
  }

  function workspaceTarget(workspace) {
    if (!workspace) return ""

    var ipc = workspace.lastIpcObject || workspace
    var id = Number(ipc.id !== undefined ? ipc.id : workspace.id)
    var target = ""
    if (Number.isInteger(id) && id > 0) {
      target = String(id)
    } else {
      var name = String(
        ipc.name !== undefined ? ipc.name : workspace.name || "").trim()
      if (!name || name.indexOf("special:") === 0) return ""
      target = name.indexOf("name:") === 0 ? name : "name:" + name
    }
    return DockModel.normalizeWorkspaceTarget(target)
  }

  function monitorIdentity(handle) {
    if (!handle) return ""
    var ipc = handle.lastIpcObject || ({})
    if (ipc.monitor === undefined || ipc.monitor === null) return ""
    return String(ipc.monitor)
  }

  function originAddress(value) {
    if (typeof value === "string")
      return DockModel.normalizeWindowAddress(value)
    return addressFor(value)
  }

  function originFor(value) {
    var address = originAddress(value)
    if (!address || minimizedOrigins[address] === undefined) return null
    var origin = minimizedOrigins[address] || ({})
    return {
      workspace: String(origin.workspace || ""),
      monitor: String(origin.monitor || "")
    }
  }

  function setOrigin(address, origin) {
    var normalized = DockModel.normalizeWindowAddress(address)
    if (!normalized || !origin || !origin.workspace) return false

    var origins = copyOrigins(minimizedOrigins)
    origins[normalized] = {
      workspace: String(origin.workspace),
      monitor: String(origin.monitor || "")
    }
    minimizedOrigins = origins
    return true
  }

  function forgetOrigin(value) {
    var address = originAddress(value)
    if (!address || minimizedOrigins[address] === undefined) return false

    var origins = copyOrigins(minimizedOrigins)
    delete origins[address]
    minimizedOrigins = origins
    return true
  }

  function isMinimized(toplevel) {
    var handle = handleFor(toplevel)
    if (!handle) return false

    var workspace = workspaceForHandle(handle)
    var workspaceName = workspace ? String(workspace.name || "") : ""
    var ipc = handle.lastIpcObject || ({})
    if (ipc.workspace && ipc.workspace.name !== undefined)
      workspaceName = String(ipc.workspace.name || "")

    if (workspaceName === minimizedWorkspace) return true

    var address = DockModel.normalizeWindowAddress(handle.address || "")
    return address !== "" && minimizedOrigins[address] !== undefined
  }

  function windowState(toplevel) {
    var handle = handleFor(toplevel)
    if (!handle)
      return { minimized: false, workspace: "", monitor: "" }

    var minimized = isMinimized(toplevel)
    var origin = originFor(toplevel)
    var workspace = minimized && origin
      ? origin.workspace : workspaceTarget(workspaceForHandle(handle))
    var monitor = minimized && origin
      ? origin.monitor : monitorIdentity(handle)

    return {
      minimized: minimized,
      workspace: workspace,
      monitor: monitor
    }
  }

  function liveMembers(toplevels) {
    return DockWindowModel.liveGroupMembers(toplevels, currentToplevels())
  }

  function dispatchRequest(request) {
    if (!request) return false
    Hyprland.dispatch(request)
    return true
  }

  function resolveOriginTarget(recorded, originOnly) {
    var target = DockModel.normalizeWorkspaceTarget(recorded)
    if (recorded || originOnly === true) return target
    return workspaceTarget(Hyprland.focusedWorkspace)
  }

  function minimizeToplevel(toplevel, originOnly) {
    if (!isAlive(toplevel) || isMinimized(toplevel)) return false

    var handle = handleFor(toplevel)
    var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
    if (!address) return false

    var workspace = resolveOriginTarget(
      workspaceTarget(workspaceForHandle(handle)), originOnly)
    if (!workspace) return false

    var request = DockModel.minimizeWindowRequest(address, Hyprland.usingLua)
    if (!request) return false

    setOrigin(address, {
      workspace: workspace,
      monitor: monitorIdentity(handle)
    })
    return dispatchRequest(request)
  }

  function restoreToplevel(toplevel, originOnly) {
    if (!isAlive(toplevel)) return false

    var address = addressFor(toplevel)
    if (!address) return false

    var origin = originFor(address)
    var target = resolveOriginTarget(origin ? origin.workspace : "", originOnly)
    if (!target) return false

    var request = DockModel.restoreWindowRequest(
      address, target, Hyprland.usingLua)
    if (!request) return false

    if (!dispatchRequest(request)) return false
    forgetOrigin(address)
    return true
  }

  function activateToplevel(toplevel, originOnly) {
    if (!isAlive(toplevel)) return false

    if (isMinimized(toplevel))
      return restoreToplevel(toplevel, originOnly)

    var request = DockModel.focusWindowRequest(
      addressFor(toplevel), Hyprland.usingLua)
    if (dispatchRequest(request)) return true

    if (typeof toplevel.activate === "function") {
      toplevel.activate()
      return true
    }
    return false
  }

  function cycleToplevels(toplevels, direction, activeToplevel) {
    var members = liveMembers(toplevels)
    if (members.length < 2) return false

    var active = activeToplevel === undefined
      ? root.activeToplevel : activeToplevel
    var target = DockWindowModel.cycleGroupMember(
      members, active, currentToplevels(), direction)
    if (!target) return false

    var address = addressFor(target)
    if (!address) return false

    if (isMinimized(target)) {
      if (!restoreToplevel(target, originOnly)) return false
      var focusRequest = DockModel.focusWindowRequest(address, Hyprland.usingLua)
      if (dispatchRequest(focusRequest)) return true
      if (typeof target.activate === "function") {
        target.activate()
        return true
      }
      return true
    }

    return activateToplevel(target, originOnly)
  }

  function minimizeRestoreToplevels(toplevels, originOnly) {
    var members = liveMembers(toplevels)
    if (members.length === 0) return false

    var states = []
    for (var stateIndex = 0; stateIndex < members.length; ++stateIndex)
      states.push(windowState(members[stateIndex]))

    var mode = DockModel.minimizeRestoreMode(states)
    var changed = false
    for (var i = 0; i < members.length; ++i) {
      if (mode === "minimize" && !states[i].minimized)
        changed = minimizeToplevel(members[i], originOnly) || changed
      else if (mode === "restore" && states[i].minimized)
        changed = restoreToplevel(members[i], originOnly) || changed
    }
    return changed
  }

  function closeToplevels(toplevels) {
    var members = liveMembers(toplevels)
    var requested = false
    for (var i = 0; i < members.length; ++i)
      requested = closeToplevel(members[i]) || requested
    return requested
  }

  function closeToplevel(toplevel) {
    if (!isAlive(toplevel) || typeof toplevel.close !== "function")
      return false
    toplevel.close()
    return true
  }

  function pruneOrigins() {
    var retained = DockWindowModel.pruneOriginSnapshot(
      minimizedOrigins, currentHandles(), currentToplevels())
    if (JSON.stringify(retained) !== JSON.stringify(minimizedOrigins))
      minimizedOrigins = copyOrigins(retained)
  }

  Timer {
    id: pruneTimer
    interval: 120
    repeat: false
    onTriggered: root.pruneOrigins()
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { pruneTimer.restart() }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { pruneTimer.restart() }
  }
}
