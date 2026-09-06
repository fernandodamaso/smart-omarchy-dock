#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
dock="$project_root/components/Dock.qml"

fail() {
  printf 'check_visible_items_snapshot: %s\n' "$1" >&2
  exit 1
}

grep -Fq 'property var visibleItems: []' "$dock" \
  || fail 'visibleItems must be an imperative snapshot'
grep -Fq 'function refreshVisibleItems()' "$dock" \
  || fail 'visibleItems refresh helper missing'
grep -Fq 'function scheduleVisibleItemsRefresh()' "$dock" \
  || fail 'visibleItems refresh scheduler missing'
grep -Fq 'id: visibleItemsRefreshTimer' "$dock" \
  || fail 'visibleItems refresh timer missing'
refresh_timer="$(sed -n '/id: visibleItemsRefreshTimer/,/^[[:space:]]*  }/p' "$dock")"
grep -Fq 'interval: 0' <<<"$refresh_timer" \
  || fail 'visibleItems refresh must be zero-delay'
grep -Fq 'onTriggered: root.refreshVisibleItems()' <<<"$refresh_timer" \
  || fail 'visibleItems timer must invoke the refresh helper'

build_calls="$(rg -n 'DockModel\.buildVisibleItems\(' "$dock" | wc -l | tr -d ' ')"
[[ "$build_calls" == "1" ]] \
  || fail "expected one buildVisibleItems call, found $build_calls"
refresh_body="$(sed -n '/function refreshVisibleItems()/,/^  }/p' "$dock")"
grep -Fq 'DockModel.buildVisibleItems(' <<<"$refresh_body" \
  || fail 'buildVisibleItems must be called by refreshVisibleItems'
visible_items_property="$(sed -n '/^[[:space:]]*property var visibleItems:/,/^[[:space:]]*function refreshVisibleItems()/p' "$dock")"
if grep -Eq 'DockModel\.buildVisibleItems\(' <<<"$visible_items_property"; then
  fail 'visibleItems must not call buildVisibleItems from a property binding'
fi

grep -Fq 'Component.onCompleted: root.scheduleVisibleItemsRefresh()' "$dock" \
  || fail 'visibleItems must refresh after startup'
grep -Fq 'onSettingsChanged: root.scheduleVisibleItemsRefresh()' "$dock" \
  || fail 'settings changes must refresh visibleItems'
grep -Fq 'onPinnedChanged: root.scheduleVisibleItemsRefresh()' "$dock" \
  || fail 'pinned changes must refresh visibleItems'
grep -Fq 'root.scheduleVisibleItemsRefresh()' "$dock" \
  || fail 'visibleItems refresh scheduling missing'

grep -Fq 'target: DesktopEntries.applications' "$dock" \
  || fail 'application collection observer missing'
grep -Fq 'target: ToplevelManager.toplevels' "$dock" \
  || fail 'toplevel collection observer missing'
grep -Fq 'target: Hyprland.toplevels' "$dock" \
  || fail 'Hyprland toplevel collection observer missing'

grep -Fq 'root.scheduleVisibleItemsRefresh()' <(sed -n '/id: fullscreenStateRefreshTimer/,/^[[:space:]]*  }/p' "$dock") \
  || fail 'fullscreen delayed refresh must schedule visibleItems'
grep -Fq 'root.scheduleVisibleItemsRefresh()' <(sed -n '/id: workspaceStateRefreshTimer/,/^[[:space:]]*  }/p' "$dock") \
  || fail 'workspace delayed refresh must schedule visibleItems'
grep -Fq 'windowtitle' "$dock" \
  || fail 'window-title raw event coverage missing'

printf 'check_visible_items_snapshot: PASS\n'
