#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d -t smartdock-animations.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cp -R "$repo_root/components" "$test_dir/components"
cp "$repo_root/tests/runtime/interface-animations.qml" "$test_dir/shell.qml"
mkdir "$test_dir/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$test_dir/imports/qs"
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$test_dir/imports" \
  timeout 6s qs -p "$test_dir" --no-color >"$test_dir/output" 2>&1 || {
    cat "$test_dir/output"
    exit 1
  }
if grep -Eq 'WARN scene:|ERROR|Error:' "$test_dir/output"; then
  cat "$test_dir/output"
  exit 1
fi
grep 'interface-animations: PASS' "$test_dir/output"
