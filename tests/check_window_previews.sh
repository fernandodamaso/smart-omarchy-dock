#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  printf 'check_window_previews: %s\n' "$*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing '$pattern' in $file"
}

[[ -f components/DockWindowPreview.qml ]] || fail "missing preview popup"
[[ -f components/DockWindowPreviewTile.qml ]] || fail "missing preview tile"
[[ -f components/DockWindowPreviewModel.js ]] || fail "missing preview model"
require_pattern 'DockWindowPreview[[:space:]]*\{' components/Dock.qml
require_pattern 'onPreviewRequested:' components/Dock.qml
require_pattern 'previewRequested' components/DockItem.qml
require_pattern 'root\.previewRequested\(root' components/DockItem.qml
require_pattern 'ScreencopyView[[:space:]]*\{' components/DockWindowPreviewTile.qml
require_pattern 'captureFrame\(\)' components/DockWindowPreviewTile.qml
require_pattern 'function groupedPreviewMembers\(' components/DockWindowPreviewModel.js
require_pattern 'function previewAnchorOffset\(' components/DockWindowPreviewModel.js

printf 'check_window_previews: PASS\n'
