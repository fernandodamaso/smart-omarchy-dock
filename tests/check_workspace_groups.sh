#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'CM-03 workspace grouping contract failed: %s\n' "$1" >&2
  exit 1
}

python3 - <<'PY'
import json
from pathlib import Path

defaults = json.loads(Path('config/dock.json').read_text())
schema = json.loads(Path('config/settings-schema.json').read_text())['settings']
assert 'workspaceGroups' in defaults and defaults['workspaceGroups'] == []
assert 'workspaceGroups' in schema
assert schema['workspaceGroups'].get('type') == 'array'
assert schema['workspaceGroups'].get('format') == 'workspace-groups'
assert defaults.get('groupWindows') is False
legacy = schema['groupWindows']
assert legacy.get('deprecated') is True
assert legacy.get('inactive') is True
assert legacy.get('replacement') == 'workspaceGroups'
PY

grep -q 'function workspaceGroupIntent' components/DockConfigModel.js \
  || fail 'DockConfigModel must own exact pair mutation'
grep -q 'var entry = exactEntry(entries || \[\], desktopKey)' components/DockConfigModel.js \
  || fail 'new group pairs must canonicalize through the exact desktop entry'
grep -q 'function groupWorkspaceApplication' DockHost.qml \
  || fail 'DockHost must expose the group intent through the sole settings writer'
grep -q 'function ungroupWorkspaceApplication' DockHost.qml \
  || fail 'DockHost must expose exact-pair ungrouping'
grep -q 'workspaceGroups' components/Dock.qml \
  || fail 'Dock must consume workspaceGroups'
grep -q 'buildFlatPresentation' components/Dock.qml \
  || fail 'flat layout must use workspace-local representation'
grep -q 'workspaceGroups: workspaceGroups' components/Dock.qml \
  || fail 'workspace-card layout must receive the saved local policy'
grep -q 'WorkspaceModel.monitorGroupForWorkspace' components/Dock.qml \
  || fail 'FDM-948 inline monitor sections must remain integrated with local grouping'
grep -q 'DockMonitorLabel' components/Dock.qml \
  || fail 'FDM-948 monitor section labels must survive CM-03 reconciliation'
if grep -q 'groupWindows: groupWindows' components/Dock.qml; then
  fail 'production workspace-card rendering must not receive legacy global grouping'
fi
grep -q 'Group Windows' components/DockContextMenu.qml \
  || fail 'eligible individual-window menus must expose Group Windows'
grep -q 'Ungroup' components/DockContextMenu.qml \
  || fail 'saved local groups must expose Ungroup'
grep -q 'mutateWorkspaceGroup' components/DockContextActionController.qml \
  || fail 'menu grouping must delegate through the host controller'
grep -q 'result.groupWindows = false' components/DockControl.qml \
  || fail 'effective CLI readback must report legacy global grouping inactive'
grep -q 'function targetSnapshotsEqual' components/DockMenuModel.js \
  || fail 'candidate snapshots must compare exact object and address identity'
grep -q 'function initialPage(controlItem, targetCount, preferredTargetValid, groupedRepresentation)' components/DockMenuModel.js \
  || fail 'menu routing must distinguish a persisted group from an ordinary single window'
grep -q 'DockMenuModel.targetSnapshotsEqual' components/DockContextMenu.qml \
  || fail 'Group Windows must revalidate the exact captured candidate set'
grep -q 'groupCandidateSnapshot' components/DockContextMenu.qml \
  || fail 'Group Windows must snapshot exact eligible membership'
grep -q 'onSettingsChanged' components/DockContextMenu.qml \
  || fail 'workspace-group settings changes must invalidate an open menu'
grep -q 'target: ToplevelManager.toplevels' components/DockContextMenu.qml \
  || fail 'candidate membership changes must invalidate an open menu'
grep -q 'root.representedWorkspaceGrouped())' components/DockContextMenu.qml \
  || fail 'a saved one-member group must still open the group/application menu'
grep -q "WorkspaceGroupModel: loadModel('DockWorkspaceGroupModel.js')" tests/test_cli_host.mjs \
  || fail 'CLI host harness must load the workspace-group dependency'
grep -q "WorkspaceGroupModel: loadModel('DockWorkspaceGroupModel.js')" tests/test_config_model.mjs \
  || fail 'writer harness must load the workspace-group dependency'
grep -q 'loading stored legacy grouping must not rewrite configuration' tests/test_config_model.mjs \
  || fail 'host lifecycle must prove legacy grouping loads without migration writes'
grep -q "config.get', { key: 'groupWindows', effective: true" tests/test_config_model.mjs \
  || fail 'host lifecycle must prove requested/effective legacy readback differs'

echo 'CM-03 workspace-group structural contract: PASS'
