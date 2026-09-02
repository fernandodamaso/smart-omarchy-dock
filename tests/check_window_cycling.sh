#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'window-cycling check failed: %s\n' "$*" >&2
  exit 1
}

require_pattern() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing '$pattern' in $file"
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "unexpected '$pattern' in $file"
  fi
}

require_pattern 'function cycleTargetIndex\(' components/DockWindowModel.js
require_pattern 'function cycleGroupMember\(' components/DockWindowModel.js
require_pattern 'function dominantVerticalWheelDelta\(' components/DockWindowModel.js
require_pattern 'function wheelRemainderForTimestamp\(' components/DockWindowModel.js
require_pattern 'function cycleToplevels\(' components/DockWindowActions.qml
require_pattern 'readonly property var activeToplevel:[[:space:]]*ToplevelManager\.activeToplevel' components/DockWindowActions.qml
require_pattern 'WheelHandler[[:space:]]*\{' components/DockItem.qml
require_pattern 'root\.runningCount >= 2' components/DockItem.qml
require_pattern 'root\.applicationActions\.scrollAction === "cycle-windows"' components/DockItem.qml
require_pattern 'DockWindowModel\.dominantVerticalWheelDelta' components/DockItem.qml
require_pattern 'DockModel\.accumulateWheelSteps' components/DockItem.qml
require_pattern 'wheelRemainderForTimestamp' components/DockItem.qml
require_pattern '220' components/DockItem.qml
require_pattern 'event\.accepted = cycled' components/DockItem.qml
require_pattern 'root\.windowActions\.activeToplevel' components/DockItem.qml

# FDM-819 ownership stays singular. Dock/DockItem may consume host-owned state,
# but they must not own minimized-origin state or instantiate another controller.
host_instances="$(grep -Ec '^[[:space:]]*DockWindowActions[[:space:]]*\{' DockHost.qml || true)"
[[ "$host_instances" -eq 1 ]] \
  || fail "DockHost.qml must own exactly one DockWindowActions instance (found $host_instances)"
reject_pattern '^[[:space:]]*DockWindowActions[[:space:]]*\{' components/DockItem.qml
reject_pattern '^[[:space:]]*DockWindowActions[[:space:]]*\{' components/Dock.qml
reject_pattern 'property[[:space:]]+var[[:space:]]+minimizedOrigins([[:space:]]|:)' components/DockItem.qml
reject_pattern 'property[[:space:]]+var[[:space:]]+minimizedOrigins([[:space:]]|:)' components/Dock.qml
require_pattern 'windowActions\.minimizedOriginsSnapshot' components/Dock.qml

require_pattern 'Grouped-window wheel cycling' README.md
require_pattern 'mouse-wheel cycling' AGENTS.md

printf 'window-cycling structural checks passed\n'
