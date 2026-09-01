#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for component in \
  DockLucideIcon.qml \
  DockSettingsSection.qml \
  DockSettingsToggleRow.qml; do
  test -s "$plugin_root/components/$component" || {
    printf 'Missing Dock Settings visual component: %s\n' "$component" >&2
    exit 1
  }
done

for icon in \
  sparkles palette panel-bottom mouse-pointer-click terminal rotate-ccw chevron-right; do
  test -s "$plugin_root/assets/lucide/$icon.svg" || {
    printf 'Missing Dock Settings Lucide icon: %s\n' "$icon" >&2
    exit 1
  }
done

rg -n 'ColorOverlay' "$plugin_root/components/DockLucideIcon.qml" >/dev/null
rg -n 'Util\.alpha\(Color\.accent' \
  "$plugin_root/components/DockSettingsSection.qml" >/dev/null
rg -n 'ToggleSwitch' \
  "$plugin_root/components/DockSettingsToggleRow.qml" >/dev/null

printf 'Dock Settings visual primitives and Lucide assets are present\n'
