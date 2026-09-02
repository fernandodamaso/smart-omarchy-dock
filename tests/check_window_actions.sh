#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_window_actions: $*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing expected wiring in $file: $pattern"
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "unexpected duplicated ownership in $file: $pattern"
  fi
}

[[ -f components/DockWindowActions.qml ]] \
  || fail "components/DockWindowActions.qml does not exist"
[[ -f components/DockWindowModel.js ]] \
  || fail "components/DockWindowModel.js does not exist"

host_instances="$(grep -Ec '^[[:space:]]*DockWindowActions[[:space:]]*\{' DockHost.qml || true)"
[[ "$host_instances" -eq 1 ]] \
  || fail "DockHost.qml must instantiate DockWindowActions exactly once (found $host_instances)"

for file in components/Dock.qml components/DockItem.qml components/DockContextMenu.qml components/DockControlItem.qml; do
  reject_pattern '^[[:space:]]*DockWindowActions[[:space:]]*\{' "$file"
  require_pattern 'property var windowActions' "$file"
done

require_pattern 'windowActions:[[:space:]]*root\.windowActions' DockHost.qml
require_pattern 'windowActions:[[:space:]]*root\.windowActions' components/Dock.qml
require_pattern 'windowActions:[[:space:]]*root\.windowActions' components/DockItem.qml
require_pattern 'windowActions:[[:space:]]*root\.windowActions' components/DockControlItem.qml

reject_pattern 'property var minimizedOrigins' components/DockContextMenu.qml
require_pattern 'property var minimizedOrigins' components/DockWindowActions.qml
require_pattern 'readonly property var minimizedOriginsSnapshot' components/DockWindowActions.qml

require_pattern 'root\.windowActions\.activateToplevel' components/DockItem.qml
require_pattern 'root\.windowActions\.minimizeToplevel' components/DockContextMenu.qml
require_pattern 'root\.windowActions\.restoreToplevel' components/DockContextMenu.qml
require_pattern 'root\.windowActions\.closeToplevel' components/DockContextMenu.qml
require_pattern 'root\.windowActions\.forgetOrigin' components/DockContextMenu.qml

echo "check_window_actions: PASS"
