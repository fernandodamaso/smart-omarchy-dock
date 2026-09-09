#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_workspace_visual_hierarchy: %s\n' "$*" >&2
  exit 1
}

group=components/DockWorkspaceGroup.qml
[[ -f "$group" ]] || fail "missing $group"

grep -Fq 'HoverHandler { id: workspaceHover' "$group" \
  || fail 'workspace group must brighten as one surface on hover'
grep -Fq 'radius: Math.max(12, Style.cornerRadius - 4)' "$group" \
  || fail 'workspace cards must use a tighter nested radius than the dock surface'
grep -Fq 'active ? Util.alpha(Color.accent, workspaceHover.hovered ? 0.13 : 0.10)' "$group" \
  || fail 'active workspace surface must keep stronger accent hierarchy on hover'
grep -Fq 'border.color: urgent ? Color.urgent : active ? Util.alpha(Color.accent, 0.50)' "$group" \
  || fail 'active workspace border must be distinct without matching focused-app emphasis'
grep -Fq 'id: groupDivider' "$group" \
  || fail 'workspace label and application region need a subtle semantic divider'

grep -Fq 'text: root.displayLabel' "$group" \
  || fail 'visible workspace headers must use the compact label'
grep -Fq 'Accessible.name: root.label + ", "' "$group" \
  || fail 'accessible workspace names must preserve descriptive labels'
grep -Fq 'text: root.label + " — "' "$group" \
  || fail 'workspace tooltips must preserve descriptive labels'

echo 'check_workspace_visual_hierarchy: PASS'
