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

if ! rg -n 'Use custom background color|Use custom border color|Use custom border width' \
    "$settings_qml" >/dev/null; then
  printf 'Dock Settings must expose independent surface override controls\n' >&2
  exit 1
fi
