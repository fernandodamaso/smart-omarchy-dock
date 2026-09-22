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
grep -Eq 'scrollBarOutset:[[:space:]]*root\.panelCollapsed[[:space:]]*\?[[:space:]]*4[[:space:]]*:[[:space:]]*\(root\.controller[[:space:]]*&&[[:space:]]*root\.controller\.edge[[:space:]]*===[[:space:]]*"left"[[:space:]]*\?[[:space:]]*4[[:space:]]*:[[:space:]]*10\)' "$viewport" \
  || fail "scrollbar outset must stay inside the collapsed rail and clear the left-sidebar resize handle"

# Guard the two layouts that regressed: 320px expanded left sidebar and 72px rail.
# Expanded viewport inset is 6px padding + 8px resize allowance on each side.
expanded_panel=320
expanded_inset=14
viewport_width=$((expanded_panel - expanded_inset * 2))
bar_width=6
bar_outset=4
bar_right=$((expanded_inset + viewport_width + bar_outset))
resize_start=$((expanded_panel - 8))
(( bar_right <= resize_start )) \
  || fail "expanded scrollbar overlaps the 8px resize handle"

collapsed_panel=72
collapsed_inset=6
collapsed_viewport=$((collapsed_panel - collapsed_inset * 2))
collapsed_right=$((collapsed_inset + collapsed_viewport + bar_outset))
(( collapsed_right <= collapsed_panel )) \
  || fail "collapsed scrollbar is clipped past the panel edge"
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
