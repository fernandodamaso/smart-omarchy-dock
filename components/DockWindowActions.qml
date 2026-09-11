import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel

Item {
  id: root

  readonly property string minimizedWorkspace: "special:smartdock-minimized"
  property var minimizedOrigins: ({})
  readonly property var minimizedOriginsSnapshot: DockWindowModel.copyOriginSnapshot(minimizedOrigins)
  readonly property var activeToplevel: ToplevelManager.activeToplevel

  function currentToplevels() {
    return ToplevelManager.toplevels
      ? ToplevelManager.toplevels.values || [] : []
  }

  function currentHandles() {
    return Hyprland.toplevels ? Hyprland.toplevels.values || [] : []
  }

  function handleFor(toplevel) {
    if (!isAlive(toplevel)) return null
    return DockWindowModel.handleForToplevel(toplevel, currentHandles())
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

    var origins = DockWindowModel.copyOriginSnapshot(minimizedOrigins)
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

    var origins = DockWindowModel.copyOriginSnapshot(minimizedOrigins)
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

  function focusToplevels(toplevels, originOnly) {
    var members = liveMembers(toplevels)
    if (members.length === 0) return false
    var member = root.activeToplevel && members.indexOf(root.activeToplevel) >= 0
      ? root.activeToplevel : members[0]
    return activateToplevel(member, originOnly)
  }

  function dispatchRequest(request) {
    if (!request) return false
    Hyprland.dispatch(request)
    return true
  }

  // Drag payloads own exact objects AND addresses, never an app-id lookup.
  function captureWorkspaceMove(toplevels) {
    var values = toplevels || []
    var captured = []
    var seen = []
    for (var i = 0; i < values.length; ++i) {
      var toplevel = values[i]
      if (!isAlive(toplevel)) return []
      if (seen.indexOf(toplevel) >= 0) continue
      seen.push(toplevel)
      captured.push({ toplevel: toplevel, address: addressFor(toplevel) })
    }
    var validated = workspaceMoveMembers(captured)
    return validated && validated.length === captured.length ? captured : []
  }

  function workspaceMoveLocation(toplevel, address) {
    var handle = handleFor(toplevel)
    if (!handle || !address || addressFor(toplevel) !== address) return null
    var ipc = handle.lastIpcObject || ({})
    if (ipc.pinned === true) return null
    var handles = currentHandles()
    for (var i = 0; i < handles.length; ++i) {
      var other = handles[i]
      if (other && other.wayland !== toplevel && isAlive(other.wayland)
          && DockModel.normalizeWindowAddress(other.address) === address)
        return null
    }
    // IPC wins over both stale object relationships and saved origins.
    var identity = DockWindowModel.workspaceIdentity(workspaceForHandle(handle))
    var minimized = identity === minimizedWorkspace
    var target = workspaceTarget(workspaceForHandle(handle))
    if (!minimized && (!target || identity.indexOf("special:") === 0
        || !DockModel.moveWindowRequest(address, target, false))) return null
    var origin = minimized ? originFor(address) : null
    return {
      toplevel: toplevel, address: address, minimized: minimized,
      workspace: minimized ? origin ? origin.workspace : "" : target,
      monitor: minimized ? origin ? origin.monitor : "" : monitorIdentity(handle)
    }
  }

  // null means an unsafe surviving member; [] means all captured objects closed.
  function workspaceMoveMembers(members) {
    var values = members || []
    var result = []
    var seen = []
    for (var i = 0; i < values.length; ++i) {
      var member = values[i]
      if (!member || !member.address) return null
      if (!isAlive(member.toplevel)) continue
      if (seen.indexOf(member.toplevel) >= 0) continue
      var location = workspaceMoveLocation(member.toplevel, member.address)
      if (!location) return null
      seen.push(member.toplevel)
      result.push(location)
    }
    return result
  }

  function resolveWorkspaceDropTarget(identity) {
    if (typeof identity !== "string"
        || DockWindowModel.workspaceIdentity(identity) !== identity) return null
    var target = identity.indexOf("id:") === 0 ? identity.slice(3) : identity
    if (!DockModel.moveWindowRequest("1", target, false)) return null
    var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values || [] : []
    var monitors = Hyprland.monitors ? Hyprland.monitors.values || [] : []
    var resolved = null
    for (var i = 0; i < workspaces.length; ++i) {
      var descriptor = workspaces[i]
      if (!descriptor || DockWindowModel.workspaceIdentity(descriptor) !== identity) continue
      var ipc = descriptor.lastIpcObject || descriptor
      if (identity.indexOf("name:") === 0) {
        var name = String(ipc.name !== undefined ? ipc.name : descriptor.name || "")
        if ((name.indexOf("name:") === 0 ? name : "name:" + name) !== target) return null
      }
      var owner = DockWindowModel.canonicalMonitorIdentity(
        ipc.monitorID !== undefined ? ipc.monitorID
          : ipc.monitor !== undefined ? ipc.monitor : descriptor.monitor, monitors)
      if (!owner || resolved && resolved.monitor !== owner) return null
      resolved = { identity: identity, target: target, monitor: owner }
    }
    return resolved
  }

  function workspaceMoveChangesLocation(member, destination) {
    if (DockModel.normalizeWorkspaceTarget(member.workspace) !== destination.target) return true
    if (!member.minimized) return false
    var monitors = Hyprland.monitors ? Hyprland.monitors.values || [] : []
    return DockWindowModel.canonicalMonitorIdentity(member.monitor, monitors) !== destination.monitor
  }

  function workspaceMoveWouldChange(members, identity) {
    var destination = resolveWorkspaceDropTarget(identity)
    var live = workspaceMoveMembers(members)
    if (!destination || !live) return false
    for (var i = 0; i < live.length; ++i) {
      if (workspaceMoveChangesLocation(live[i], destination)) return true
    }
    return false
  }

  function moveCapturedToplevels(members, workspaceIdentity) {
    var destination = resolveWorkspaceDropTarget(workspaceIdentity)
    var live = workspaceMoveMembers(members)
    if (!destination || !live || live.length === 0) return false
    // Complete preflight before the first side effect. This is a submission
    // result, not a compositor acknowledgement or an atomic multi-window move.
    var changed = false
    for (var i = 0; i < live.length; ++i) {
      destination = resolveWorkspaceDropTarget(workspaceIdentity)
      if (!destination) break
      var member = workspaceMoveLocation(live[i].toplevel, live[i].address)
      if (!member || !workspaceMoveChangesLocation(member, destination)) continue
      if (member.minimized) {
        changed = setOrigin(member.address, {
          workspace: destination.target, monitor: destination.monitor
        }) || changed
      } else {
        var request = DockModel.moveWindowRequest(
          member.address, destination.target, Hyprland.usingLua)
        if (dispatchRequest(request)) {
          forgetOrigin(member.address)
          changed = true
        }
      }
    }
    return changed
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

  function cycleToplevels(toplevels, direction, activeToplevel, originOnly) {
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
      minimizedOrigins = DockWindowModel.copyOriginSnapshot(retained)
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
