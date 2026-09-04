#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="${1:-$root_dir/research/fdm816/results/environment-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out_dir"

capture() {
  local name="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$out_dir/$name.txt" 2>&1 || true
}

{
  echo "captured_at=$(date --iso-8601=seconds)"
  echo "repository_root=$root_dir"
  echo "repository_head=$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}"
  echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
  echo "OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}"
} >"$out_dir/summary.txt"

capture uname uname -a
capture hyprland-json hyprctl version -j
capture hyprland-text hyprctl version
capture quickshell-qs qs --version
if command -v quickshell >/dev/null 2>&1; then
  capture quickshell-command quickshell --version
fi
if command -v omarchy >/dev/null 2>&1; then
  capture omarchy-version-flag omarchy --version
  capture omarchy-version-command omarchy version
fi
if command -v qtpaths6 >/dev/null 2>&1; then
  capture qtpaths-version qtpaths6 --qt-version
fi
if command -v qmake6 >/dev/null 2>&1; then
  capture qmake-version qmake6 -query QT_VERSION
fi

omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
if [[ -d "$omarchy_path/.git" ]]; then
  capture omarchy-git-head git -C "$omarchy_path" rev-parse HEAD
  capture omarchy-git-describe git -C "$omarchy_path" describe --always --dirty --tags
fi

if command -v pacman >/dev/null 2>&1; then
  packages=(
    hyprland
    quickshell
    quickshell-git
    aquamarine
    wayland
    wayland-protocols
    qt6-wayland
    xdg-desktop-portal-hyprland
  )
  for package in "${packages[@]}"; do
    capture "package-$package" pacman -Q "$package"
  done
fi

printf 'FDM-816 environment capture: %s\n' "$out_dir"
