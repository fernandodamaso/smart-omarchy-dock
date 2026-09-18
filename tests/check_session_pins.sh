#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "session pin contract: FAIL: $*" >&2
  exit 1
}

ACTIONS=components/DockWindowActions.qml
MENU=components/DockContextMenu.qml
DRAG=components/DockWorkspaceDrag.qml
DOC=README.md

for needle in \
  'property var windowWorkspacePins' \
  'property var workspaceMonitorPins' \
  'function pinWindowToWorkspace' \
  'function unpinWindowFromWorkspace' \
  'function canMoveToplevelToWorkspace' \
  'function moveToplevelToWorkspace' \
  'function pinWorkspaceToMonitor' \
  'function unpinWorkspaceFromMonitor' \
  'function canRelocateWorkspaceToMonitor' \
  'function reconcileSessionPins'; do
  grep -q "$needle" "$ACTIONS" || fail "missing shared controller contract: $needle"
done

grep -q 'if (workspaceMonitorPin(workspace)) return \[focusRequest\]' "$ACTIONS" \
  || fail 'workspace activation must focus a monitor-pinned workspace in place'
grep -q 'canMoveToplevelToWorkspace(live\[i\].toplevel, destination.identity)' "$ACTIONS" \
  || fail 'drag hover must reject a represented payload containing a pinned member'
grep -q 'canMoveToplevelToWorkspace(member.toplevel, destination.identity)' "$ACTIONS" \
  || fail 'drag drop must recheck session pins immediately before movement'

if grep -Eq 'settings\.(windowWorkspacePins|workspaceMonitorPins)' "$ACTIONS" DockHost.qml components/*.qml; then
  fail 'session pins must not be persisted through settings'
fi

grep -q 'windowActions.moveToplevelToWorkspace' "$MENU" \
  || fail 'context-menu workspace moves must delegate to the shared controller'
move_body="$(sed -n '/function moveTargetToWorkspace(/,/^  }/p' "$MENU")"
if grep -Eq 'DockModel\.moveWindowRequest|Hyprland\.dispatch' <<<"$move_body"; then
  fail 'context-menu workspace moves must not retain a direct compositor bypass'
fi
grep -q '"pin-window-workspace"' "$MENU" \
  || fail 'individual window menu must expose session pin action'
grep -q '"unpin-window-workspace"' "$MENU" \
  || fail 'individual window menu must expose session unpin action'

grep -q 'workspaceMoveWouldChange(members, destination.identity)' "$DRAG" \
  || fail 'drag hover must use the central movement guard'
grep -q 'moveCapturedToplevels(members, hoveredIdentity, true)' "$DRAG" \
  || fail 'drag drop must use the central movement guard'

grep -q 'session-only movement pins' "$DOC" \
  || fail 'user documentation must describe the session-only lifetime'
grep -q 'External Hyprland shortcuts/tools remain free' "$DOC" \
  || fail 'documentation must preserve external compositor authority'

echo 'CM-04 central session pin structural contract: PASS'
