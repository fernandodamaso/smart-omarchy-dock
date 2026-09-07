#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_attention_motion_sources: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
tracker=components/DockBadgeTracker.qml
item=components/DockItem.qml

grep -Fq 'function motionAttentionEligible' "$model" \
  || fail 'pure motion source eligibility helper missing'
grep -Fq 'function motionAttentionFor(desktopId)' "$tracker" \
  || fail 'badge tracker must expose source-specific motion eligibility'
grep -Fq 'BadgeModel.motionAttentionEligible(' "$tracker" \
  || fail 'tracker must use the pure source eligibility contract'
grep -Fq 'badgeTracker.motionAttentionFor(desktopId)' "$item" \
  || fail 'DockItem must consume source-specific motion eligibility'

if grep -Fq 'attentionSeverityFromBadgeToken(attentionBadge)' "$item"; then
  fail 'DockItem must not infer motion eligibility from the rendered badge token'
fi

printf 'check_attention_motion_sources: PASS\n'
