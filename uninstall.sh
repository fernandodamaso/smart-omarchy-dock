#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
bin_home="${XDG_BIN_HOME:-$HOME/.local/bin}"
app_dir="$data_home/smartdock"
config_dir="$config_home/smartdock"
desktop_file="$data_home/applications/smartdock.desktop"
purge=false
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
agent_extensions=(png svg svg svg svg svg svg)
desktop_dir="$data_home/applications"
svg_icon_dir="$data_home/icons/hicolor/scalable/apps"
raster_icon_dir="$data_home/icons/hicolor/256x256/apps"

usage() {
  cat <<'EOF'
Usage: uninstall.sh [OPTION]

  --agent-assets-only
                  Remove only the terminal-agent launchers and icons
  --purge         Remove SmartDock and its configuration
  --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) purge=true ;;
    --agent-assets-only) agent_assets_only=true ;;
    --help|-h) usage; exit ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if $agent_assets_only && $purge; then
  echo "--agent-assets-only cannot be combined with --purge." >&2
  exit 2
fi

remove_agent_assets() {
  for index in "${!agent_ids[@]}"; do
    id="${agent_ids[$index]}"
    extension="${agent_extensions[$index]}"
    rm -f -- "$desktop_dir/$id.desktop"
    if [[ "$extension" == svg ]]; then
      rm -f -- "$svg_icon_dir/$id.svg"
    else
      rm -f -- "$raster_icon_dir/$id.$extension"
    fi
  done
}

if $agent_assets_only; then
  remove_agent_assets
  echo "Removed SmartDock terminal-agent launchers and icons."
  exit
fi

if command -v qs >/dev/null 2>&1; then
  qs kill -p "$app_dir" --any-display >/dev/null 2>&1 || true
fi

remove_agent_assets
rm -f -- "$config_home/autostart/smartdock.desktop"
rm -f -- "$desktop_file"
rm -f -- "$bin_home/smartdock"
rm -rf -- "$app_dir"

if $purge; then
  rm -rf -- "$config_dir"
  echo "Removed SmartDock for Omarchy and its configuration."
else
  echo "Removed SmartDock for Omarchy. Configuration preserved at:"
  echo "  $config_dir/dock.json"
fi
