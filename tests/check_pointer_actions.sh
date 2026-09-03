#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_pointer_actions: $*" >&2
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
    fail "unexpected FDM-808/runtime wiring in $file: $pattern"
  fi
}

for key in clickAction middleClickAction shiftClickAction scrollAction; do
  require_pattern "\"${key}\"" config/dock.json
  require_pattern "${key}:" DockHost.qml
  require_pattern "${key}:" components/DockModel.js
  require_pattern "${key}" README.md
  require_pattern "root\.current\(\"${key}\"\)" components/DockSettings.qml
done

require_pattern 'normalizeApplicationActionConfig' components/Dock.qml
require_pattern 'applicationActions:[[:space:]]*root\.applicationActions' components/Dock.qml
require_pattern 'required property var applicationActions' components/DockItem.qml
require_pattern 'function dispatchApplicationAction\(' components/DockItem.qml
require_pattern 'resolveApplicationPointerAction' components/DockItem.qml

require_pattern 'acceptedButtons:[[:space:]]*Qt\.LeftButton' components/DockItem.qml
require_pattern 'acceptedModifiers:[[:space:]]*Qt\.KeyboardModifierMask' components/DockItem.qml
require_pattern 'eventPoint\.modifiers' components/DockItem.qml
require_pattern 'acceptedButtons:[[:space:]]*Qt\.MiddleButton' components/DockItem.qml
require_pattern 'acceptedButtons:[[:space:]]*Qt\.RightButton' components/DockItem.qml
require_pattern 'contextMenu\.open\(\)' components/DockItem.qml
require_pattern 'DragHandler[[:space:]]*\{' components/DockItem.qml
require_pattern 'acceptedModifiers:[[:space:]]*Qt\.NoModifier' components/DockItem.qml

require_pattern 'WheelHandler[[:space:]]*\{' components/DockItem.qml
require_pattern 'DockModel\.accumulateWheelSteps' components/DockItem.qml
require_pattern 'root\.applicationActions\.scrollAction' components/DockItem.qml
require_pattern 'event\.accepted = cycled' components/DockItem.qml

require_pattern 'function focusToplevels\(' components/DockWindowActions.qml
require_pattern 'function minimizeRestoreToplevels\(' components/DockWindowActions.qml
require_pattern 'function closeToplevels\(' components/DockWindowActions.qml
require_pattern 'function showToplevelPreviews\(' components/DockWindowActions.qml
require_pattern 'previewRequested' components/DockItem.qml
require_pattern 'DockWindowPreview[[:space:]]*\{' components/Dock.qml

[[ -f components/DockActionDropdown.qml ]] \
  || fail "components/DockActionDropdown.qml does not exist"
selector_count="$(grep -Ec '^[[:space:]]*DockActionDropdown[[:space:]]*\{' components/DockSettings.qml || true)"
[[ "$selector_count" -eq 4 ]] \
  || fail "Dock Settings must expose exactly four application action selectors (found $selector_count)"
require_pattern 'applicationActionOptions\(\)' components/DockSettings.qml
require_pattern 'label:[[:space:]]*"Left click"' components/DockSettings.qml
require_pattern 'label:[[:space:]]*"Middle click"' components/DockSettings.qml
require_pattern 'label:[[:space:]]*"Shift \+ left click"' components/DockSettings.qml
require_pattern 'label:[[:space:]]*"Scroll"' components/DockSettings.qml
reject_pattern 'id:[[:space:]]*clickActionGroup' components/DockSettings.qml
reject_pattern 'label:[[:space:]]*"Focus"' components/DockModel.js
reject_pattern 'label:[[:space:]]*"Launch"' components/DockModel.js

# FDM-819 ownership remains singular.
host_instances="$(grep -Ec '^[[:space:]]*DockWindowActions[[:space:]]*\{' DockHost.qml || true)"
[[ "$host_instances" -eq 1 ]] \
  || fail "DockHost.qml must still own exactly one DockWindowActions instance"
reject_pattern 'property var minimizedOrigins' components/DockItem.qml

require_pattern 'Left click' README.md
require_pattern 'Shift\+left' README.md
require_pattern 'Middle click' README.md
require_pattern 'cycle-windows' README.md

echo "check_pointer_actions: PASS"
