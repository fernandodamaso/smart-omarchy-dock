#!/usr/bin/env bash
# CLI installation owns no desktop/plugin state and cooperates with standalone.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d -t 'smartdock-cli-install.XXXXXX')"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home with spaces"
export XDG_DATA_HOME="$HOME/data" XDG_CONFIG_HOME="$HOME/config"
export XDG_BIN_HOME="$HOME/bin" XDG_CACHE_HOME="$HOME/cache"
mkdir -p "$tmp/tools"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$QS_INSTALL_LOG"\n' >"$tmp/tools/qs"
chmod +x "$tmp/tools/qs"
export QS_INSTALL_LOG="$tmp/qs.log"
export PATH="$tmp/tools:$PATH"

cli_install() { bash "$repo/install.sh" --cli-only; }
full_install() { bash "$repo/install.sh" --no-autostart; }
cli_remove() { bash "$repo/uninstall.sh" --cli-only; }
full_remove() { bash "$repo/uninstall.sh"; }

cli_install
cli_install
test -x "$XDG_BIN_HOME/smartdock"
test -f "$XDG_DATA_HOME/smartdock-cli/scripts/smartdock_cli.py"
test -f "$XDG_DATA_HOME/smartdock-cli/config/settings-schema.json"
test -f "$XDG_DATA_HOME/smartdock-cli/config/dock.json"
test -f "$XDG_DATA_HOME/smartdock-cli/docs/AGENT_CONFIGURATION.md"
test "$(cat "$XDG_DATA_HOME/smartdock-cli/.source-dir")" = "$repo"
test ! -e "$XDG_DATA_HOME/smartdock"
test ! -e "$XDG_DATA_HOME/applications"
test ! -e "$XDG_DATA_HOME/icons"
test ! -e "$XDG_CONFIG_HOME"
test ! -e "$XDG_CACHE_HOME"
test ! -e "$QS_INSTALL_LOG"
"$XDG_BIN_HOME/smartdock" agent-guide >/dev/null
"$XDG_BIN_HOME/smartdock" help >/dev/null
test ! -e "$QS_INSTALL_LOG"
if bash "$repo/uninstall.sh" --cli-only --purge; then
  echo 'Client-only purge must be rejected' >&2
  exit 1
fi
test -x "$XDG_BIN_HOME/smartdock"

# Client first, then standalone: client removal retains standalone ownership.
full_install
printf '{"pinned":["Keep.Me"],"extension":true}\n' >"$XDG_CONFIG_HOME/smartdock/dock.json"
config_before="$(cat "$XDG_CONFIG_HOME/smartdock/dock.json")"
source_before="$(cat "$XDG_DATA_HOME/smartdock/.source-dir")"
cli_remove
test -x "$XDG_BIN_HOME/smartdock"
test -f "$XDG_DATA_HOME/smartdock/shell.qml"
test -f "$XDG_DATA_HOME/smartdock/scripts/smartdock_cli.py"
test "$source_before" = "$(cat "$XDG_DATA_HOME/smartdock/.source-dir")"
test "$config_before" = "$(cat "$XDG_CONFIG_HOME/smartdock/dock.json")"
"$XDG_BIN_HOME/smartdock" agent-guide >/dev/null
full_remove
test ! -e "$XDG_BIN_HOME/smartdock"
test "$config_before" = "$(cat "$XDG_CONFIG_HOME/smartdock/dock.json")"

# Standalone first, then client: standalone removal retains client ownership.
full_install
cli_install
full_remove
test -x "$XDG_BIN_HOME/smartdock"
test -f "$XDG_DATA_HOME/smartdock-cli/scripts/smartdock_cli.py"
"$XDG_BIN_HOME/smartdock" help >/dev/null
"$XDG_BIN_HOME/smartdock" agent-guide >/dev/null
cli_remove
cli_remove
test ! -e "$XDG_BIN_HOME/smartdock"
test "$config_before" = "$(cat "$XDG_CONFIG_HOME/smartdock/dock.json")"
echo 'CLI-only installation/coexistence checks passed.'
