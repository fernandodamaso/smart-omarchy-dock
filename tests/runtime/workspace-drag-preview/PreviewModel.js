.pragma library
.import "components/DockWorkspaceModel.js" as DockWorkspaceModel

function workspaceCompare(left, right) {
  return DockWorkspaceModel.workspaceCompare(left, right)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function monitorPinned(monitor, workspaceIdentity) {
  var pinned = monitor && monitor.pinnedWorkspaces ? monitor.pinnedWorkspaces : []
  return pinned.indexOf(workspaceIdentity) >= 0
}

function findWorkspace(fixtures, workspaceIdentity) {
  var workspaces = fixtures && fixtures.workspaces ? fixtures.workspaces : []
  for (var i = 0; i < workspaces.length; ++i) {
    if (workspaces[i] && workspaces[i].identity === workspaceIdentity)
      return workspaces[i]
  }
  return null
}

function findMonitor(fixtures, monitorIdentity) {
  var monitors = fixtures && fixtures.monitors ? fixtures.monitors : []
  for (var i = 0; i < monitors.length; ++i) {
    if (monitors[i] && monitors[i].identity === monitorIdentity)
      return monitors[i]
  }
  return null
}

function canMove(fixtures, workspaceIdentity, targetMonitor) {
  var workspace = findWorkspace(fixtures, workspaceIdentity)
  var monitor = findMonitor(fixtures, targetMonitor)
  if (!workspace || !monitor) return false
  if (String(workspace.owner || "") === String(targetMonitor || "")) return false
  if (monitorPinned(monitor, workspaceIdentity)) return false
  // Also reject when the workspace is pinned on its current owner for cross-monitor moves.
  var owner = findMonitor(fixtures, workspace.owner)
  if (owner && monitorPinned(owner, workspaceIdentity)) return false
  return true
}

function ownersFrom(workspaces) {
  var owners = {}
  for (var i = 0; i < workspaces.length; ++i) {
    var workspace = workspaces[i]
    if (!workspace || !workspace.identity) continue
    owners[workspace.identity] = String(workspace.owner || "")
  }
  return owners
}

function project(fixtures, drag) {
  var source = fixtures || { monitors: [], workspaces: [] }
  var monitors = clone(source.monitors || [])
  var workspaces = clone(source.workspaces || [])
  var owners = ownersFrom(workspaces)

  if (drag && drag.workspaceIdentity && drag.targetMonitor
      && canMove(source, drag.workspaceIdentity, drag.targetMonitor)) {
    for (var i = 0; i < workspaces.length; ++i) {
      if (workspaces[i].identity === drag.workspaceIdentity) {
        workspaces[i].owner = String(drag.targetMonitor)
        break
      }
    }
    owners = ownersFrom(workspaces)
  }

  var projected = []
  for (var m = 0; m < monitors.length; ++m) {
    var monitor = monitors[m]
    var section = clone(monitor)
    section.workspaces = workspaces.filter(function (workspace) {
      return workspace && workspace.owner === monitor.identity
    }).sort(workspaceCompare)
    projected.push(section)
  }

  return {
    monitors: projected,
    workspaceOwners: owners
  }
}

function commit(fixtures, workspaceIdentity, targetMonitor) {
  var next = clone(fixtures || { monitors: [], workspaces: [] })
  if (!canMove(next, workspaceIdentity, targetMonitor)) return next
  for (var i = 0; i < next.workspaces.length; ++i) {
    if (next.workspaces[i].identity === workspaceIdentity) {
      next.workspaces[i].owner = String(targetMonitor)
      break
    }
  }
  return next
}
