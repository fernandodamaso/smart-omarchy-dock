#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$script_dir/.."
assets_dir="$plugin_dir/assets/lucide"
menu_action="$plugin_dir/components/DockMenuAction.qml"
control_item="$plugin_dir/components/DockControlItem.qml"
context_menu="$plugin_dir/components/DockContextMenu.qml"

for icon in trash-2 settings-2 plus eye eye-off rocket folder-open \
  maximize-2 minimize-2 square pin pin-off x arrow-right-left \
  chevron-left focus layout-grid move minus app-window; do
  test -s "$assets_dir/$icon.svg" \
    || { echo "Missing bundled Lucide icon: $icon.svg" >&2; exit 1; }
  grep -q '<svg' "$assets_dir/$icon.svg" \
    || { echo "Invalid SVG asset: $icon.svg" >&2; exit 1; }
done

grep -Eq 'property string iconName' "$menu_action" \
  || { echo "DockMenuAction is missing Lucide icon support" >&2; exit 1; }
grep -Eq 'assets/lucide/' "$menu_action" \
  || { echo "DockMenuAction is not loading bundled Lucide assets" >&2; exit 1; }
grep -Eq '^[[:space:]]*ColorOverlay \{' "$menu_action" \
  || { echo "DockMenuAction is missing themed SVG recoloring" >&2; exit 1; }

grep -Eq 'onTapped: contextMenu\.open\(\)' "$control_item" \
  || { echo "Controls left click must open the controls menu" >&2; exit 1; }
grep -Eq 'signal openLauncher' "$context_menu" \
  || { echo "Controls menu is missing its launcher action signal" >&2; exit 1; }
grep -Eq 'text: "Open App Launcher"' "$context_menu" \
  || { echo "Controls menu is missing Open App Launcher" >&2; exit 1; }
grep -Eq 'Qt\.callLater\(\(\) => root\.activate\(\)\)' "$control_item" \
  || { echo "Launcher action is not wired to the configured command" >&2; exit 1; }

if grep -Eq 'onTapped: root\.activate\(\)' "$control_item"; then
  echo "Controls left click still launches directly" >&2
  exit 1
fi

echo "Lucide menu assets and controls-menu wiring are present"
