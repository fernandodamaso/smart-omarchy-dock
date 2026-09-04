#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
label="${1:?usage: capture-fixture.sh LABEL [OUTPUT_DIR]}"
out_dir="${2:-$root_dir/research/fdm816/results/manual}"
fixture_dir="$out_dir/$label"
probe_dir="$root_dir/research/fdm816/quickshell-probe"
mkdir -p "$fixture_dir"

capture_json() {
  local name="$1"
  shift
  "$@" >"$fixture_dir/$name.json" 2>"$fixture_dir/$name.stderr" || true
}

{
  echo "label=$label"
  echo "captured_at=$(date --iso-8601=ns)"
  echo "repository_head=$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || echo unavailable)"
} >"$fixture_dir/metadata.txt"

capture_json clients hyprctl clients -j
capture_json monitors hyprctl monitors -j
capture_json workspaces hyprctl workspaces -j
capture_json activeworkspace hyprctl activeworkspace -j
capture_json activewindow hyprctl activewindow -j
capture_json layers hyprctl layers -j

# Preserve raw numeric state fields instead of assuming pinned-version meaning.
if command -v jq >/dev/null 2>&1 && [[ -s "$fixture_dir/clients.json" ]]; then
  jq -r '
    .[] | [
      (.address // ""),
      (.class // ""),
      (.title // ""),
      (.fullscreen // null),
      (.fullscreenClient // null),
      (.floating // null),
      (.at[0] // null), (.at[1] // null),
      (.size[0] // null), (.size[1] // null),
      (.workspace.id // null), (.workspace.name // "")
    ] | @tsv' "$fixture_dir/clients.json" \
    >"$fixture_dir/client-state-fields.tsv" || true
fi

if command -v qs >/dev/null 2>&1; then
  set +e
  timeout 3s qs -p "$probe_dir" >"$fixture_dir/quickshell-probe.log" 2>&1
  probe_status=$?
  set -e
  # timeout(1) returns 124 after the one-shot log has already been emitted.
  if [[ "$probe_status" -ne 0 && "$probe_status" -ne 124 ]]; then
    echo "quickshell_probe_exit=$probe_status" >>"$fixture_dir/metadata.txt"
  fi
  grep 'FDM816_FIXTURE ' "$fixture_dir/quickshell-probe.log" \
    | tail -n 1 | sed 's/^.*FDM816_FIXTURE //' \
    >"$fixture_dir/quickshell-toplevels.json" || true
else
  echo "qs unavailable" >"$fixture_dir/quickshell-probe.log"
fi

printf 'FDM-816 fixture: %s\n' "$fixture_dir"
