#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
control_qml="$script_dir/../components/DockControlItem.qml"

foreground_count=$(grep -Ec '^[[:space:]]*color:[[:space:]]*Color\.foreground[[:space:]]*$' "$control_qml")
if (( foreground_count < 2 )); then
  echo "Dock Controls glyph must keep its foreground color" >&2
  exit 1
fi

if grep -Eq 'color:.*mouse\.hovered.*Color\.accent' "$control_qml"; then
  echo "Dock Controls glyph still changes to the accent color on hover" >&2
  exit 1
fi

echo "Dock Controls glyph keeps its foreground color on hover"
