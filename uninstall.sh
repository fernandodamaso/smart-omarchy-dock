#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
bin_home="${XDG_BIN_HOME:-$HOME/.local/bin}"
app_dir="$data_home/smartdock"
config_dir="$config_home/smartdock"
desktop_file="$data_home/applications/smartdock.desktop"
purge=false

case "${1:-}" in
  --purge) purge=true ;;
  --help|-h)
    cat <<'EOF'
Usage: uninstall.sh [--purge]

By default, user configuration is preserved. Use --purge to remove it.
EOF
    exit
    ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

if command -v qs >/dev/null 2>&1; then
  qs kill -p "$app_dir" --any-display >/dev/null 2>&1 || true
fi

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
