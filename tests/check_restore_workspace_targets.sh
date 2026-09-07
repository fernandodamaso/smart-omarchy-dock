#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_restore_workspace_targets: $*" >&2
  exit 1
}

model="components/DockModel.js"
actions="components/DockWindowActions.qml"

grep -Fq 'function normalizeWorkspaceTarget(value)' "$model" \
  || fail "workspace target normalizer is missing"
grep -Fq 'return DockModel.normalizeWorkspaceTarget(target)' "$actions" \
  || fail "DockWindowActions.workspaceTarget must use the restore target validator"

echo "check_restore_workspace_targets: PASS"
