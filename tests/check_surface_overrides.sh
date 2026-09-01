#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dock_qml="$plugin_root/components/Dock.qml"
settings_qml="$plugin_root/components/DockSettings.qml"

for token in \
  backgroundColorEnabled \
  backgroundColor \
  borderColorEnabled \
  borderColor \
  borderWidthEnabled \
  borderWidth; do
  if ! rg -n "$token" "$dock_qml" "$settings_qml" >/dev/null; then
    printf 'Surface override setting is missing: %s\n' "$token" >&2
    exit 1
  fi
done

if ! rg -n 'effectiveColor|effectiveBorderWidth' "$dock_qml" >/dev/null; then
  printf 'Dock surface must resolve enabled overrides against theme tokens\n' >&2
  exit 1
fi

for label in 'Dock surface' 'Background opacity' 'Theme default' \
  'Custom hex' 'Custom width'; do
  rg -n "$label" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing progressive surface control: %s\n' "$label" >&2
    exit 1
  }
done

if rg -n 'Use custom background color|Use custom border color|Use custom border width' \
    "$settings_qml" >/dev/null; then
  printf 'Dock Settings still exposes the old always-expanded override rows\n' >&2
  exit 1
fi

if ! rg -n 'settingsPatchCommitted|settingsPatchRequested|saveSettings\(patch\)' \
    "$settings_qml" "$dock_qml" "$plugin_root/DockHost.qml" >/dev/null; then
  printf 'Surface selectors must persist default/token/custom changes atomically\n' >&2
  exit 1
fi
