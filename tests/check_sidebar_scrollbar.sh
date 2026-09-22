#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  printf 'check_sidebar_scrollbar: %s\n' "$*" >&2
  exit 1
}

viewport=components/DockSidebarViewport.qml
[[ -f $viewport ]] || fail "missing $viewport"

scroll_block="$(sed -n '/Controls\.ScrollBar\.vertical/,/^    }/p' "$viewport")"
[[ -n $scroll_block ]] || fail "no vertical ScrollBar block in $viewport"

# Under pragma ComponentBehavior: Bound, anchors on the inline attached
# ScrollBar are dropped ("Cannot anchor to an item that isn't a parent or
# sibling") and the bar parks at x=0 on the sidebar's LEFT edge. The block
# must keep explicit geometry and never reintroduce anchors.
grep -q 'x: root.width - width' <<<"$scroll_block" \
  || fail "scrollbar lost its explicit right-edge x binding"
grep -q 'scrollBarOutset' <<<"$scroll_block" \
  || fail "scrollbar lost its scrollBarOutset nudge toward the panel edge"
grep -q 'height: list.height' <<<"$scroll_block" \
  || fail "scrollbar must track the list height explicitly"
grep -Eq 'anchors\.(top|bottom|right|left)' <<<"$scroll_block" \
  && fail "anchors on the attached ScrollBar are dropped under the Bound pragma; keep explicit x/y/width/height"

# The list stays full-width: the bar lives scrollBarOutset past the viewport
# edge, so a reserved right gutter would be dead space (asymmetric padding).
if grep -Eq 'anchors\.rightMargin:[[:space:]]*root\.scrollGutter' "$viewport"; then
  fail "list reserves a right scroll gutter again; the bar lives past the viewport edge, so the gutter is dead space"
fi

# The sidebar keeps symmetric outer insets (padding + resize-edge allowance on
# both sides); asymmetric padding was the user-visible defect.
sidebar=components/DockSidebar.qml
grep -Eq 'anchors\.leftMargin:[[:space:]]*Style\.space\(6\) \+ \(!root\.panelCollapsed \? root\.resizeEdgeAllowance : 0\)' "$sidebar" \
  || fail "viewport left inset lost its resize-edge allowance (symmetry)"
grep -Eq 'anchors\.rightMargin:[[:space:]]*Style\.space\(6\) \+ \(!root\.panelCollapsed \? root\.resizeEdgeAllowance : 0\)' "$sidebar" \
  || fail "viewport right inset lost its resize-edge allowance (symmetry)"
if grep -q 'scrollGutter' "$sidebar"; then
  fail "$sidebar references scrollGutter again; the gutter was folded into the symmetric inset"
fi

# The pragma that forbids anchor positioning must stay visible to reviewers.
grep -q 'pragma ComponentBehavior: Bound' "$viewport" \
  || fail "$viewport lost its Bound pragma; re-evaluate the scrollbar geometry rule above"
