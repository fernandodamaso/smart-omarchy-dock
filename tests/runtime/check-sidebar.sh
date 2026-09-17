#!/usr/bin/env bash
set -euo pipefail
if [[ "${SMARTDOCK_ISOLATED_RUNTIME:-}" != "1" ]]; then
  echo 'Use the disposable session in docs/DEV_SESSIONS.md; stop its normal dock before this fixture.' >&2
  exit 2
fi
command -v qs >/dev/null
command -v hyprctl >/dev/null
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
temporary="$(mktemp -d -t smartdock-sidebar.XXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT
# Read-only native layer check prevents running alongside another mapped SmartDock.
hyprctl -j layers | python3 -c '
import json,sys
def visit(x):
    if isinstance(x,dict):
        if x.get("namespace") in ("smartdock", "smartdock-sidebar"):
            raise SystemExit("Stop the isolated guest dock before running the sidebar fixture.")
        for v in x.values(): visit(v)
    elif isinstance(x,list):
        for v in x: visit(v)
visit(json.load(sys.stdin))'
cp -R "$root/components" "$root/config" "$temporary/"
cp "$root/DockHost.qml" "$temporary/DockHost.qml"
mkdir -p "$temporary/tests"
cp -R "$root/tests/fixtures" "$temporary/tests/"
cp "$root/tests/runtime/sidebar.qml" "$temporary/shell.qml"
ln -s "$root/assets" "$temporary/assets"
mkdir "$temporary/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$temporary/imports/qs"
python3 - "$root/config/dock.json" "$temporary/fixture-config.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
value.update(presentationMode='sidebar',pinned=[],hiddenApplications=[],showTrash=False,
             autoHide=False,position='bottom',iconSize=42,sidebarExpandedWidth=320,
             sidebarCollapsed=False,sidebarEdge='left',sidebarMonitor='')
with open(sys.argv[2],'w') as f: json.dump(value,f)
PY
# Save diagnostic output outside the temporary source when a path is requested.
log="${SMARTDOCK_RUNTIME_LOG:-$temporary/output.log}"
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$temporary/imports" \
  timeout 45s qs -p "$temporary" --no-color >"$log" 2>&1 || { cat "$log"; exit 1; }
if grep -E 'ERROR|Error:|ReferenceError|TypeError|Unable to assign' "$log"; then cat "$log"; exit 1; fi
grep -F 'sidebar: PASS' "$log"
