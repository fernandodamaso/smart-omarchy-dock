#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/components/DockContextMenu.qml"
controller="$repo_root/components/DockContextActionController.qml"
fullscreen_model="$repo_root/components/DockFullscreenModel.js"
menu_model="$repo_root/components/DockMenuModel.js"
window_actions="$repo_root/components/DockWindowActions.qml"
host="$repo_root/DockHost.qml"

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

grep -q 'property var applicationMutationController: null' "$window_actions" \
  || fail 'shared window actions must declare the host mutation controller explicitly'
grep -q 'applicationMutationController: root' "$host" \
  || fail 'DockHost must explicitly inject the sole mutation/persistence owner'
grep -q 'windowActions\.applicationMutationController' "$controller" \
  || fail 'context actions must consume the explicitly injected host controller'
if grep -q 'windowActions\.parent' "$controller"; then
  fail 'context actions must not infer the host through QObject parent traversal'
fi

grep -q 'iconCommandSpec' "$menu_model" \
  || fail 'icon-copy commands need a pure argv/text builder with shell-safe quoting'
grep -q 'mutationPresentation' "$menu_model" \
  || fail 'menu mutations need requested/effective/durable presentation states'

for command in 'minimize-visible' 'restore-minimized' 'close-represented' \
  'fullscreen-keep-bars' 'fullscreen-hide-bars' 'copy-icon-command'; do
  grep -Fq "$command" "$menu" || fail "missing contextual command wiring: $command"
done

# CM-03 now owns local Group/Ungroup. Keep this earlier-slice guard focused on
# preventing later CM-04 window pinning from leaking into the aggregate PR.
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

strip="$repo_root/components/DockSidebarPinnedStrip.qml"
grep -Eq 'readonly property string desktopId' "$strip" \
  || fail 'pin-strip cells must expose desktopId for Unpin'
grep -Fq 'pinStripOwned' "$strip" \
  || fail 'pin-strip cells must mark pinStripOwned for menu gating'
grep -Fq 'pinStripOwned' "$menu" \
  || fail 'context menu must gate Hide App using pinStripOwned'
grep -Fq 'contextMenuMembers' "$repo_root/components/DockSidebar.qml" \
  || fail 'sidebar openContext must use contextMenuMembers for pin-strip shortcuts'
grep -Fq 'function contextMenuMembers' \
  "$repo_root/components/DockSidebarInteractionModel.js" \
  || fail 'InteractionModel must own pin-strip vs hierarchy menu member selection'
if grep -Fq 'DockApplicationBadge' "$strip"; then
  fail 'pin-strip must show plain application artwork without DockApplicationBadge'
fi
grep -Fq 'profileBadgesEnabled: false' "$strip" \
  || fail 'pin-strip DockAppIcon must explicitly disable profile badges'
if grep -Eq 'profileKey:|profileName:|profileAvatarPath:' "$strip"; then
  fail 'pin-strip must not pass profileKey/profileName/profileAvatarPath'
fi

sidebar="$repo_root/components/DockSidebar.qml"
grep -Fq 'panel-left-close' "$sidebar" \
  || fail 'expanded collapse control must use panel-left-close'
grep -Fq 'panel-left-open' "$sidebar" \
  || fail 'collapsed collapse control must use panel-left-open'
test -s "$repo_root/assets/lucide/panel-left-close.svg" \
  || fail 'missing bundled Lucide panel-left-close.svg'
test -s "$repo_root/assets/lucide/panel-left-open.svg" \
  || fail 'missing bundled Lucide panel-left-open.svg'

# Match the current 14x10 miniature geometry and topologyStripWidth contract.
row="$repo_root/components/DockSidebarRow.qml"
grep -Fq 'width: 14' "$row" \
  || fail 'monitor topology miniatures must be 14px wide'
grep -Fq 'height: 10' "$row" \
  || fail 'monitor topology miniatures must be 10px tall'
grep -Fq 'radius: 2' "$row" \
  || fail 'monitor topology miniatures must use radius 2'

exit "$status"
