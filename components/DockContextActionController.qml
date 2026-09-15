import QtQuick
import Quickshell
import Quickshell.Hyprland
import "DockFullscreenModel.js" as FullscreenModel

Item {
  id: root

  required property var windowActions

  readonly property var applicationMutationController:
    root.windowActions ? root.windowActions.applicationMutationController : null
  readonly property string runtimeMode: root.applicationMutationController
    ? String(root.applicationMutationController.runtimeMode || "") : ""
  readonly property string instanceId: String(Quickshell.processId)

  visible: false
  width: 0
  height: 0

  function targetIsCurrent(targetContext) {
    if (!targetContext || !targetContext.toplevel || !root.windowActions)
      return false
    if (!root.windowActions.isAlive(targetContext.toplevel)) return false
    return String(root.windowActions.addressFor(targetContext.toplevel) || "")
      === String(targetContext.address || "")
  }

  function setFullscreenMode(targetContext, selectedMode) {
    if (!targetIsCurrent(targetContext)) return false
    var handle = root.windowActions.handleFor(targetContext.toplevel)
    if (!handle) return false
    var current = FullscreenModel.mode(handle.lastIpcObject || ({}))
    var next = FullscreenModel.targetMode(current, selectedMode)
    var request = FullscreenModel.request(
      targetContext.address, next, Hyprland.usingLua)
    return root.windowActions.dispatchRequest(request)
  }

  function representedToplevels(targetContexts) {
    var values = targetContexts || []
    var result = []
    for (var i = 0; i < values.length; ++i) {
      if (!targetIsCurrent(values[i])) return []
      result.push(values[i].toplevel)
    }
    return result
  }

  function minimizeVisible(targetContexts, originOnly) {
    var members = representedToplevels(targetContexts)
    if (members.length !== (targetContexts || []).length || members.length === 0)
      return false
    var changed = false
    for (var i = 0; i < members.length; ++i) {
      if (!root.windowActions.isMinimized(members[i]))
        changed = root.windowActions.minimizeToplevel(members[i], originOnly) || changed
    }
    return changed
  }

  function restoreMinimized(targetContexts, originOnly) {
    var members = representedToplevels(targetContexts)
    if (members.length !== (targetContexts || []).length || members.length === 0)
      return false
    var changed = false
    for (var i = 0; i < members.length; ++i) {
      if (root.windowActions.isMinimized(members[i]))
        changed = root.windowActions.restoreToplevel(members[i], originOnly) || changed
    }
    return changed
  }

  function closeRepresented(targetContexts) {
    var members = representedToplevels(targetContexts)
    if (members.length !== (targetContexts || []).length || members.length === 0)
      return false
    return root.windowActions.closeToplevels(members)
  }

  function mutateApplication(action, desktopId) {
    var controller = root.applicationMutationController
    var id = String(desktopId || "")
    if (!controller || !id) {
      return {
        ok: false,
        error: { code: "E_UNAVAILABLE", message: "Host application controller is unavailable." },
        data: { applied: false, persisted: false, writeState: "unavailable" }
      }
    }

    if (action === "pin" && typeof controller.pinApplication === "function")
      return controller.pinApplication(id)
    if (action === "unpin" && typeof controller.unpinApplication === "function")
      return controller.unpinApplication(id)
    if (action === "hide" && typeof controller.hideApplication === "function")
      return controller.hideApplication(id)

    return {
      ok: false,
      error: { code: "E_ACTION", message: "Unsupported application mutation." },
      data: { applied: false, persisted: false, writeState: "error" }
    }
  }

  function mutateWorkspaceGroup(action, desktopId, workspace) {
    var controller = root.applicationMutationController
    var id = String(desktopId || "")
    var target = String(workspace || "")
    if (!controller || !id || !target) {
      return {
        ok: false,
        error: { code: "E_UNAVAILABLE", message: "Host workspace-group controller is unavailable." },
        data: { applied: false, persisted: false, writeState: "unavailable" }
      }
    }
    if (action === "group" && typeof controller.groupWorkspaceApplication === "function")
      return controller.groupWorkspaceApplication(id, target)
    if (action === "ungroup" && typeof controller.ungroupWorkspaceApplication === "function")
      return controller.ungroupWorkspaceApplication(id, target)
    return {
      ok: false,
      error: { code: "E_ACTION", message: "Unsupported workspace-group mutation." },
      data: { applied: false, persisted: false, writeState: "error" }
    }
  }
}
