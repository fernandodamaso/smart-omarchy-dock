#!/usr/bin/env bash
set -euo pipefail

dock="components/Dock.qml"
add_pin="components/DockAddPinItem.qml"
new_workspace="components/DockNewWorkspaceDropTarget.qml"
drag="components/DockWorkspaceDrag.qml"
actions="components/DockWindowActions.qml"

[[ -f "$add_pin" ]]
[[ -f "$new_workspace" ]]

# A dedicated, always-visible pin affordance sits beside Dock Controls and owns
# the app-picker anchor instead of hiding pinning exclusively in the menu.
rg -q 'DockAddPinItem \{' "$dock"
rg -q 'id:\s*addPinItem' "$dock"
rg -q 'onActivated:\s*root\.openAppPicker\(addPinItem\)' "$dock"
rg -q 'anchorItem:\s*addPinItem' "$dock"
rg -q 'objectName:\s*"dock-add-pin"' "$add_pin"
rg -q 'Accessible\.name:\s*"Add pinned application"' "$add_pin"
rg -q 'iconName:\s*"plus"' "$add_pin"

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
rg -q 'moveCapturedToplevelsToNewWorkspace\(\[member\], monitorIdentity\)' "$actions"
rg -q 'text:\s*"New workspace"' "$new_workspace"
rg -q 'iconName:\s*"plus"' "$new_workspace"
! rg -q 'TapHandler|MouseArea|DragHandler' "$new_workspace"

echo "dock quick actions structural contract: PASS"
