#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dock_qml="$plugin_root/components/Dock.qml"
dock_item_qml="$plugin_root/components/DockItem.qml"
schema="$plugin_root/config/settings-schema.json"

for token in \
  backgroundColorEnabled \
  backgroundColor \
  borderColorEnabled \
  borderColor \
  workspaceBadgeBackgroundColorEnabled \
  workspaceBadgeBackgroundColor \
  workspaceBadgeTextColorEnabled \
  workspaceBadgeTextColor \
  borderWidthEnabled \
  borderWidth; do
  for file in "$dock_qml" "$schema"; do
    if ! rg -n "$token" "$file" >/dev/null; then
      printf 'Surface override setting is missing from %s: %s\n' "$file" "$token" >&2
      exit 1
    fi
  done
done

if ! rg -n 'effectiveColor|effectiveBorderWidth' "$dock_qml" >/dev/null; then
  printf 'Dock surface must resolve enabled overrides against theme tokens\n' >&2
  exit 1
fi

for flow in \
  'workspaceBadgeBackgroundColor:.*effectiveWorkspaceBadgeBackgroundColor' \
  'workspaceBadgeTextColor:.*effectiveWorkspaceBadgeTextColor'; do
  if ! rg -n "$flow" "$dock_qml" >/dev/null; then
    printf 'Dock must pass resolved workspace badge colors to DockItem: %s\n' "$flow" >&2
    exit 1
  fi
done
rg -n 'required property color workspaceBadgeBackgroundColor' "$dock_item_qml" >/dev/null \
  || { echo 'DockItem is missing the workspace badge background color input' >&2; exit 1; }
rg -n 'required property color workspaceBadgeTextColor' "$dock_item_qml" >/dev/null \
  || { echo 'DockItem is missing the workspace badge text color input' >&2; exit 1; }
rg -n 'color: root\.workspaceBadgeBackgroundColor' "$dock_item_qml" >/dev/null \
  || { echo 'Workspace badge background does not use its resolved color' >&2; exit 1; }
rg -n 'color: root\.workspaceBadgeTextColor' "$dock_item_qml" >/dev/null \
  || { echo 'Workspace badge text does not use its resolved color' >&2; exit 1; }

# Atomic multi-key color intents are exercised by the actual host/model suite.
rg -n 'root\.host\.saveSettings\(args.patch, args.dryRun === true\)' \
    "$plugin_root/components/DockControl.qml" >/dev/null \
  || { echo 'CLI color patches must use the shared host writer' >&2; exit 1; }
