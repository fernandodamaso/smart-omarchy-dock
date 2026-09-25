#!/usr/bin/env bash
set -euo pipefail

dock="components/Dock.qml"
new_workspace="components/DockNewWorkspaceDropTarget.qml"
drag="components/DockWorkspaceDrag.qml"
actions="components/DockWindowActions.qml"

[[ -f "$new_workspace" ]]

# Pinning lives in the Dock Controls menu; no standalone + slot in the dock.
! rg -q 'DockAddPinItem' "$dock"
[[ ! -f components/DockAddPinItem.qml ]]

# Monitor prefixes carry information only when multiple live monitors exist.
rg -q 'showMonitorPrefixes:\s*hyprMonitors\.length > 1' "$dock"
rg -q 'hasMonitorPrefix:\s*root\.showMonitorPrefixes' "$dock"

# Grouped window dragging exposes a transient end-of-monitor destination and
# routes it through the shared exact-capture action controller.
rg -q 'DockNewWorkspaceDropTarget \{' "$dock"
rg -q 'function newWorkspaceMonitorForCard\(' "$dock"
rg -q 'function newWorkspaceDropMonitorAt\(' "$dock"
rg -q 'newWorkspaceTargetAtScenePoint:\s*root\.newWorkspaceDropMonitorAt' "$dock"
rg -q 'hoveredNewWorkspaceMonitor' "$drag"
rg -q 'canMoveCapturedToplevelsToNewWorkspace' "$drag"
rg -q 'moveCapturedToplevelsToNewWorkspace' "$drag"
rg -q 'function canMoveCapturedToplevelsToNewWorkspace\(' "$actions"
rg -q 'function moveCapturedToplevelsToNewWorkspace\(' "$actions"
rg -q 'moveCapturedToplevelsToNewWorkspaceResult\(members, monitorIdentity\)\.accepted === true' "$actions"
rg -q 'moveCapturedWindowToNewWorkspaceResult\(member, monitorIdentity\)\.accepted === true' "$actions"
rg -q 'moveCapturedToplevelsToNewWorkspaceResult\(\[member\], monitorIdentity\)' "$actions"
rg -q 'text:\s*"New workspace"' "$new_workspace"
rg -q 'iconName:\s*"plus"' "$new_workspace"
! rg -q 'TapHandler|MouseArea|DragHandler' "$new_workspace"

echo "dock quick actions structural contract: PASS"
