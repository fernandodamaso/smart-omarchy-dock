#!/usr/bin/env python3
from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one literal match, found {count}")
    return text.replace(old, new, 1)


def sub_one(text, pattern, replacement, label, flags=0):
    next_text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, found {count}")
    return next_text


# Fix the deliberate sequence in the behavioral fixture before checking that
# profile metadata is not a grouping dimension.
path = "tests/test_workspace_groups.mjs"
text = read(path)
text = replace_one(text,
    "A.browserProfileKey = 'Profile 1'\nE.browserProfileKey = 'Profile 2'",
    "handles[1].lastIpcObject.workspace = { id: 3 }\nA.browserProfileKey = 'Profile 1'\nE.browserProfileKey = 'Profile 2'",
    "workspace-group browser profile fixture")
write(path, text)

# Production dock: start from individual items, then combine only saved exact
# application/workspace pairs. The existing workspace model remains the owner
# of monitor/card partitioning.
path = "components/Dock.qml"
text = read(path)
text = replace_one(text,
    'import "DockWorkspaceModel.js" as WorkspaceModel\n',
    'import "DockWorkspaceModel.js" as WorkspaceModel\nimport "DockWorkspaceGroupModel.js" as WorkspaceGroupModel\n',
    "Dock workspace group import")
text = replace_one(text,
    '  readonly property bool groupWindows: DockModel.normalizeSetting(\n    "groupWindows", settings.groupWindows)\n',
    '  readonly property var workspaceGroups: WorkspaceGroupModel.normalizeWorkspaceGroups(\n    settings.workspaceGroups || [])\n',
    "Dock workspaceGroups property")
new_refresh = '''  function refreshVisibleItems() {
    if (root.workspaceDragActive) {
      root.workspacePresentationDirty = true
      return
    }
    if (groupedRequested) {
      var monitor = dockHyprMonitor
      var ipc = monitor ? monitor.lastIpcObject || monitor : ({})
      var records = toplevels.map(function(toplevel) {
        return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
          toplevel, hyprToplevels, windowActions ? windowActions.minimizedOriginsSnapshot : ({})))
      })
      var baseItems = DockModel.buildVisibleItems(
        pinned, toplevels, applications, hyprToplevels,
        false, false, hiddenApplications)
      var localizedItems = WorkspaceGroupModel.prepareWorkspaceItems(
        baseItems, records, workspaceGroups)
      var nextPresentation = WorkspaceModel.buildWorkspacePresentation(
        localizedItems, records, hyprWorkspaces, {
          monitor: DockWindowModel.monitorIdentity(monitor),
          monitorScope: workspaceMonitorScope,
          monitorOrder: workspaceMonitorOrder,
          activeWorkspace: workspaceMonitorScope === "all" ? focusedScopeWorkspace
            : DockWindowModel.workspaceIdentity(ipc.activeWorkspace
            || (monitor ? monitor.activeWorkspace : null)),
          monitors: hyprMonitors,
          groupWindows: false,
          workspaceGroups: workspaceGroups
        })
      nextPresentation = WorkspaceGroupModel.decorateWorkspacePresentation(
        nextPresentation, workspaceGroups)
      if (badgeTracker && screen)
        badgeTracker.syncWorkspaceScopes(screen.name,
          nextPresentation.groups.reduce(function(items, group) {
            return items.concat(group.items)
          }, []).concat(nextPresentation.globalLaunchers, nextPresentation.fallbackItems))
      if (!WorkspaceModel.presentationsEqual(workspacePresentation, nextPresentation)) {
        windowPreview.dismissImmediately()
        workspacePresentation = nextPresentation
      }
    }
    var flatRecords = filteredToplevels.map(function(toplevel) {
      return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
        toplevel, hyprToplevels, windowActions ? windowActions.minimizedOriginsSnapshot : ({})))
    })
    var flatBaseItems = DockModel.buildVisibleItems(
      pinned, filteredToplevels, applications, hyprToplevels, false,
      false, hiddenApplications)
    var nextItems = WorkspaceGroupModel.buildFlatPresentation(
      flatBaseItems, flatRecords, workspaceGroups, sortByWorkspace)
    if (!DockModel.visibleItemsEqual(visibleItems, nextItems)) {
      windowPreview.dismissImmediately()
      visibleItems = nextItems
    }
    if (root.revealAfterWorkspaceDrag) {
      root.revealAfterWorkspaceDrag = false
      Qt.callLater(root.revealActiveWorkspace)
    }
  }

  function scheduleVisibleItemsRefresh()'''
text = sub_one(text,
    r'  function refreshVisibleItems\(\) \{\n.*?\n  \}\n\n  function scheduleVisibleItemsRefresh\(\)',
    new_refresh,
    "Dock refreshVisibleItems", re.S)
text = replace_one(text,
    '  onGroupWindowsChanged: root.scheduleVisibleItemsRefresh()\n',
    '  onWorkspaceGroupsChanged: {\n    if (windowPreview) windowPreview.dismissImmediately()\n    root.scheduleVisibleItemsRefresh()\n  }\n',
    "Dock workspace group change handler")
if "groupWindows: groupWindows" in text:
    raise RuntimeError("legacy global grouping still drives Dock presentation")
write(path, text)

# Effective CLI projection explicitly reports the legacy Boolean as inactive
# while requested readback preserves any stored legacy value.
path = "components/DockControl.qml"
text = read(path)
text = replace_one(text,
    'import "DockConfigModel.js" as ConfigModel\n',
    'import "DockConfigModel.js" as ConfigModel\nimport "DockWorkspaceGroupModel.js" as WorkspaceGroupModel\n',
    "DockControl workspace group import")
text = replace_one(text,
    '    result.iconOverrides = ConfigModel.effectiveIcons(requested.iconOverrides)\n',
    '    result.iconOverrides = ConfigModel.effectiveIcons(requested.iconOverrides)\n    result.workspaceGroups = WorkspaceGroupModel.normalizeWorkspaceGroups(\n      requested.workspaceGroups === undefined ? root.defaults.workspaceGroups : requested.workspaceGroups)\n    result.groupWindows = false\n',
    "DockControl effective legacy projection")
write(path, text)

# DockHost remains the sole persistence writer. Both menu intents are computed
# against root.settings at invocation time, then flow through commitSettings.
path = "DockHost.qml"
text = read(path)
text = replace_one(text,
'''  function hideApplication(desktopId) {
    return changeApplication("hide", { id: desktopId })
  }

  function toggleBrowserActivityMute(serviceId) {''',
'''  function hideApplication(desktopId) {
    return changeApplication("hide", { id: desktopId })
  }

  function groupWorkspaceApplication(desktopId, workspace) {
    return changeWorkspaceGroup("group", desktopId, workspace)
  }

  function ungroupWorkspaceApplication(desktopId, workspace) {
    return changeWorkspaceGroup("ungroup", desktopId, workspace)
  }

  function changeWorkspaceGroup(action, desktopId, workspace) {
    var blocked = mutationBlocked()
    if (blocked) return blocked
    return commitSettings(ConfigModel.workspaceGroupIntent(
      settings, applications, action,
      { desktopId: desktopId, workspace: workspace }), false)
  }

  function toggleBrowserActivityMute(serviceId) {''',
    "DockHost workspace group writer intents")
write(path, text)

# Menu adapter delegates group persistence exactly like existing app mutations.
path = "components/DockContextActionController.qml"
text = read(path)
text = replace_one(text,
'''    return {
      ok: false,
      error: { code: "E_ACTION", message: "Unsupported application mutation." },
      data: { applied: false, persisted: false, writeState: "error" }
    }
  }
}''',
'''    return {
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
}''',
    "context action workspace group delegation")
write(path, text)

# Context menu: grouping is explicit, workspace-local, and target-safe. Candidate
# membership is snapshotted on open; any global membership/config change
# invalidates the menu, and execution revalidates the exact address set.
path = "components/DockContextMenu.qml"
text = read(path)
text = replace_one(text,
    'import "DockFullscreenModel.js" as FullscreenModel\n',
    'import "DockFullscreenModel.js" as FullscreenModel\nimport "DockWorkspaceGroupModel.js" as WorkspaceGroupModel\n',
    "context menu workspace group import")
text = replace_one(text,
    '  property string pendingClipboardText: ""\n',
    '  property string pendingClipboardText: ""\n  property var groupCandidateSnapshot: []\n  property string openedWorkspaceGroupsSignature: ""\n',
    "context menu group snapshot properties")
text = replace_one(text,
'''  readonly property var applicationMutationController:
    contextActions.applicationMutationController
  readonly property var selectedHandle:''',
'''  readonly property var applicationMutationController:
    contextActions.applicationMutationController
  readonly property var workspaceGroups: WorkspaceGroupModel.normalizeWorkspaceGroups(
    root.applicationMutationController && root.applicationMutationController.settings
      ? root.applicationMutationController.settings.workspaceGroups || [] : [])
  readonly property var selectedHandle:''',
    "context menu current workspace groups")
text = replace_one(text,
'''    root.pageTarget = root.targetContexts.length === 1
      ? root.targetContexts[0] : null
    root.page = DockMenuModel.initialPage(''',
'''    root.pageTarget = root.targetContexts.length === 1
      ? root.targetContexts[0] : null
    root.groupCandidateSnapshot = root.captureGroupCandidateSnapshot()
    root.openedWorkspaceGroupsSignature = root.workspaceGroupsSignature()
    root.page = DockMenuModel.initialPage(''',
    "context menu group snapshot capture")
text = replace_one(text,
'''    root.pendingMutationLabel = ""
    root.copyProfileDirectory = ""
  }

  function targetContextFor''',
'''    root.pendingMutationLabel = ""
    root.copyProfileDirectory = ""
    root.groupCandidateSnapshot = []
    root.openedWorkspaceGroupsSignature = ""
  }

  function targetContextFor''',
    "context menu group snapshot cleanup")
helpers = '''  function workspaceIdentityForToplevel(toplevel) {
    if (!toplevel || !root.windowActions || !root.windowActions.isAlive(toplevel)) return ""
    var state = root.windowState(toplevel)
    return WorkspaceGroupModel.canonicalWorkspaceTarget(state ? state.workspace : "")
  }

  function candidateMatchesApplication(toplevel) {
    if (!toplevel || !root.desktopId) return false
    var entries = DesktopEntries.applications.values || []
    var appId = DockModel.toplevelAppId(toplevel, entries)
    var entry = DockModel.entryForDesktopId(root.desktopId, entries)
    return DockModel.entryMatchesAppId(root.desktopId, entry, appId)
  }

  function workspaceGroupCandidates(targetContext) {
    if (!targetContext || !root.targetIsValid(targetContext)) return []
    var workspace = root.workspaceIdentityForToplevel(targetContext.toplevel)
    if (!workspace) return []
    var live = root.windowActions.currentToplevels()
    var candidates = []
    for (var i = 0; i < live.length; ++i) {
      var toplevel = live[i]
      if (!root.windowActions.isAlive(toplevel)
          || !root.candidateMatchesApplication(toplevel)
          || root.workspaceIdentityForToplevel(toplevel) !== workspace) continue
      var address = String(root.windowActions.addressFor(toplevel) || "")
      if (!address) return []
      candidates.push({ toplevel: toplevel, address: address, key: "address:" + address })
    }
    candidates.sort(function(left, right) {
      return left.key < right.key ? -1 : left.key > right.key ? 1 : 0
    })
    return candidates
  }

  function candidateKeys(targetContext) {
    return root.workspaceGroupCandidates(targetContext).map(function(candidate) {
      return candidate.key
    })
  }

  function candidateSnapshotsEqual(left, right) {
    var a = left || []
    var b = right || []
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; ++i)
      if (a[i] !== b[i]) return false
    return true
  }

  function captureGroupCandidateSnapshot() {
    if (root.controlItem || root.targetContexts.length !== 1 || !root.pageTarget) return []
    return root.candidateKeys(root.pageTarget)
  }

  function representedWorkspaceIdentity() {
    if (!root.allTargetsAreValid()) return ""
    var identity = ""
    for (var i = 0; i < root.targetContexts.length; ++i) {
      var current = root.workspaceIdentityForToplevel(root.targetContexts[i].toplevel)
      if (!current) return ""
      if (!identity) identity = current
      else if (identity !== current) return ""
    }
    return identity
  }

  function workspaceGroupsSignature() {
    return JSON.stringify(root.workspaceGroups)
  }

  function representedWorkspaceGrouped() {
    var workspace = root.representedWorkspaceIdentity()
    return workspace !== "" && WorkspaceGroupModel.workspaceGroupEnabled(
      root.workspaceGroups, root.desktopId, workspace)
  }

  function canGroupTarget(targetContext) {
    if (!targetContext || root.targetContexts.length !== 1
        || targetContext !== root.pageTarget || !root.targetIsValid(targetContext)) return false
    var workspace = root.workspaceIdentityForToplevel(targetContext.toplevel)
    if (!workspace || WorkspaceGroupModel.workspaceGroupEnabled(
        root.workspaceGroups, root.desktopId, workspace)) return false
    var current = root.candidateKeys(targetContext)
    return root.groupCandidateSnapshot.length >= 2
      && root.candidateSnapshotsEqual(root.groupCandidateSnapshot, current)
  }

'''
text = replace_one(text,
    '  function profileDirectoryForTarget(targetContext) {',
    helpers + '  function profileDirectoryForTarget(targetContext) {',
    "context menu workspace group helpers")
mutation = '''  function workspaceGroupMutationLabel(action) {
    return action === "group" ? "Group Windows" : "Ungroup"
  }

  function runWorkspaceGroupMutation(action, targetContext) {
    var workspace = action === "group"
      ? root.workspaceIdentityForToplevel(targetContext ? targetContext.toplevel : null)
      : root.representedWorkspaceIdentity()
    if (action === "group" && !root.canGroupTarget(targetContext)) {
      root.dismiss()
      return false
    }
    if (action === "ungroup" && !root.representedWorkspaceGrouped()) {
      root.dismiss()
      return false
    }
    if (!workspace) {
      root.dismiss()
      return false
    }
    var reply = contextActions.mutateWorkspaceGroup(action, root.desktopId, workspace)
    var presentation = DockMenuModel.mutationPresentation(reply)
    var label = root.workspaceGroupMutationLabel(action)
    root.feedbackTitle = label
    if (presentation.state === "saved") {
      root.feedbackText = label + " saved."
      root.pendingMutationAction = ""
      root.pendingMutationLabel = ""
      return true
    }
    if (presentation.state === "pending") {
      root.feedbackText = label + " applied for this session; saving…"
      root.pendingMutationAction = action
      root.pendingMutationLabel = label
      return true
    }
    root.feedbackText = presentation.message
    root.pendingMutationAction = ""
    root.pendingMutationLabel = ""
    return false
  }

'''
text = replace_one(text,
    '  function refreshPendingMutationFeedback() {',
    mutation + '  function refreshPendingMutationFeedback() {',
    "context menu group mutation runner")
text = replace_one(text,
'''    var records = [
      DockMenuModel.headerRecord("app:header", root.applicationName, subtitle)
    ]

    if (total > 1) {''',
'''    var records = [
      DockMenuModel.headerRecord("app:header", root.applicationName, subtitle)
    ]

    if (root.representedWorkspaceGrouped()) {
      records.push(DockMenuModel.actionRecord(
        "app:ungroup", "Ungroup", "", true,
        "ungroup-windows", null))
      records.push(DockMenuModel.separatorRecord("app:ungroup-separator"))
    }

    if (total > 1) {''',
    "grouped app Ungroup action")
text = replace_one(text,
'''    records.push(DockMenuModel.actionRecord(
      "window:workspace", "Move to Workspace…", "arrow-right-left",
      addressValid, "open-workspaces-page", target, { submenu: true }))
    records.push(DockMenuModel.actionRecord(
      "window:fullscreen-keep-bars",''',
'''    records.push(DockMenuModel.actionRecord(
      "window:workspace", "Move to Workspace…", "arrow-right-left",
      addressValid, "open-workspaces-page", target, { submenu: true }))
    if (root.representedWorkspaceGrouped()) {
      records.push(DockMenuModel.actionRecord(
        "window:ungroup", "Ungroup", "", valid,
        "ungroup-windows", target))
    } else if (root.canGroupTarget(target)) {
      records.push(DockMenuModel.actionRecord(
        "window:group", "Group Windows", "", true,
        "group-windows", target))
    }
    records.push(DockMenuModel.actionRecord(
      "window:fullscreen-keep-bars",''',
    "individual Group Windows action")
text = replace_one(text,
'''    case "restore-minimized": return root.representedAction("restore-minimized")
    case "close-represented": return root.representedAction("close-represented")
    case "close-window":''',
'''    case "restore-minimized": return root.representedAction("restore-minimized")
    case "close-represented": return root.representedAction("close-represented")
    case "group-windows": return root.runWorkspaceGroupMutation("group", targetContext)
    case "ungroup-windows": return root.runWorkspaceGroupMutation("ungroup", targetContext)
    case "close-window":''',
    "context menu group dispatch")
text = replace_one(text,
'''  Connections {
    target: root.applicationMutationController
    function onSettingsWriteStateChanged() { root.refreshPendingMutationFeedback() }
    function onSettingsPersistedChanged() { root.refreshPendingMutationFeedback() }
    function onSettingsWriteErrorChanged() { root.refreshPendingMutationFeedback() }
  }
}''',
'''  Connections {
    target: root.applicationMutationController
    function onSettingsWriteStateChanged() { root.refreshPendingMutationFeedback() }
    function onSettingsPersistedChanged() { root.refreshPendingMutationFeedback() }
    function onSettingsWriteErrorChanged() { root.refreshPendingMutationFeedback() }
    function onSettingsChanged() {
      if (root.visible && root.workspaceGroupsSignature()
          !== root.openedWorkspaceGroupsSignature) root.dismiss()
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      if (!root.visible || root.targetContexts.length !== 1 || !root.pageTarget) return
      if (!root.candidateSnapshotsEqual(
          root.groupCandidateSnapshot, root.candidateKeys(root.pageTarget))) root.dismiss()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.visible || !event) return
      var name = String(event.name || "")
      if (["openwindow", "closewindow", "movewindow", "movewindowv2"].indexOf(name) >= 0)
        root.dismiss()
    }
  }
}''',
    "context menu stale grouping invalidation")
write(path, text)

# CLI-facing docs: 45 settings, local opt-in grouping, and explicit legacy behavior.
path = "docs/CONFIGURATION.md"
text = read(path)
text = replace_one(text,
    'checks these 44 rows against the shipped defaults.',
    'checks these 45 rows against the shipped defaults.',
    "configuration row count")
text = replace_one(text,
    '| `groupWindows` | `true` | Boolean; group an application\'s windows; applies in both layouts. |',
    '| `groupWindows` | `false` | Deprecated/inactive compatibility Boolean. Stored legacy `true` is preserved on read and unrelated writes but never changes presentation; new attempts to enable it are rejected. |\n| `workspaceGroups` | `[]` | Strict opt-in `{desktopId, workspace}` pairs. Workspace identities are canonical `id:N` or safe `name:N`; duplicate pairs and ambiguous/special identities are rejected atomically. |',
    "configuration grouping rows")
text = replace_one(text,
    'New pointer writes require canonical values; stored legacy `focus`/`launch` aliases read effectively as `focus-or-launch` without an unrelated rewrite.\n',
    'New pointer writes require canonical values; stored legacy `focus`/`launch` aliases read effectively as `focus-or-launch` without an unrelated rewrite. Stored legacy `groupWindows: true` remains visible in requested readback but its effective value is always false; no startup rewrite or automatic local-group migration occurs. Use `workspaceGroups` or the context-menu **Group Windows** action instead.\n',
    "requested/effective legacy grouping docs")
text = replace_one(text,
    'Workspace cards and window filtering are different features.',
    'Workspace groups are opt-in per canonical application/workspace pair and never span workspaces. A saved pair survives empty workspaces and restart, new arrivals join automatically, moved windows follow the destination policy, minimized windows retain membership through their recorded origin, and unresolved/special workspace membership remains individual. Browser profile metadata does not create a second grouping dimension.\n\nWorkspace cards and window filtering are different features.',
    "workspace grouping behavior docs")
text = replace_one(text,
    '`workspaceMonitorOrder` is an ordinary preference, so preference reset and `config reset workspaceMonitorOrder` both restore `[]` automatic ordering.',
    '`workspaceMonitorOrder` and `workspaceGroups` are ordinary preferences, so preference reset restores automatic monitor ordering and clears local grouping pairs; `config reset workspaceMonitorOrder` and `config reset workspaceGroups` reset only their exact keys.',
    "workspaceGroups reset docs")
write(path, text)

# Strengthen the structural gate for effective readback and stale-menu defense.
path = "tests/check_workspace_groups.sh"
text = read(path)
text = replace_one(text,
'''grep -q 'mutateWorkspaceGroup' components/DockContextActionController.qml \\
  || fail 'menu grouping must delegate through the host controller'

echo 'CM-03 workspace-group structural contract: PASS'
''',
'''grep -q 'mutateWorkspaceGroup' components/DockContextActionController.qml \\
  || fail 'menu grouping must delegate through the host controller'
grep -q 'result.groupWindows = false' components/DockControl.qml \\
  || fail 'effective CLI readback must report legacy global grouping inactive'
grep -q 'groupCandidateSnapshot' components/DockContextMenu.qml \\
  || fail 'Group Windows must snapshot exact eligible membership'
grep -q 'onSettingsChanged' components/DockContextMenu.qml \\
  || fail 'workspace-group settings changes must invalidate an open menu'
grep -q 'target: ToplevelManager.toplevels' components/DockContextMenu.qml \\
  || fail 'candidate membership changes must invalidate an open menu'

echo 'CM-03 workspace-group structural contract: PASS'
''',
    "workspace group structural hardening")
write(path, text)

print("FDM-941 source integration applied")
