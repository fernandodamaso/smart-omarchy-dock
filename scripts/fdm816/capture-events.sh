#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="${1:-$root_dir/research/fdm816/results/events-$(date +%Y%m%d-%H%M%S)}"
duration="${2:-20}"
mkdir -p "$out_dir"

[[ "$duration" =~ ^[0-9]+$ ]] || { echo "duration must be an integer number of seconds" >&2; exit 2; }
(( duration >= 1 && duration <= 120 )) || { echo "duration must be between 1 and 120 seconds" >&2; exit 2; }

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
[[ -n "$signature" ]] || { echo "HYPRLAND_INSTANCE_SIGNATURE is not set" >&2; exit 2; }
socket="${HYPRLAND_EVENT_SOCKET:-$runtime_dir/hypr/$signature/.socket2.sock}"
[[ -S "$socket" ]] || { echo "Hyprland event socket not found: $socket" >&2; exit 2; }

if command -v socat >/dev/null 2>&1; then
  reader=(socat -u "UNIX-CONNECT:$socket" -)
elif command -v nc >/dev/null 2>&1; then
  reader=(nc -U "$socket")
else
  echo "capture-events requires socat or nc with Unix-socket support" >&2
  exit 2
fi

{
  echo "captured_at=$(date --iso-8601=ns)"
  echo "duration_seconds=$duration"
  echo "socket=$socket"
  echo "repository_head=$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || echo unavailable)"
} >"$out_dir/metadata.txt"

set +e
timeout --signal=INT "${duration}s" "${reader[@]}" 2>"$out_dir/events.stderr" \
  | python3 -c 'import sys,time
for line in sys.stdin:
    print(f"{time.time_ns()}\t{line.rstrip()}", flush=True)' \
  >"$out_dir/events.tsv"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -ne 0 && "$status" -ne 124 && "$status" -ne 130 ]]; then
  echo "event reader exited $status" >&2
  exit "$status"
fi

printf 'FDM-816 event capture: %s\n' "$out_dir"
