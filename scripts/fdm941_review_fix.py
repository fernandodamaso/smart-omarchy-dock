#!/usr/bin/env python3
from pathlib import Path


def replace_one(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    p.write_text(text.replace(old, new, 1))

replace_one(
    'components/DockConfigModel.js',
'''      var desktopId = storedIdentity(current, entries || [], args.desktopId)
      if (!DockWorkspaceGroupModel.persistedApplicationId(desktopId))
        return rejectedIntent("desktopId", "Application identity cannot be persisted canonically")
      list.push({ desktopId: desktopId, workspace: workspace })''',
'''      var entry = exactEntry(entries || [], desktopKey)
      var desktopId = entry && entry.id ? String(entry.id) : String(args.desktopId || "")
      if (!DockWorkspaceGroupModel.persistedApplicationId(desktopId))
        return rejectedIntent("desktopId", "Application identity cannot be persisted canonically")
      list.push({ desktopId: desktopId, workspace: workspace })''',
    'canonical workspace-group application identity')

replace_one(
    'components/DockContextMenu.qml',
'''  function candidateKeys(targetContext) {
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
  }''',
'''  function candidateSnapshotsEqual(left, right) {
    return DockMenuModel.targetSnapshotsEqual(left, right)
  }

  function captureGroupCandidateSnapshot() {
    if (root.controlItem || root.targetContexts.length !== 1 || !root.pageTarget) return []
    return root.workspaceGroupCandidates(root.pageTarget)
  }''',
    'exact workspace-group candidate snapshots')

replace_one(
    'components/DockContextMenu.qml',
    '    var current = root.candidateKeys(targetContext)\n',
    '    var current = root.workspaceGroupCandidates(targetContext)\n',
    'exact candidate revalidation')

replace_one(
    'components/DockContextMenu.qml',
    '          root.groupCandidateSnapshot, root.candidateKeys(root.pageTarget))) root.dismiss()\n',
    '          root.groupCandidateSnapshot, root.workspaceGroupCandidates(root.pageTarget))) root.dismiss()\n',
    'candidate membership invalidation')

print('FDM-941 review fixes applied')
