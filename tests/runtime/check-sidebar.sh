#!/usr/bin/env bash
set -euo pipefail
if [[ "${SMARTDOCK_ISOLATED_RUNTIME:-}" != "1" ]]; then
  echo 'Use the disposable session in docs/DEV_SESSIONS.md; stop its normal dock before this fixture.' >&2
  exit 2
fi
mode="${1:-fixture}"
if [[ "$mode" != "fixture" && "$mode" != "--native" ]]; then
  echo 'Usage: check-sidebar.sh [--native]' >&2
  exit 2
fi
if [[ "$mode" == "--native" ]]; then
  : "${SMARTDOCK_RUNTIME_LOG:?Set an evidence log path outside the temporary fixture source}"
  duration="${SMARTDOCK_NATIVE_SECONDS:-120}"
  if [[ ! "$duration" =~ ^[0-9]+$ ]] || (( duration < 1 || duration > 300 )); then
    echo 'SMARTDOCK_NATIVE_SECONDS must be 1..300.' >&2; exit 2
  fi
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
if [[ "$mode" == "--native" ]]; then
  cp "$root/tests/runtime/sidebar-native.qml" "$temporary/shell.qml"
else
  cp "$root/tests/runtime/sidebar.qml" "$temporary/shell.qml"
fi
ln -s "$root/assets" "$temporary/assets"
mkdir "$temporary/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$temporary/imports/qs"
python3 - "$root/config/dock.json" "$temporary/fixture-config.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
value.update(presentationMode='sidebar',pinned=[],hiddenApplications=[],showTrash=False,
             autoHide=False,position='bottom',iconSize=42,sidebarExpandedWidth=320,
             sidebarCollapsed=False,sidebarEdge='left',sidebarMonitor='')
value['runtimeFixtureUnknown']={'keep': True}
with open(sys.argv[2],'w') as f: json.dump(value,f)
PY
# Save diagnostic output outside the temporary source when a path is requested.
log="${SMARTDOCK_RUNTIME_LOG:-$temporary/output.log}"
if [[ "$mode" == "--native" ]]; then
  status=0
  QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$temporary/imports" \
    timeout "${duration}s" qs -p "$temporary" --no-color >"$log" 2>&1 || status=$?
  if [[ "$status" != 0 && "$status" != 124 ]]; then cat "$log"; exit 1; fi
  if grep -E 'ERROR|Error:|ReferenceError|TypeError|Unable to assign' "$log"; then exit 1; fi
  grep -F '"event":"ready"' "$log" >/dev/null
  printf 'Native observer stopped; evidence: %s\nNo acceptance verdict: SB-06 must qualify the native matrix.\n' "$log"
  exit 0
fi
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$temporary/imports" \
  timeout 60s qs -p "$temporary" --no-color >"$log" 2>&1 || { cat "$log"; exit 1; }
# Fixture asserts print "ERROR qml: Error: sidebar fixture: ...". Ignore unrelated
# DockContextMenu ReferenceError noise when the fixture itself completed.
if grep -F 'ERROR qml: Error: sidebar fixture:' "$log"; then cat "$log"; exit 1; fi
if grep -E 'Unable to assign|TypeError: Cannot' "$log"; then cat "$log"; exit 1; fi
grep -F 'sidebar: PASS (production host/panel/delegates/widgets, resize reservation/writer-count, leases/popups, layers, teardown)' "$log"
python3 - "$temporary/fixture-config.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
assert value['sidebarExpandedWidth'] == 240, value['sidebarExpandedWidth']
assert value['sidebarEdge'] == 'left', value['sidebarEdge']
assert value['sidebarCollapsed'] is True, value['sidebarCollapsed']
assert value['runtimeFixtureUnknown'] == {'keep': True}
assert value['position'] == 'bottom' and value['iconSize'] == 42
print('sidebar persistence readback: PASS (width=240, collapsed, unknown/classic keys preserved)')
PY
