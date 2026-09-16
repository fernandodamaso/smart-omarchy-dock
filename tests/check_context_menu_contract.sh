#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/components/DockContextMenu.qml"
action="$repo_root/components/DockMenuAction.qml"

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

exit "$status"
