#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/components/DockContextMenu.qml"
item="$repo_root/components/DockItem.qml"
dock="$repo_root/components/Dock.qml"
actions="$repo_root/components/DockWindowActions.qml"
model="$repo_root/components/DockModel.js"
menu_model="$repo_root/components/DockMenuModel.js"

status=0
fail() {
  printf 'FDM-940 contextual-action contract: %s\n' "$1" >&2
  status=1
}

for label in 'Fullscreen — Keep Bars' 'Fullscreen — Hide Bars' \
  'Hide App from Dock' 'Copy Icon Command'; do
  grep -Fq "$label" "$menu" || fail "missing menu action: $label"
done

grep -q 'fullscreenModeRequest' "$model" \
  || fail 'fullscreen modes must share one exact-address request builder'
grep -q 'setFullscreenMode' "$actions" \
  || fail 'window actions must own exact-target fullscreen transitions'
grep -q 'minimizeVisibleToplevels' "$actions" \
  || fail 'represented groups need a counted visible-only minimize action'
grep -q 'restoreMinimizedToplevels' "$actions" \
  || fail 'represented groups need a counted minimized-only restore action'

grep -q 'applicationMutationController' "$menu" \
  || fail 'persistent app actions must consume the host-owned mutation controller'
grep -q 'applicationMutationController' "$item" \
  || fail 'DockItem must pass the host-owned mutation controller into its menu'
grep -q 'applicationMutationController' "$dock" \
  || fail 'Dock must route the host-owned mutation controller without adding a writer'

grep -q 'iconCommandSpec' "$menu_model" \
  || fail 'icon-copy commands need a pure argv/text builder with shell-safe quoting'
grep -q 'mutationPresentation' "$menu_model" \
  || fail 'menu mutations need requested/effective/durable presentation states'

for command in 'minimize-visible' 'restore-minimized' 'close-represented' \
  'fullscreen-keep-bars' 'fullscreen-hide-bars' 'copy-icon-command'; do
  grep -Fq "$command" "$menu" || fail "missing contextual command wiring: $command"
done

if grep -Fq 'Group Windows' "$menu"; then
  fail 'CM-03 grouping mutation must not be exposed early'
fi
if grep -Fq 'Pin Window to Workspace' "$menu"; then
  fail 'CM-04 window pinning must not be exposed early'
fi
if grep -Eq 'sh[[:space:]]+-c|execDetached\(\[[[:space:]]*"sh"' "$menu"; then
  fail 'copy-command actions must not execute copied shell text'
fi

exit "$status"
