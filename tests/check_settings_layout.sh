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

echo "Dock Settings uses a responsive wide layout"
