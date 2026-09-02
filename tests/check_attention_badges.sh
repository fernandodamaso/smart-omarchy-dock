#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_attention_badges: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
tracker=components/DockBadgeTracker.qml
badge=components/DockApplicationBadge.qml
qml_test=tests/tst_badgemodel.qml
node_test=tests/test_badge_model.mjs

[[ -f "$model" ]] || fail 'DockBadgeModel.js missing'
[[ -f "$tracker" ]] || fail 'DockBadgeTracker.qml missing'
[[ -f "$badge" ]] || fail 'DockApplicationBadge.qml missing'
[[ -f "$qml_test" ]] || fail 'QML badge model test missing'
[[ -f "$node_test" ]] || fail 'Node badge model test missing'

tracker_owners="$(grep -R -F 'DockBadgeTracker {' DockHost.qml components --include='*.qml' | wc -l | tr -d ' ')"
[[ "$tracker_owners" == "1" ]] \
  || fail "expected exactly one DockBadgeTracker owner, found $tracker_owners"
grep -Fq 'DockBadgeTracker {' DockHost.qml \
  || fail 'DockHost.qml must own DockBadgeTracker'
grep -Fq 'badgeTracker: root.badgeTracker' DockHost.qml \
  || fail 'DockHost.qml must share one tracker with every Dock'

grep -Fq 'PersistentProperties {' "$tracker" \
  || fail 'tracker must use PersistentProperties'
if grep -Fq 'FileView' "$tracker"; then
  fail 'attention state must not be persisted to disk'
fi
if grep -Fq 'NotificationServer' "$tracker" Overlay.qml DockHost.qml; then
  fail 'SmartDock must not create a competing notification server'
fi

badge_for_body="$(sed -n '/function badgeFor(desktopId)/,/^  }/p' "$tracker")"
if grep -Fq 'revision' <<<"$badge_for_body"; then
  fail 'badgeFor must not read tracker revision from inside the DockItem binding'
fi
grep -Fq 'property int badgeStateRevision: 0' components/Dock.qml \
  || fail 'Dock.qml must own the external badge revision dependency'
grep -Fq 'target: root.badgeTracker' components/Dock.qml \
  || fail 'Dock.qml must observe shared tracker revisions'
grep -Fq 'function onRevisionChanged()' components/Dock.qml \
  || fail 'Dock.qml must handle tracker revision changes'
grep -Fq 'root.badgeStateRevision++' components/Dock.qml \
  || fail 'tracker revision changes must invalidate dock badge bindings'
grep -Fq 'var badgeRevision = badgeStateRevision' components/Dock.qml \
  || fail 'attentionBadgeFor must depend on Dock-owned badge revision state'

grep -Fq 'firstPartyServiceFor("omarchy.notifications")' Overlay.qml \
  || fail 'preferred optional Omarchy notification service wiring missing'
grep -Fq 'Status.NeedsAttention' "$tracker" \
  || fail 'SNI NeedsAttention source missing'
grep -Fq 'NotificationUrgency.Critical' "$tracker" \
  || fail 'critical notification reduction missing'
grep -Fq 'handle.urgent !== true' "$tracker" \
  || fail 'Hyprland urgent source missing'

grep -q 'LOCAL_ATTENTION_TTL_MS = 24 \* 60 \* 60 \* 1000' "$model" \
  || fail '24-hour local attention TTL missing'
grep -q 'FOCUS_DWELL_MS = 800' "$model" \
  || fail '800ms focus dwell missing'
grep -q 'function strictIdentityMatches' "$model" \
  || fail 'strict identity matching missing'
grep -q 'function upsertNotification' "$model" \
  || fail 'notification replacement handling missing'
grep -q 'function badgeSeverity' "$model" \
  || fail 'source reduction missing'
grep -q 'function isPrimaryVisibleItem' "$model" \
  || fail 'ungrouped primary-item selection missing'
grep -Fq 'isPrimaryVisibleItem' components/Dock.qml \
  || fail 'Dock.qml must assign one primary item per app'

grep -Fq '"attentionBadgesEnabled": true' config/dock.json \
  || fail 'config default must enable attention badges'
grep -Fq 'attentionBadgesEnabled: true' DockHost.qml \
  || fail 'host fallback must enable attention badges'
grep -Fq 'DockApplicationBadge {' components/DockItem.qml \
  || fail 'DockItem.qml must use the reusable application badge'
grep -Fq 'severity === "urgent" ? Color.urgent : Color.accent' "$badge" \
  || fail 'urgent/accent dot rendering missing'

if grep -Eq '(^|[^A-Za-z])(Text|Label)[[:space:]]*\{' "$badge"; then
  fail 'FDM-809 badge must remain dot-only with no numeric/text content'
fi
if grep -Eq '(Animation|Behavior)[[:space:]]' "$badge"; then
  fail 'attention badge motion belongs to FDM-814, not FDM-809'
fi
if grep -Eiq 'unread(Count|Total|Number)|notification(Count|Total)' \
    "$model" "$tracker" "$badge"; then
  fail 'numeric unread counts belong to FDM-811, not FDM-809'
fi

printf 'check_attention_badges: PASS\n'
