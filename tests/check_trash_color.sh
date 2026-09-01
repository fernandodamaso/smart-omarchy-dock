#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
trash_qml="$script_dir/../components/DockTrashItem.qml"
trash_svg="$script_dir/../assets/lucide/trash-2.svg"

test -s "$trash_svg" \
  || { echo "Trash must use the bundled Lucide SVG" >&2; exit 1; }
grep -Eq '^[[:space:]]*stroke="currentColor"[[:space:]]*$' "$trash_svg" \
  || { echo "Bundled Trash artwork is not a Lucide currentColor SVG" >&2; exit 1; }
grep -Eq 'source: Qt\.resolvedUrl\("\.\./assets/lucide/trash-2\.svg"\)' "$trash_qml" \
  || { echo "Dock Trash is not using the bundled Lucide artwork" >&2; exit 1; }

grep -Eq 'color: trashHover\.hovered \? Color\.accent : "#ffffff"' "$trash_qml" \
  || { echo "Trash idle glyph must use opaque white" >&2; exit 1; }
grep -Eq '^[[:space:]]*opacity: 1\.0[[:space:]]*$' "$trash_qml" \
  || { echo "Trash glyph must remain fully opaque" >&2; exit 1; }
grep -Eq '^[[:space:]]*layer\.enabled: true[[:space:]]*$' "$trash_qml" \
  || { echo "Trash source image must expose a layer for color-effect recoloring" >&2; exit 1; }
grep -Eq '^[[:space:]]*import Qt5Compat\.GraphicalEffects[[:space:]]*$' "$trash_qml" \
  || { echo "Trash glyph must use an exact color overlay" >&2; exit 1; }
grep -Eq '^[[:space:]]*ColorOverlay \{' "$trash_qml" \
  || { echo "Trash glyph is missing its color overlay" >&2; exit 1; }
if grep -Eq 'trashStateKnown \? 0\.94 : 0\.58|colorizationColor: trashHover\.hovered \? Color\.accent : Color\.foreground' "$trash_qml"; then
  echo "Trash glyph still dims or inherits the gray foreground token" >&2
  exit 1
fi

echo "Trash idle glyph styling is opaque white"
