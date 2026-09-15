#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/components/DockContextMenu.qml"
controller="$repo_root/components/DockContextActionController.qml"
fullscreen_model="$repo_root/components/DockFullscreenModel.js"
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

grep -q 'function request(address, targetModeValue, usingLua)' "$fullscreen_model" \
  || fail 'fullscreen modes must share one exact-address request builder'
grep -q 'function setFullscreenMode' "$controller" \
  || fail 'context action controller must own exact-target fullscreen transitions'
grep -q 'function minimizeVisible' "$controller" \
  || fail 'represented groups need a counted visible-only minimize action'
grep -q 'function restoreMinimized' "$controller" \
  || fail 'represented groups need a counted minimized-only restore action'
grep -q 'function closeRepresented' "$controller" \
  || fail 'represented groups need an exact-membership close action'

grep -q 'applicationMutationController' "$controller" \
  || fail 'persistent app actions must delegate to the host-owned mutation controller'
grep -q 'applicationMutationController' "$menu" \
  || fail 'menu must observe host persistence state rather than claiming optimistic success'

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

grep -Fq 'omarchy-clipboard-paste-text' "$menu" \
  || fail 'clipboard copy must use the Omarchy clipboard helper with exit status'
grep -Fq -- '--copy-only' "$menu" \
  || fail 'clipboard helper must copy without synthesizing paste input'

exit "$status"
