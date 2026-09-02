#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'check_attention_badges: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
qml_test=tests/tst_badgemodel.qml
node_test=tests/test_badge_model.mjs

[[ -f "$model" ]] || fail 'DockBadgeModel.js missing'
[[ -f "$qml_test" ]] || fail 'QML badge model test missing'
[[ -f "$node_test" ]] || fail 'Node badge model test missing'

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

if grep -Eqi 'unread.?count|badge.?count|numeric.?badge' "$model" "$qml_test" "$node_test"; then
  fail 'numeric unread counts belong to FDM-811, not FDM-809'
fi

printf 'check_attention_badges: PASS\n'
