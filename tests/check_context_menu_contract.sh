#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/components/DockContextMenu.qml"
action="$repo_root/components/DockMenuAction.qml"
model="$repo_root/components/DockMenuModel.js"

status=0

fail() {
  printf 'FDM-939 context-menu contract: %s\n' "$1" >&2
  status=1
}

if grep -q 'autoTriggerOnHover:[[:space:]]*true' "$menu"; then
  fail 'hover must never trigger window selection or mutate the action target'
fi

if grep -q 'implicitWidth:.*400' "$menu"; then
  fail 'the application menu must not retain the 400px two-column layout'
fi

if grep -q '^[[:space:]]*Row[[:space:]]*{' "$menu"; then
  fail 'menu pages must render as one full-width column, not a side-by-side Row'
fi

if ! grep -q 'CursorSurface[[:space:]]*{' "$action"; then
  fail 'DockMenuAction must use Omarchy CursorSurface for shared cursor chrome'
fi

if ! grep -q 'PanelSeparator[[:space:]]*{' "$menu"; then
  fail 'DockContextMenu must use Omarchy PanelSeparator for dividers'
fi

if ! grep -q 'targetContext' "$menu"; then
  fail 'actions must carry explicit target context instead of relying on a mutable selected index'
fi

if ! grep -q 'ensureActiveVisible' "$menu"; then
  fail 'keyboard cursor movement must keep the selected row inside the viewport'
fi

if ! grep -q 'function agentRecord(id, title, kind, status, enabled, target)' "$model"; then
  fail 'agent rows must use the explicit agentRecord contract'
fi

if ! grep -q 'DockHerdrStatusMark[[:space:]]*{' "$menu"; then
  fail 'agent rows must reuse the shared Herdr status mark'
fi

if ! grep -q 'captureAgentTarget(agent.toplevel, agent)' "$menu"; then
  fail 'the menu must capture each exact Herdr target when it opens'
fi

if ! grep -q 'actions.activateHerdrTarget(record.target)' "$menu"; then
  fail 'agent activation must route only through DockHerdrAgentActions'
fi

if grep -Eq 'Go to waiting agent|AGENTS|send agent|steer agent|stop agent' "$menu"; then
  fail 'the menu must not add forbidden Herdr controls or labels'
fi

if ! grep -q 'text: "remote"' "$menu"; then
  fail 'disabled remote agent rows must show the plain remote tag'
fi

node "$repo_root/tests/test_context_menu_herdr_records.mjs" || status=1

exit "$status"
