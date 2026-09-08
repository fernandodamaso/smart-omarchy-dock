#!/usr/bin/env bash
set -euo pipefail

component="components/DockActionDropdown.qml"
local_test="local-tests/tst_action_dropdown_settings.qml"
local_runner="tests/run_action_dropdown_settings.sh"

if ! rg -q '^[[:space:]]*Dropdown[[:space:]]*\{' "$component"; then
  echo "DockActionDropdown must compose qs.Ui.Dropdown" >&2
  exit 1
fi

if ! rg -q 'showLabel:[[:space:]]*false' "$component"; then
  echo "DockActionDropdown must preserve SmartDock label composition" >&2
  exit 1
fi

if ! rg -q 'Qt\.binding' "$component"; then
  echo "DockActionDropdown must restore the settings-driven native value binding after selection" >&2
  exit 1
fi

for obsolete in \
  '^[[:space:]]*Popup[[:space:]]*\{' \
  '^[[:space:]]*ListView[[:space:]]*\{' \
  'Keys\.onPressed' \
  'delegate:[[:space:]]*Rectangle'; do
  if rg -q "$obsolete" "$component"; then
    echo "DockActionDropdown still contains superseded custom dropdown internals: $obsolete" >&2
    exit 1
  fi
done

test -f "$local_test"
bash -n "$local_runner"
test -f tests/stubs/Quickshell/qmldir
test -f tests/stubs/Quickshell/Io/FileView.qml
test -f tests/stubs/Quickshell/Io/Process.qml
test -f tests/stubs/Quickshell/Io/StdioCollector.qml
rg -q 'tests/stubs' "$local_runner"
rg -q 'OMARCHY_PATH:-/usr/share/omarchy' "$local_runner"

echo "Native action-dropdown structural guard passed."
