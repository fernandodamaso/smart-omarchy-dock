#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_urgent_window_attention: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
tracker=components/DockBadgeTracker.qml
motion=components/DockAttentionMotion.qml
item=components/DockItem.qml
dock=components/Dock.qml
settings=components/DockSettings.qml

for path in "$model" "$tracker" "$motion" "$item" "$dock" "$settings" \
  DockHost.qml config/dock.json docs/attention-badges.md \
  tests/test_attention_motion_model.mjs tests/test_urgent_window_settings.mjs \
  tests/tst_attentionmotionmodel.qml; do
  [[ -f "$path" ]] || fail "missing $path"
done

tracker_owners="$(grep -R -F 'DockBadgeTracker {' DockHost.qml components \
  --include='*.qml' | wc -l | tr -d ' ')"
[[ "$tracker_owners" == "1" ]] \
  || fail "expected one shared DockBadgeTracker, found $tracker_owners"
grep -Fq 'DockBadgeTracker {' DockHost.qml \
  || fail 'DockHost must continue to own the single badge/urgency tracker'

# Motion must be finite: four 130ms OutCubic legs, exactly one sequence.
grep -Fq 'SequentialAnimation {' "$motion" \
  || fail 'bounded sequential nudge missing'
grep -Fq 'loops: 1' "$motion" || fail 'urgent nudge must never loop'
[[ "$(grep -c 'duration: 130' "$motion")" == "4" ]] \
  || fail 'urgent nudge must contain four 130ms legs (~520ms total)'
[[ "$(grep -c 'easing.type: Easing.OutCubic' "$motion")" == "4" ]] \
  || fail 'all urgent nudge legs must use OutCubic'
grep -Fq 'to: 5' "$motion" || fail '5px first excursion missing'
grep -Fq 'to: 3' "$motion" || fail '3px second excursion missing'
if grep -Fq 'Timer {' "$motion"; then
  fail 'DockAttentionMotion must not add idle timers'
fi

# Edge vectors: toward the desktop for every dock position.
grep -Fq 'case "top": return { x: 0, y: amount }' "$model" \
  || fail 'top vector must point downward'
grep -Fq 'case "left": return { x: amount, y: 0 }' "$model" \
  || fail 'left vector must point rightward'
grep -Fq 'case "right": return { x: -amount, y: 0 }' "$model" \
  || fail 'right vector must point leftward'
grep -Fq 'default: return { x: 0, y: -amount }' "$model" \
  || fail 'bottom vector must point upward'
grep -Fq 'URGENT_WINDOW_COOLDOWN_MS = 3000' "$model" \
  || fail 'three-second per-application cooldown missing'

# Only Hyprland window urgency may create motion revisions. Existing FDM-809
# SNI/notification title matching remains static badge behavior outside this block.
urgent_block="$(sed -n '/function urgentAddressesFor/,/function ensureUrgentState/p' "$tracker")"
grep -Fq 'handle.urgent !== true' <<<"$urgent_block" \
  || fail 'motion revision source must require Hyprland urgent=true'
grep -Fq 'ipc.address' <<<"$urgent_block" \
  || fail 'motion revision must key real Hyprland window addresses'
if grep -Eiq 'title|tooltip|notification|launcherBadge|count|body|sender|output' \
    <<<"$urgent_block"; then
  fail 'motion revision source must not use titles, notifications, counts, or content'
fi

# No new persistence/logging/polling for motion state.
grep -Fq 'property var urgentStates: ({})' "$tracker" \
  || fail 'in-memory urgent-address state missing'
grep -Fq 'property var urgentMotionStates: ({})' "$tracker" \
  || fail 'in-memory motion state missing'
[[ "$(grep -c 'Timer {' "$tracker")" == "2" ]] \
  || fail 'FDM-814 must not add tracker timers beyond FDM-809 focus/TTL timers'
if grep -Eq 'hyprctl|Process[[:space:]]*\{' "$tracker" "$motion" "$item"; then
  fail 'urgent motion must not poll or shell out to hyprctl'
fi
if grep -Eq 'console\.(log|warn|error).*urgent|console\.(log|warn|error).*address' \
    "$tracker" "$item" "$motion"; then
  fail 'urgent window addresses/state must not be logged'
fi

# Primary ownership and suppression/pending hooks.
grep -Fq 'isPrimaryVisibleItem' "$dock" \
  || fail 'ungrouped primary badge-owner selection missing'
grep -Fq 'primaryBadgeOwner: root.primaryBadgeOwnerFor(index)' "$dock" \
  || fail 'primary ownership not wired into DockItem'
grep -Fq 'mouse.hovered' "$item" || fail 'hover suppression missing'
grep -Fq 'dragHandler.active' "$item" || fail 'drag suppression missing'
grep -Fq 'contextMenu.visible' "$item" || fail 'context-menu suppression missing'
grep -Fq 'previewInteractionActive' "$item" || fail 'preview suppression hook missing'
grep -Fq 'pendingRevision' "$model" || fail 'hidden-dock pending reducer missing'
grep -Fq 'dockShown: root.dockShown' "$dock" \
  || fail 'dock reveal state not wired to the motion reducer'

# Preserve the existing auto-hide reveal/mask semantics; urgency only observes
# dockShown and must not own reveal state.
grep -Fq 'readonly property bool dockShown: !autoHide || autoHideRevealed' "$dock" \
  || fail 'existing dockShown auto-hide expression changed'
grep -Fq 'item: root.dockShown ? interactionArea : revealStrip' "$dock" \
  || fail 'existing auto-hide input mask changed'
grep -Fq 'interval: 800' "$dock" \
  || fail 'existing auto-hide close grace changed'
if grep -Fq 'autoHideRevealed' "$tracker" "$motion" "$item"; then
  fail 'urgency/motion code must not reveal an auto-hidden dock'
fi

# Setting defaults, UI and effective gating.
grep -Fq '"urgentWindowAnimationEnabled": true' config/dock.json \
  || fail 'config default missing'
grep -Fq 'urgentWindowAnimationEnabled: true' DockHost.qml \
  || fail 'host fallback missing'
grep -Fq 'patch.urgentWindowAnimationEnabled = true' DockHost.qml \
  || fail 'reset default missing'
grep -Fq 'title: "Application Badges"' "$settings" \
  || fail 'Application Badges settings section missing'
grep -Fq 'label: "Urgent window animation"' "$settings" \
  || fail 'explicit urgent motion control missing'
grep -Fq 'urgentWindowAnimationEnabled: root.urgentWindowAnimationEnabled' "$dock" \
  || fail 'motion setting not wired to DockItem'
grep -Fq 'badgesEnabled: attentionBadgesEnabled' "$item" \
  || fail 'motion must also require attention badges to be enabled'

# Motion offsets wrap artwork/badges while the persistent running indicator is
# deliberately outside motionContent.
grep -Fq 'id: motionContent' "$item" || fail 'motion artwork wrapper missing'
grep -Fq 'x: attentionMotion.xOffset' "$item" || fail 'x offset composition missing'
grep -Fq 'y: attentionMotion.yOffset' "$item" || fail 'y offset composition missing'
grep -Fq 'Keep the persistent running/focus indicator anchored' "$item" \
  || fail 'anchored running-indicator boundary missing'

printf 'check_urgent_window_attention: PASS\n'
