#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
components=(DockItem.qml DockControlItem.qml DockTrashItem.qml)

for component in "${components[@]}"; do
  qml="$script_dir/../components/$component"
  block="$(sed -n '/id: iconContainer/,/scale: root.iconScale/p' "$qml")"
  grep -Fq 'x: (root.width - root.iconSize) / 2' <<<"$block" \
    || { echo "$component does not center the icon horizontally" >&2; exit 1; }
  grep -Fq 'y: (root.height - root.iconSize) / 2' <<<"$block" \
    || { echo "$component does not center the icon vertically" >&2; exit 1; }
done

echo "Dock icon containers use symmetric cross-axis alignment"
