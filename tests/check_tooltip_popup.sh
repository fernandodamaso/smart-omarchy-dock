#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for relative_path in \
  components/DockItem.qml \
  components/DockControlItem.qml \
  components/DockTrashItem.qml; do
  qml_file="$plugin_root/$relative_path"

  if ! rg -n '^  PanelToolTip \{' "$qml_file" >/dev/null; then
    printf '%s must use a popup-backed PanelToolTip\n' "$relative_path" >&2
    exit 1
  fi

  if rg -n '^  BorderSurface \{' "$qml_file" >/dev/null \
      && rg -n 'id: tooltip|id: tooltipText|id: trashTooltip' "$qml_file" >/dev/null; then
    printf '%s still contains an inline tooltip surface that can be clipped\n' \
      "$relative_path" >&2
    exit 1
  fi
done
