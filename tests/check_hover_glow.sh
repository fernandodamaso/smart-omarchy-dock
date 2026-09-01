#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for relative_path in \
  components/DockItem.qml \
  components/DockControlItem.qml \
  components/DockTrashItem.qml; do
  qml_file="$plugin_root/$relative_path"

  if ! rg -n '^    RectangularShadow \{' "$qml_file" >/dev/null; then
    printf '%s must provide a hover glow behind the icon\n' "$relative_path" >&2
    exit 1
  fi

  if rg -n 'Style\.hoverFillFor|Border\.controlSpec\("hover-cursor"' \
      "$qml_file" >/dev/null; then
    printf '%s still uses the hover fill/border tile treatment\n' "$relative_path" >&2
    exit 1
  fi

  for token in hoverGlowEnabled hoverGlowOpacity hoverGlowRadius; do
    if ! rg -n "$token" "$qml_file" >/dev/null; then
      printf '%s must consume %s\n' "$relative_path" "$token" >&2
      exit 1
    fi
  done
done

settings="$plugin_root/components/DockSettings.qml"
for token in hoverGlowEnabled hoverGlowOpacity hoverGlowRadius; do
  if ! rg -n "$token" "$settings" >/dev/null; then
    printf 'Dock Settings must expose %s\n' "$token" >&2
    exit 1
  fi
done

if ! rg -n 'hoverGlowEnabled|hoverGlowOpacity|hoverGlowRadius' \
    "$plugin_root/components/Dock.qml" >/dev/null; then
  printf 'Dock must pass hover glow settings to its icon components\n' >&2
  exit 1
fi
