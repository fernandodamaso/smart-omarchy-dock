#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
overlay="$project_dir/Overlay.qml"
launcher="$project_dir/scripts/dockrail"
compat_launcher="$project_dir/scripts/smartdock"

fail() {
  echo "XDG config path guard: $*" >&2
  exit 1
}

grep -F 'Quickshell.env("XDG_CONFIG_HOME")' "$overlay" >/dev/null \
  || fail "Overlay.qml must honor XDG_CONFIG_HOME"
grep -F 'Quickshell.env("HOME") + "/.config"' "$overlay" >/dev/null \
  || fail "Overlay.qml must fall back to HOME/.config"

if grep -F 'configPath: Quickshell.env("HOME") + "/.config/smartdock/dock.json"' \
    "$overlay" >/dev/null; then
  fail "Overlay.qml must not hardcode HOME/.config when XDG_CONFIG_HOME is set"
fi

grep -F 'config_home="${XDG_CONFIG_HOME:-$HOME/.config}"' "$launcher" >/dev/null \
  || fail "canonical standalone launcher must remain XDG_CONFIG_HOME-aware"

grep -F 'exec bash "$script_dir/dockrail" "$@"' "$compat_launcher" >/dev/null \
  || fail "smartdock compatibility launcher must delegate to dockrail"

echo "XDG config path guard passed"
