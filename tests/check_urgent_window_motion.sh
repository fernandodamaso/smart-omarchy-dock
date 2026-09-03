#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_urgent_window_motion: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
tracker=components/DockBadgeTracker.qml
motion=components/DockAttentionMotion.qml
dock=components/Dock.qml
item=components/DockItem.qml
settings=components/DockSettings.qml
config=config/dock.json
node_test=tests/test_attention_motion_model.mjs

for path in "$model" "$tracker" "$motion" "$dock" "$item" "$settings" "$config" "$node_test"; do
  [[ -f "$path" ]] || fail "missing $path"
done

tracker_owners="$(grep -R -F 'DockBadgeTracker {' DockHost.qml components --include='*.qml' | wc -l | tr -d ' ')"
[[ "$tracker_owners" == "1" ]] \
  || fail "expected exactly one DockBadgeTracker owner, found $tracker_owners"
grep -Fq 'DockBadgeTracker {' DockHost.qml \
  || fail 'DockHost.qml must remain the sole badge tracker owner'
grep -Fq 'badgeTracker: root.badgeTracker' DockHost.qml \
  || fail 'DockHost must share the existing tracker with every Dock'

# The urgency reducer must revise only when a new address enters the set.
grep -Fq 'URGENT_WINDOW_COOLDOWN_MS = 3000' "$model" \
  || fail 'three-second per-application cooldown missing'
grep -Fq 'function reduceWindowUrgencyState' "$model" \
  || fail 'window urgency revision reducer missing'
grep -Fq 'oldAddresses.indexOf(current[i]) < 0' "$model" \
  || fail 'new-address-only urgency revision rule missing'
grep -Fq 'function reduceUrgentMotion' "$model" \
  || fail 'pure urgent motion decision reducer missing'
grep -Fq 'function urgentMotionVector' "$model" \
  || fail 'position-aware vector helper missing'

grep -Fq 'case "top": return { x: 0, y: amount }' "$model" \
  || fail 'top edge must nudge downward'
grep -Fq 'case "left": return { x: amount, y: 0 }' "$model" \
  || fail 'left edge must nudge rightward'
grep -Fq 'case "right": return { x: -amount, y: 0 }' "$model" \
  || fail 'right edge must nudge leftward'
grep -Fq 'default: return { x: 0, y: -amount }' "$model" \
  || fail 'bottom edge must nudge upward'

# Motion is bounded: one 520ms two-excursion sequence and never loops.
grep -Fq 'loops: 1' "$motion" || fail 'motion must not loop'
[[ "$(grep -F 'duration: 130' "$motion" | wc -l | tr -d ' ')" == "4" ]] \
  || fail 'motion must have four 130ms legs (~520ms total)'
[[ "$(grep -F 'easing.type: Easing.OutCubic' "$motion" | wc -l | tr -d ' ')" == "4" ]] \
  || fail 'every motion leg must use OutCubic easing'
grep -Fq 'to: 5' "$motion" || fail 'first 5px excursion missing'
grep -Fq 'to: 3' "$motion" || fail 'second 3px excursion missing'
[[ "$(grep -F 'to: 0' "$motion" | wc -l | tr -d ' ')" == "2" ]] \
  || fail 'motion must return to zero after each excursion'

# Motion only exposes offsets; existing icon scale/opacity and slot indicator stay outside it.
grep -Fq 'readonly property real xOffset' "$motion" || fail 'xOffset missing'
grep -Fq 'readonly property real yOffset' "$motion" || fail 'yOffset missing'
if grep -Eq '(^|[[:space:]])(scale|opacity):' "$motion"; then
  fail 'DockAttentionMotion must not own scale or opacity'
fi
grep -Fq 'x: attentionMotion.xOffset' "$item" || fail 'x offset composition missing'
grep -Fq 'y: attentionMotion.yOffset' "$item" || fail 'y offset composition missing'
grep -Fq 'Keep the persistent running/focus indicator anchored to the dock slot' "$item" \
  || fail 'running/focus indicator anchoring boundary missing'

# Interaction and primary-owner gates are explicit; preview branches can wire the hook.
grep -Fq 'primaryBadgeOwner' "$item" || fail 'primary badge owner gate missing'
grep -Fq 'previewInteractionActive' "$item" || fail 'preview suppression hook missing'
grep -Fq 'mouse.hovered' "$item" || fail 'hover suppression missing'
grep -Fq 'dragHandler.active' "$item" || fail 'drag suppression missing'
grep -Fq 'contextMenu.visible' "$item" || fail 'context-menu suppression missing'
grep -Fq 'BadgeModel.isPrimaryVisibleItem' "$dock" \
  || fail 'ungrouped primary-owner selection missing'

# Auto-hide remains owned by Dock.qml. Urgency may observe dockShown but must never reveal it.
grep -Fq 'readonly property bool dockShown: !autoHide || autoHideRevealed' "$dock" \
  || fail 'existing dockShown auto-hide state missing'
grep -Fq 'item: root.dockShown ? interactionArea : revealStrip' "$dock" \
  || fail 'existing reveal-strip input mask changed or missing'
if grep -Eq 'autoHideRevealed[[:space:]]*=' "$tracker" "$motion" "$item"; then
  fail 'urgent motion must not reveal an auto-hidden dock'
fi

# Settings default on, explicit disable control, effective only with badge display enabled.
grep -Fq '"urgentWindowAnimationEnabled": true' "$config" \
  || fail 'config default missing'
grep -Fq 'urgentWindowAnimationEnabled: true' DockHost.qml \
  || fail 'host fallback default missing'
grep -Fq 'patch.urgentWindowAnimationEnabled = true' DockHost.qml \
  || fail 'reset default missing'
grep -Fq 'title: "Application Badges"' "$settings" \
  || fail 'Application Badges settings section missing'
grep -Fq 'label: "Urgent window animation"' "$settings" \
  || fail 'explicit urgent motion toggle missing'
grep -Fq 'enabled: root.current("attentionBadgesEnabled") !== false' "$settings" \
  || fail 'motion toggle must be effective only when badges are enabled'
grep -Fq 'animationEnabled: urgentWindowAnimationEnabled' "$item" \
  || fail 'animation setting not wired into decision reducer'
grep -Fq 'badgesEnabled: attentionBadgesEnabled' "$item" \
  || fail 'badge enable setting not wired into decision reducer'

# FDM-809/FDM-811 ownership boundaries: provider count changes never request motion.
grep -Fq 'launcherBadgeService: root.launcherBadgeService' DockHost.qml \
  || fail 'existing FDM-811 provider injection missing'
if grep -A8 -F 'Connections {' "$tracker" | grep -Eq 'launcherBadge.*requestUrgentMotion'; then
  fail 'launcher badge counts must not trigger urgent motion'
fi
if grep -Eq 'requestUrgentMotion.*(title|notification|count|sender|output)' "$tracker" "$item"; then
  fail 'content/count heuristic detected in motion trigger path'
fi

# No motion polling/idle loops or persistence of urgency/motion state.
if grep -Eiq 'hyprctl|while[[:space:]]+true|repeat:[[:space:]]*true' "$motion"; then
  fail 'motion component must not poll or run an idle loop'
fi
if grep -Eiq 'hyprctl' "$tracker" "$model"; then
  fail 'urgency tracker/model must not poll hyprctl'
fi
if grep -A8 -F 'PersistentProperties {' "$tracker" | grep -Eq 'urgentStates|urgentMotionStates|windowUrgentRevision'; then
  fail 'urgency/motion revision state must not persist across reloads'
fi

printf 'check_urgent_window_motion: PASS\n'
