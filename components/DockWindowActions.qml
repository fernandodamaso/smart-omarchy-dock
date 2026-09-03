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
    if (Number.isInteger(id) && id > 0) return String(id)

    var name = String(
      ipc.name !== undefined ? ipc.name : workspace.name || "").trim()
    if (!name || name.indexOf("special:") === 0) return ""
    return name.indexOf("name:") === 0 ? name : "name:" + name
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

  function activeMember(toplevels) {
    return DockWindowModel.activeGroupMember(
      toplevels, ToplevelManager.activeToplevel, currentToplevels())
  }

  function dispatchRequest(request) {
    if (!request) return false
    Hyprland.dispatch(request)
    return true
  }

  function minimizeToplevel(toplevel) {
    if (!isAlive(toplevel) || isMinimized(toplevel)) return false

    var handle = handleFor(toplevel)
    var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
    if (!address) return false

    var workspace = workspaceTarget(workspaceForHandle(handle))
      || workspaceTarget(Hyprland.focusedWorkspace)
    if (!workspace) return false

    var request = DockModel.minimizeWindowRequest(address, Hyprland.usingLua)
    if (!request) return false

    setOrigin(address, {
      workspace: workspace,
      monitor: monitorIdentity(handle)
    })
    return dispatchRequest(request)
  }

  function restoreToplevel(toplevel) {
    if (!isAlive(toplevel)) return false

    var address = addressFor(toplevel)
    if (!address) return false

    var origin = originFor(address)
    var target = origin && origin.workspace
      ? origin.workspace : workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return false

    var request = DockModel.restoreWindowRequest(
      address, target, Hyprland.usingLua)
    if (!request) return false

    if (!dispatchRequest(request)) return false
    forgetOrigin(address)
    return true
  }

  function activateToplevel(toplevel) {
    if (!isAlive(toplevel)) return false

    if (isMinimized(toplevel))
      return restoreToplevel(toplevel)

    var request = DockModel.focusWindowRequest(
      addressFor(toplevel), Hyprland.usingLua)
    if (dispatchRequest(request)) return true

    if (typeof toplevel.activate === "function") {
      toplevel.activate()
      return true
    }
    return false
  }

  function closeToplevel(toplevel) {
    if (!isAlive(toplevel) || typeof toplevel.close !== "function")
      return false
    toplevel.close()
    return true
  }

  function pruneOrigins() {
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
