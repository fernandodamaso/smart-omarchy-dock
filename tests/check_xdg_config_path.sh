#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
overlay="$project_dir/Overlay.qml"
service="$project_dir/Service.qml"
paths="$project_dir/scripts/dockrail_paths.py"
launcher="$project_dir/scripts/dockrail"
compat_launcher="$project_dir/scripts/smartdock"

fail() {
  echo "XDG config path guard: $*" >&2
  exit 1
}

grep -F 'configPath: root.pluginService.migration.configPath' "$overlay" >/dev/null \
  || fail "plugin overlay must consume the service-owned resolved config path"
grep -F 'DockMigrationBootstrap' "$service" >/dev/null \
  || fail "plugin service must own the migration bootstrap"
grep -F '"XDG_CONFIG_HOME"' "$paths" >/dev/null \
  || fail "shared path resolver must honor XDG_CONFIG_HOME"
grep -F 'canonical_config_root = config_home / "dockrail"' "$paths" >/dev/null \
  || fail "shared path resolver must select the canonical Dockrail config root"
grep -F 'legacy_config_root = config_home / "smartdock"' "$paths" >/dev/null \
  || fail "shared path resolver must retain the SmartDock compatibility root"
grep -F 'config_home="${XDG_CONFIG_HOME:-$HOME/.config}"' "$launcher" >/dev/null \
  || fail "canonical standalone launcher must remain XDG_CONFIG_HOME-aware"
grep -F 'exec bash "$script_dir/dockrail" "$@"' "$compat_launcher" >/dev/null \
  || fail "smartdock compatibility launcher must delegate to dockrail"

echo "XDG config path guard passed"
