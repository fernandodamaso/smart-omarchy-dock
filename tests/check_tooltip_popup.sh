#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tooltip_component="$plugin_root/components/DockToolTip.qml"

if [[ ! -f "$tooltip_component" ]]; then
  printf 'missing Quickshell-native DockToolTip component\n' >&2
  exit 1
fi

for pattern in \
  '^PopupWindow \{' \
  '^    window:.*QsWindow\.window' \
  '^  mask: Region \{\}$' \
  'PopupAdjustment\.Slide' \
  'var x = root\.anchorItem\.width / 2 - root\.implicitWidth / 2' \
  'var y = root\.anchorItem\.height \+ 6' \
  'root\.position === "bottom"' \
  'y = -root\.implicitHeight - 6' \
  'root\.position === "left"' \
  'x = root\.anchorItem\.width \+ 6' \
  'root\.position === "right"' \
  'x = -root\.implicitWidth - 6' \
  'function scheduleReanchor\(\)' \
  'onImplicitWidthChanged: root\.scheduleReanchor\(\)' \
  'onImplicitHeightChanged: root\.scheduleReanchor\(\)' \
  '^  Connections \{$' \
  'function onXChanged\(\)' \
  'function onYChanged\(\)' \
  'function onWidthChanged\(\)' \
  'function onHeightChanged\(\)' \
  '^  Timer \{' \
  'interval: 400'; do
  if ! rg -n "$pattern" "$tooltip_component" >/dev/null; then
    printf 'DockToolTip must contain %s\n' "$pattern" >&2
    exit 1
  fi
done

if ! rg -n 'requestedVisible: root\.presentationVisible && mouse\.hovered && !contextMenu\.visible && !root\.previewActive && !dragHandler\.active && root\.reorderOffset === 0' \
    "$plugin_root/components/DockItem.qml" >/dev/null; then
  printf 'DockItem application tooltip must suppress preview/context, drag, and reorder motion\n' >&2
  exit 1
fi

for relative_path in \
  components/DockItem.qml \
  components/DockControlItem.qml \
  components/DockTrashItem.qml; do
  qml_file="$plugin_root/$relative_path"

  if ! rg -n '^  DockToolTip \{' "$qml_file" >/dev/null; then
    printf '%s must use the Quickshell-native DockToolTip\n' "$relative_path" >&2
    exit 1
  fi

  if rg -n '^  PanelToolTip \{' "$qml_file" >/dev/null; then
    printf '%s must not use a Qt Quick Controls PanelToolTip\n' \
      "$relative_path" >&2
    exit 1
  fi

  if rg -n '^  BorderSurface \{' "$qml_file" >/dev/null \
      && rg -n 'id: tooltip|id: tooltipText|id: trashTooltip' "$qml_file" >/dev/null; then
    printf '%s still contains an inline tooltip surface that can be clipped\n' \
      "$relative_path" >&2
    exit 1
  fi
done
