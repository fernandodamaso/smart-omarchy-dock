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

usage() {
  cat <<'EOF'
Usage: install.sh [OPTION]

  --no-autostart  Do not create an XDG autostart entry
  --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-autostart) install_autostart=false ;;
    --help|-h) usage; exit ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ! command -v qs >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Quickshell is required but `qs` was not found.
On Arch Linux, install it with an AUR helper, for example:
  yay -S quickshell-git
EOF
  exit 1
fi

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

install -d "$app_dir" "$config_dir" "$bin_home" "$desktop_dir"
rm -rf -- "$app_dir/components"
cp -R -- "$source_dir/components" "$app_dir/components"
install -m 0644 "$source_dir/shell.qml" "$app_dir/shell.qml"
install -m 0644 "$source_dir/DockHost.qml" "$app_dir/DockHost.qml"
install -m 0644 "$source_dir/LICENSE" "$app_dir/LICENSE"
install -m 0755 "$source_dir/uninstall.sh" "$app_dir/uninstall.sh"
install -m 0755 "$source_dir/install.sh" "$app_dir/install.sh"
install -m 0755 "$source_dir/scripts/smartdock" "$bin_home/smartdock"

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
