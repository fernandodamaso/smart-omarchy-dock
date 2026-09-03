#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_focus_indicator: $*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing expected focus-indicator wiring in $file: $pattern"
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "unexpected legacy or out-of-scope focus-indicator wiring in $file: $pattern"
  fi
}

[[ -f components/DockApplicationStateIndicator.qml ]] \
  || fail "components/DockApplicationStateIndicator.qml does not exist"

require_pattern '^function hasActiveMember\(' components/DockModel.js
require_pattern '^function applicationStateIndicatorGeometry\(' components/DockModel.js
require_pattern 'required property string position' components/DockApplicationStateIndicator.qml
require_pattern 'required property real iconWidth' components/DockApplicationStateIndicator.qml
require_pattern 'required property real iconHeight' components/DockApplicationStateIndicator.qml
require_pattern 'required property bool running' components/DockApplicationStateIndicator.qml
require_pattern 'required property bool focused' components/DockApplicationStateIndicator.qml
require_pattern 'DockModel\.applicationStateIndicatorGeometry' components/DockApplicationStateIndicator.qml
require_pattern 'required property bool focused' components/DockItem.qml
require_pattern 'DockApplicationStateIndicator[[:space:]]*\{' components/DockItem.qml
require_pattern 'runningColor:[[:space:]]*Color\.foreground' components/DockItem.qml
require_pattern 'focusedColor:[[:space:]]*Color\.accent' components/DockItem.qml
require_pattern 'root\.focused[[:space:]]*\?[[:space:]]*"focused application"' components/DockItem.qml
require_pattern '"running application"' components/DockItem.qml
require_pattern 'focused:[[:space:]]*root\.activeToplevel' components/Dock.qml
require_pattern 'modelData\.toplevels\.indexOf\(root\.activeToplevel\)' components/Dock.qml
require_pattern 'root\.activeToplevel' components/Dock.qml

reject_pattern 'color:[[:space:]]*root\.visibleWindowCount[[:space:]]*>[[:space:]]*0[[:space:]]*\?[[:space:]]*Color\.foreground' components/DockItem.qml
reject_pattern 'focusIndicator' config/dock.json
reject_pattern 'focusedIndicator' config/dock.json

echo "check_focus_indicator: PASS"
