#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host="$script_dir/../DockHost.qml"
dock="$script_dir/../components/Dock.qml"

grep -Eq 'property bool settingsLoaded: false' "$host" \
  || { echo "Trash polling must wait for the first settings load" >&2; exit 1; }
grep -Eq 'property bool showTrashSetting: true' "$host" \
  || { echo "Trash visibility must use explicit host-owned state" >&2; exit 1; }
grep -Eq 'showTrashSetting = parsed\.showTrash' "$host" \
  || { echo "Reloaded Trash visibility must update host-owned state" >&2; exit 1; }
grep -Eq 'running: root\.settingsLoaded && root\.showTrash' "$host" \
  || { echo "Trash polling must stop when settings hide Trash" >&2; exit 1; }
grep -Eq 'showTrash: root\.showTrash' "$host" \
  || { echo "Dock instances must consume host-owned Trash visibility" >&2; exit 1; }
grep -Eq 'required property bool showTrash' "$dock" \
  || { echo "Dock must receive Trash visibility explicitly" >&2; exit 1; }

echo "Show Trash reload state is explicit and polling is load-gated"
