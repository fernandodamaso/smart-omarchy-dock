#!/usr/bin/env bash
set -euo pipefail

# Explicit guard: never launch this source fixture alongside the installed dock.
if [[ "${SMARTDOCK_ISOLATED_RUNTIME:-}" != "1" ]]; then
  printf 'Run in the isolated guest from docs/DEV_SESSIONS.md with SMARTDOCK_ISOLATED_RUNTIME=1.\n' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d -t smartdock-desktop-model.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cp -R "$repo_root/components" "$test_dir/components"
ln -s "$repo_root/assets" "$test_dir/assets"
cp "$repo_root/tests/runtime/desktop-model.qml" "$test_dir/shell.qml"
mkdir "$test_dir/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$test_dir/imports/qs"
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$test_dir/imports" \
  timeout 8s qs -p "$test_dir" --no-color >"$test_dir/output" 2>&1 || {
    cat "$test_dir/output"
    exit 1
  }
if grep -E 'ERROR|Error:' "$test_dir/output"; then
  cat "$test_dir/output"
  exit 1
fi
grep -F 'desktop-model: PASS' "$test_dir/output"
