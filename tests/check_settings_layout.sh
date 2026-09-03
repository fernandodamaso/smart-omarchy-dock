#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
settings_qml="$script_dir/../components/DockSettings.qml"

grep -Eq 'panelWidth: Math\.min\(980,' "$settings_qml" \
  || { echo "Dock Settings should use a wide 980px desktop layout" >&2; exit 1; }
grep -Eq 'readonly property bool wideLayout' "$settings_qml" \
  || { echo "Dock Settings is missing its responsive wide-layout breakpoint" >&2; exit 1; }
grep -Eq '^[[:space:]]*Flow \{' "$settings_qml" \
  || { echo "Dock Settings should use responsive flow sections" >&2; exit 1; }
grep -Eq 'width: root\.wideLayout \?' "$settings_qml" \
  || { echo "Dock Settings flow children should switch between columns and rows" >&2; exit 1; }
grep -Eq '^[[:space:]]*flow: Flow\.LeftToRight[[:space:]]*$' "$settings_qml" \
  || { echo "Dock Settings responsive flows should use width-driven wrapping" >&2; exit 1; }
if grep -Eq 'Flow\.TopToBottom' "$settings_qml"; then
  echo "Dock Settings should not use unbounded top-to-bottom flows" >&2
  exit 1
fi
if grep -Eq 'panelWidth: Math\.min\(460,' "$settings_qml"; then
  echo "Dock Settings still has the old narrow width cap" >&2
  exit 1
fi

grep -Eq 'panelHeight: Math\.min\(820,' "$settings_qml" \
  || { echo "Dock Settings should leave the bottom dock visible" >&2; exit 1; }
grep -Eq 'id: settingsHeader' "$settings_qml" \
  || { echo "Dock Settings is missing its fixed header" >&2; exit 1; }
grep -Eq 'id: settingsContent' "$settings_qml" \
  || { echo "Dock Settings is missing its scrollable content area" >&2; exit 1; }
grep -Eq 'id: settingsFooter' "$settings_qml" \
  || { echo "Dock Settings is missing its sticky footer" >&2; exit 1; }
grep -Eq 'property bool advancedExpanded' "$settings_qml" \
  || { echo "Dock Settings is missing UI-only launcher disclosure state" >&2; exit 1; }
grep -Eq 'property bool compactControls' "$settings_qml" \
  || { echo "Dock Settings is missing its narrow control layout breakpoint" >&2; exit 1; }
rg -n 'compactControls: panelWidth < 560' "$settings_qml" >/dev/null \
  || { echo "Narrow settings controls must stack below 560 px" >&2; exit 1; }

for section in 'Icons' 'Hover effect' 'Dock surface' 'Workspace badge' 'Layout' 'Behavior'; do
  rg -n "title: \"$section\"" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing section: %s\n' "$section" >&2
    exit 1
  }
done

for icon in maximize-2 sparkles palette layout-grid panel-bottom mouse-pointer-click; do
  rg -n "iconName: \"$icon\"" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing section icon: %s\n' "$icon" >&2
    exit 1
  }
done

if rg -n 'text: ".*Appearance"' "$settings_qml" >/dev/null; then
  echo "The old mixed Appearance section should be removed" >&2
  exit 1
fi

for text in 'Advanced launcher settings' 'Reset to defaults' 'Close'; do
  rg -n "$text" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing action: %s\n' "$text" >&2
    exit 1
  }
done

rg -n 'iconName: "terminal"' "$settings_qml" >/dev/null \
  || { echo "Launcher disclosure is missing its Lucide icon" >&2; exit 1; }
rg -n 'iconName: "rotate-ccw"' "$settings_qml" >/dev/null \
  || { echo "Reset action is missing its Lucide icon" >&2; exit 1; }
rg -n 'Color\.urgent' "$settings_qml" >/dev/null \
  || { echo "Reset action must use the Omarchy urgent token" >&2; exit 1; }

echo "Dock Settings uses a responsive wide layout"
