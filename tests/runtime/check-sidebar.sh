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
  native_override="${SMARTDOCK_NATIVE_CONFIG_OVERRIDE:-}"
  native_evidence="${SMARTDOCK_NATIVE_EVIDENCE_DIR:-}"
  if [[ -n "$native_override" && ( ! -f "$native_override" || -L "$native_override" || ! -r "$native_override" ) ]]; then
    echo 'SMARTDOCK_NATIVE_CONFIG_OVERRIDE must name a readable regular JSON file.' >&2; exit 2
  fi
  if [[ -n "$native_evidence" && ( ! -d "$native_evidence" || -L "$native_evidence" || ! -w "$native_evidence" ) ]]; then
    echo 'SMARTDOCK_NATIVE_EVIDENCE_DIR must name a writable, non-symlink directory.' >&2; exit 2
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
if [[ "$mode" == "--native" && -n "$native_override" ]]; then
  cp -- "$native_override" "$temporary/native-config-override.json"
fi
python3 - "$root/config/dock.json" "$temporary/fixture-config.json" "${temporary}/native-config-override.json" <<'PY'
import json
import re
import sys
from pathlib import Path

base_path, output_path, override_path = map(Path, sys.argv[1:])
value=json.loads(base_path.read_text(encoding="utf-8"))
value.update(presentationMode='sidebar',pinned=[],hiddenApplications=[],showTrash=False,
             autoHide=False,position='bottom',iconSize=42,sidebarExpandedWidth=320,
             sidebarCollapsed=False,sidebarEdge='left',sidebarMonitor='')
value['runtimeFixtureUnknown']={'keep': True}
if override_path.exists():
    try:
        override = json.loads(override_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"SMARTDOCK_NATIVE_CONFIG_OVERRIDE is not valid JSON: {error}")
    allowed = {
        "presentationMode", "sidebarEdge", "sidebarMonitor", "sidebarExpandedWidth",
        "sidebarCollapsed", "sidebarCollapsedByMonitor", "sidebarInlineSoloWorkspace",
        "sidebarWidgets", "sidebarWidgetCollapsed", "sidebarBrowserTabsEnabled",
    }
    if not isinstance(override, dict) or set(override) - allowed:
        raise SystemExit("SMARTDOCK_NATIVE_CONFIG_OVERRIDE must be an object containing only sidebar settings.")
    identifier = re.compile(r"[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\Z")
    monitor = re.compile(r"[^\x00-\x1f\x7f]{1,128}\Z")
    def fail(message): raise SystemExit("SMARTDOCK_NATIVE_CONFIG_OVERRIDE " + message)
    if override.get("presentationMode", "sidebar") != "sidebar": fail("presentationMode must be sidebar.")
    if "sidebarEdge" in override and override["sidebarEdge"] not in ("left", "right"): fail("sidebarEdge must be left or right.")
    if "sidebarMonitor" in override and (not isinstance(override["sidebarMonitor"], str) or (override["sidebarMonitor"] and not monitor.fullmatch(override["sidebarMonitor"]))): fail("sidebarMonitor is invalid.")
    if "sidebarExpandedWidth" in override and (type(override["sidebarExpandedWidth"]) is not int or not 240 <= override["sidebarExpandedWidth"] <= 480): fail("sidebarExpandedWidth must be an integer from 240 through 480.")
    for key in ("sidebarCollapsed", "sidebarInlineSoloWorkspace", "sidebarBrowserTabsEnabled"):
        if key in override and type(override[key]) is not bool: fail(f"{key} must be boolean.")
    for key in ("sidebarCollapsedByMonitor", "sidebarWidgetCollapsed"):
        if key in override and (not isinstance(override[key], dict) or any(type(v) is not bool for v in override[key].values())): fail(f"{key} must map names to booleans.")
    if "sidebarCollapsedByMonitor" in override and any(not isinstance(k, str) or not monitor.fullmatch(k) for k in override["sidebarCollapsedByMonitor"]): fail("sidebarCollapsedByMonitor contains an invalid monitor.")
    if "sidebarWidgetCollapsed" in override and any(not isinstance(k, str) or not identifier.fullmatch(k) for k in override["sidebarWidgetCollapsed"]): fail("sidebarWidgetCollapsed contains an invalid widget ID.")
    if "sidebarWidgets" in override and (not isinstance(override["sidebarWidgets"], list) or len(override["sidebarWidgets"]) > 32 or any(not isinstance(v, str) or not identifier.fullmatch(v) for v in override["sidebarWidgets"]) or len(set(override["sidebarWidgets"])) != len(override["sidebarWidgets"])): fail("sidebarWidgets must be up to 32 unique valid widget IDs.")
    value.update(override)
value["presentationMode"] = "sidebar"
output_path.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")
PY
# Save diagnostic output outside the temporary source when a path is requested.
log="${SMARTDOCK_RUNTIME_LOG:-$temporary/output.log}"
if [[ "$mode" == "--native" ]]; then
  if [[ -n "$native_evidence" ]]; then
    archive="$native_evidence/native-initial-fixture-config.json"
    digest="$native_evidence/native-initial-fixture-config.sha256"
    if [[ -e "$archive" || -e "$digest" ]]; then
      echo 'Native evidence archive paths already exist; use a fresh evidence directory.' >&2; exit 2
    fi
    install -m 600 "$temporary/fixture-config.json" "$archive"
    (cd "$native_evidence" && sha256sum "$(basename "$archive")" >"$(basename "$digest")")
  fi
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
