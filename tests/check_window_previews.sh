#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_window_previews: $*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing expected preview contract in $file: $pattern"
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "unexpected preview ownership/behavior in $file: $pattern"
  fi
}

for file in components/DockWindowPreview.qml components/DockWindowPreviewTile.qml components/DockWindowPreviewModel.js; do
  [[ -f "$file" ]] || fail "$file does not exist"
done

popup_count="$(grep -Ec '^[[:space:]]*DockWindowPreview[[:space:]]*\{' components/Dock.qml || true)"
[[ "$popup_count" -eq 1 ]] \
  || fail "Dock.qml must own exactly one shared DockWindowPreview (found $popup_count)"

require_pattern 'signal previewRequested\(' components/DockItem.qml
require_pattern 'signal previewReleased\(' components/DockItem.qml
require_pattern 'signal previewDismissRequested\(' components/DockItem.qml
require_pattern 'runningCount[[:space:]]*<[[:space:]]*2' components/DockItem.qml
require_pattern 'onHoveredChanged' components/DockItem.qml
require_pattern 'previewRequested\(' components/DockItem.qml
require_pattern 'previewReleased\(' components/DockItem.qml
require_pattern 'previewDismissRequested\(\)' components/DockItem.qml
require_pattern 'visible:[[:space:]]*mouse\.hovered.*!root\.previewActive' components/DockItem.qml

require_pattern 'openDelayMs:[[:space:]]*250' components/DockWindowPreview.qml
require_pattern 'closeGraceMs:[[:space:]]*180' components/DockWindowPreview.qml
require_pattern 'interactionActive' components/DockWindowPreview.qml
require_pattern 'readonly property bool keepAutoHideOpen' components/Dock.qml
require_pattern 'windowPreview\.interactionActive' components/Dock.qml
require_pattern 'onPreviewRequested:' components/Dock.qml
require_pattern 'onPreviewReleased:' components/Dock.qml
require_pattern 'onPreviewDismissRequested:' components/Dock.qml
require_pattern 'onOpenMenuCountChanged:' components/Dock.qml
require_pattern 'onDragSourceChanged:' components/Dock.qml

require_pattern 'grabFocus:[[:space:]]*false' components/DockWindowPreview.qml
require_pattern 'PopupAdjustment\.Slide' components/DockWindowPreview.qml
require_pattern 'groupedPreviewMembers' components/DockWindowPreview.qml
require_pattern 'previewViewport' components/DockWindowPreview.qml
require_pattern 'previewAnchorOffset' components/DockWindowPreview.qml
require_pattern 'Flickable[[:space:]]*\{' components/DockWindowPreview.qml
require_pattern 'orientationHorizontal' components/DockWindowPreview.qml
require_pattern 'onVisibleItemsChanged:' components/DockWindowPreview.qml
require_pattern 'onDestroyed' components/DockWindowPreview.qml
require_pattern 'Component\.onDestruction:' components/DockWindowPreview.qml

require_pattern 'ScreencopyView[[:space:]]*\{' components/DockWindowPreviewTile.qml
require_pattern 'live:[[:space:]]*false' components/DockWindowPreviewTile.qml
require_pattern 'paintCursor:[[:space:]]*false' components/DockWindowPreviewTile.qml
require_pattern 'constraintSize:' components/DockWindowPreviewTile.qml
require_pattern 'captureSource:[[:space:]]*root\.captureEnabled[[:space:]]*\?[[:space:]]*root\.toplevel[[:space:]]*:[[:space:]]*null' components/DockWindowPreviewTile.qml
require_pattern 'captureFrame\(\)' components/DockWindowPreviewTile.qml
require_pattern 'Preview unavailable' components/DockWindowPreviewTile.qml
require_pattern 'Accessible\.name:' components/DockWindowPreviewTile.qml
require_pattern 'activateToplevel\(' components/DockWindowPreview.qml
require_pattern 'closeToplevel\(' components/DockWindowPreview.qml

host_instances="$(grep -Ec '^[[:space:]]*DockWindowActions[[:space:]]*\{' DockHost.qml || true)"
[[ "$host_instances" -eq 1 ]] \
  || fail "DockHost.qml must still own exactly one DockWindowActions instance"
reject_pattern 'DockWindowActions[[:space:]]*\{' components/DockWindowPreview.qml
reject_pattern 'DockWindowActions[[:space:]]*\{' components/DockWindowPreviewTile.qml
reject_pattern 'property var minimizedOrigins' components/DockWindowPreview.qml
reject_pattern 'property var minimizedOrigins' components/DockWindowPreviewTile.qml

require_pattern 'window previews' README.md
require_pattern 'check_window_previews\.sh' AGENTS.md
require_pattern '50 open/close cycles' AGENTS.md

echo "check_window_previews: PASS"
