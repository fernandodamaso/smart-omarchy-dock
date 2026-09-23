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

! grep -Fq 'groupDivider' "$group" \
  || fail 'workspace groups must not reintroduce a groupDivider separator'

grep -Fq 'HoverHandler { id: workspaceHover' "$group" \
  || fail 'workspace group must brighten as one surface on hover'
grep -Fq 'id: surface' "$group" \
  || fail 'workspace pill must render through the shared surface rectangle'
grep -Fq 'property bool monitorFocused' "$group" \
  || fail 'workspace group must track monitor focus for border emphasis'

surface_block="$(sed -n '/id: surface/,/Behavior on color/p' "$group")"
[[ -n "$surface_block" ]] || fail 'workspace pill must render through the shared surface rectangle'
surface_flat="$(printf '%s\n' "$surface_block" | tr '\n' ' ' | tr -s '[:space:]' ' ')"

title_block="$(sed -n '/id: title/,/Behavior on color/p' "$group")"
[[ -n "$title_block" ]] || fail 'workspace header must render through the title text item'
title_flat="$(printf '%s\n' "$title_block" | tr '\n' ' ' | tr -s '[:space:]' ' ')"

grep -Fq 'radius: Math.max(12, Style.cornerRadius - 4)' <<<"$surface_block" \
  || fail 'workspace cards must use a tighter nested radius than the dock surface'
grep -Fq 'root.active && root.monitorFocused ? Util.alpha(Color.accent, workspaceHover.hovered ? 0.13 : 0.10)' <<<"$surface_block" \
  || fail 'active workspace surface must keep stronger accent hierarchy on hover'
grep -Fq 'root.dropHighlighted ? Util.alpha(Color.accent, 0.24)' <<<"$surface_block" \
  || fail 'drag destination workspace surface must keep accent fill hierarchy'

grep -Fq 'border.width: (root.dropHighlighted || root.urgent || (root.active && root.monitorFocused)) ? 1 : 0' <<<"$surface_block" \
  || fail 'workspace border width must be conditional on dropHighlighted || urgent || active && monitorFocused'
grep -Fq '? 1 : 0' <<<"$surface_block" \
  || fail 'inactive non-urgent workspace pill must have no border'
grep -Fq 'border.color: root.dropHighlighted ? Color.accent' <<<"$surface_flat" \
  || fail 'a valid drag destination needs a transient border highlight'
grep -Fq 'root.urgent ? Color.urgent' <<<"$surface_flat" \
  || fail 'urgent workspace border must use the urgent color'
grep -Fq '(root.active && root.monitorFocused) ? Util.alpha(Color.accent, 0.50)' <<<"$surface_flat" \
  || fail 'focused active workspace border must keep distinct accent emphasis'
grep -Fq ': "transparent"' <<<"$surface_flat" \
  || fail 'inactive non-urgent workspace pill must fall back to a transparent border color'
grep -Fq 'border.color: root.dropHighlighted ? Color.accent : root.urgent ? Color.urgent : (root.active && root.monitorFocused) ? Util.alpha(Color.accent, 0.50) : "transparent"' <<<"$surface_flat" \
  || fail 'surface border color must map drop -> accent, urgent -> urgent, focused-active -> accent 50%, else transparent'

grep -Fq 'color: root.active && root.monitorFocused ? Color.accent' <<<"$title_flat" \
  || fail 'focused active workspace title must use the accent color'
grep -Fq 'root.active ? Util.alpha(Color.accent, 0.6) : Color.foreground' <<<"$title_flat" \
  || fail 'unfocused workspace titles must fall back through the title color mapping'

grep -Fq 'text: root.displayLabel' "$group" \
  || fail 'visible workspace headers must use the compact label'
grep -Fq 'Accessible.name: root.label + ", "' "$group" \
  || fail 'accessible workspace names must preserve descriptive labels'
grep -Fq 'text: root.label + " — "' "$group" \
  || fail 'workspace tooltips must preserve descriptive labels'

echo 'check_workspace_visual_hierarchy: PASS'
