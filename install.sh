#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
bin_home="${XDG_BIN_HOME:-$HOME/.local/bin}"
app_dir="$data_home/smartdock"
config_dir="$config_home/smartdock"
desktop_dir="$data_home/applications"
desktop_file="$desktop_dir/smartdock.desktop"
install_autostart=true
agent_assets_only=false

agent_ids=(
  smartdock-agent-pi
  smartdock-agent-oh-my-pi
  smartdock-agent-command-code
  smartdock-agent-cursor
  smartdock-agent-claude-code
  smartdock-agent-kilo-code
  smartdock-agent-cline
)
agent_commands=(pi omp commandcode cursor-agent claude kilo cline)
agent_extensions=(png svg svg svg svg svg svg)

usage() {
  cat <<'EOF'
Usage: install.sh [OPTION]

  --no-autostart  Do not create an XDG autostart entry
  --agent-assets-only
                  Install only the terminal-agent launchers and icons
  --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-autostart) install_autostart=false ;;
    --agent-assets-only) agent_assets_only=true ;;
    --help|-h) usage; exit ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for command in install cp rm; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

source_dir=""
script_path="${BASH_SOURCE[0]:-}"
if [[ -n "$script_path" ]]; then
  candidate="$(cd -- "$(dirname -- "$script_path")" 2>/dev/null && pwd || true)"
  if [[ -f "$candidate/shell.qml" && -d "$candidate/components" ]]; then
    source_dir="$candidate"
  fi
fi

if [[ -z "$source_dir" ]]; then
  echo "install.sh must be run from a SmartDock for Omarchy source tree." >&2
  echo "Clone or unpack your own SmartDock repository, then run ./install.sh." >&2
  exit 1
fi

agent_asset_dir="$source_dir/assets/terminal-agents"
svg_icon_dir="$data_home/icons/hicolor/scalable/apps"
raster_icon_dir="$data_home/icons/hicolor/256x256/apps"

install_agent_assets() {
  [[ -d "$agent_asset_dir" ]] || {
    echo "Terminal-agent assets not found: $agent_asset_dir" >&2
    exit 1
  }

  install -d "$desktop_dir" "$svg_icon_dir" "$raster_icon_dir"

  for index in "${!agent_ids[@]}"; do
    id="${agent_ids[$index]}"
    extension="${agent_extensions[$index]}"
    icon_dir="$svg_icon_dir"
    if [[ "$extension" != svg ]]; then
      icon_dir="$raster_icon_dir"
    fi
    install -m 0644 "$agent_asset_dir/$id.desktop" "$desktop_dir/$id.desktop"
    install -m 0644 "$agent_asset_dir/$id.$extension" "$icon_dir/$id.$extension"
  done
}

if $agent_assets_only; then
  install_agent_assets
  echo "Installed SmartDock terminal-agent launchers and icons."
  exit
fi

if ! command -v qs >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Quickshell is required but `qs` was not found.
On Arch Linux, install it with an AUR helper, for example:
  yay -S quickshell-git
EOF
  exit 1
fi

install -d "$app_dir" "$config_dir" "$bin_home" "$desktop_dir"
if [[ "$source_dir" != "$app_dir" ]]; then
  rm -rf -- "$app_dir/components"
  rm -rf -- "$app_dir/assets"
  cp -R -- "$source_dir/components" "$app_dir/components"
  cp -R -- "$source_dir/assets" "$app_dir/assets"
  install -m 0644 "$source_dir/shell.qml" "$app_dir/shell.qml"
  install -m 0644 "$source_dir/DockHost.qml" "$app_dir/DockHost.qml"
  install -m 0644 "$source_dir/LICENSE" "$app_dir/LICENSE"
  install -m 0755 "$source_dir/uninstall.sh" "$app_dir/uninstall.sh"
  install -m 0755 "$source_dir/install.sh" "$app_dir/install.sh"
  install -m 0755 "$source_dir/scripts/smartdock" "$bin_home/smartdock"
  printf '%s\n' "$source_dir" >"$app_dir/.source-dir"
fi
install_agent_assets

cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=SmartDock for Omarchy
Comment=Start or restart the Omarchy application dock
Exec="$bin_home/smartdock" restart
Icon=preferences-desktop
Terminal=false
Categories=Utility;
Keywords=Dock;Launcher;Hyprland;
StartupNotify=false
EOF
chmod 0644 "$desktop_file"

if [[ ! -f "$config_dir/dock.json" ]]; then
  install -m 0644 "$source_dir/config/dock.json" "$config_dir/dock.json"
  echo "Created configuration: $config_dir/dock.json"
else
  echo "Preserved configuration: $config_dir/dock.json"
fi

if $install_autostart; then
  "$bin_home/smartdock" autostart enable
fi

cat <<EOF

SmartDock for Omarchy installed successfully.

Run now:
  $bin_home/smartdock --daemonize

Application launcher:
  SmartDock for Omarchy

Configure:
  $config_dir/dock.json

Update later:
  $bin_home/smartdock --update
EOF

case ":$PATH:" in
  *":$bin_home:"*) ;;
  *) echo; echo "Note: add $bin_home to PATH to run smartdock by name." ;;
esac
