#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_path="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
shell_root="$omarchy_path/shell"

for module in Commons Ui; do
  if [[ ! -d "$shell_root/$module" ]]; then
    echo "Missing Omarchy shell module: $shell_root/$module" >&2
    echo "Set OMARCHY_PATH to the installed Omarchy checkout and retry." >&2
    exit 2
  fi
done

if [[ ! -f "$shell_root/Ui/Dropdown.qml" ]]; then
  echo "Installed Omarchy does not expose shell/Ui/Dropdown.qml" >&2
  exit 2
fi

qml_test_runner="$(command -v qmltestrunner || true)"
if [[ -z "$qml_test_runner" && -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  qml_test_runner="/usr/lib/qt6/bin/qmltestrunner"
fi
if [[ -z "$qml_test_runner" ]]; then
  echo "qmltestrunner was not found in PATH." >&2
  exit 2
fi

module_root="$(mktemp -d)"
trap 'rm -rf "$module_root"' EXIT
mkdir -p "$module_root/qs"
ln -s "$shell_root/Commons" "$module_root/qs/Commons"
ln -s "$shell_root/Ui" "$module_root/qs/Ui"

cd "$repo_root"
QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
  "$qml_test_runner" \
  -input local-tests \
  -import "$module_root" \
  -import components
