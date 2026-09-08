#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d -t smartdock-resize.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cp -R "$repo_root/components" "$test_dir/components"
ln -s "$repo_root/assets" "$test_dir/assets"
cp "$repo_root/tests/runtime/workspace-resize.qml" "$test_dir/shell.qml"
mkdir "$test_dir/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$test_dir/imports/qs"
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$test_dir/imports" \
  timeout 5s qs -p "$test_dir" --no-color >"$test_dir/output" 2>&1 || {
    cat "$test_dir/output"
    exit 1
  }
grep 'workspace-resize: PASS' "$test_dir/output"
