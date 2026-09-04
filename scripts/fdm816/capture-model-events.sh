#!/usr/bin/env bash
# FDM-816 bounded Quickshell model-event capture (research only).
#
# Usage: capture-model-events.sh OUTPUT_DIR MODE DURATION_SECONDS
#   MODE is "passive" or "centralized"; DURATION_SECONDS is an integer 1..120.
#
# - passive mode observes protocol/model updates only and never calls
#   Hyprland.refresh*(). It cannot prove freshness by itself; stale data here
#   is a measured gap, not a failure.
# - centralized mode runs the single host-equivalent coalesced refresh owned by
#   the probe (one debounced refresh per event burst) and timestamps every
#   request/completion. There are no per-screen pollers.
#
# This script performs no continuous hyprctl polling.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="${1:?usage: capture-model-events.sh OUTPUT_DIR MODE DURATION_SECONDS}"
mode="${2:?usage: capture-model-events.sh OUTPUT_DIR MODE DURATION_SECONDS}"
duration="${3:?usage: capture-model-events.sh OUTPUT_DIR MODE DURATION_SECONDS}"
probe_dir="$root_dir/research/fdm816/quickshell-probe"

[[ "$mode" == passive || "$mode" == centralized ]] \
  || { echo "capture-model-events: MODE must be passive or centralized" >&2; exit 2; }
[[ "$duration" =~ ^[0-9]+$ ]] \
  || { echo "capture-model-events: duration must be an integer number of seconds" >&2; exit 2; }
(( duration >= 1 && duration <= 120 )) \
  || { echo "capture-model-events: duration must be between 1 and 120 seconds" >&2; exit 2; }

command -v qs >/dev/null 2>&1 || { echo "capture-model-events: qs is not installed" >&2; exit 2; }

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
[[ -n "$signature" ]] || { echo "capture-model-events: HYPRLAND_INSTANCE_SIGNATURE is not set" >&2; exit 2; }
socket="$runtime_dir/hypr/$signature/.socket2.sock"
[[ -S "$socket" ]] || { echo "capture-model-events: Hyprland event socket not found: $socket" >&2; exit 2; }

mkdir -p "$out_dir"
started_ns="$(date +%s%N)"

{
  echo "captured_at=$(date --iso-8601=ns)"
  echo "mode=$mode"
  echo "duration_seconds=$duration"
  echo "target_address=${FDM816_TARGET:-}"
  echo "socket=$socket"
  echo "repository_head=$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || echo unavailable)"
  if [[ "$mode" == passive ]]; then
    echo "refresh_policy=none; passive mode never calls Hyprland.refresh*()"
  else
    echo "refresh_policy=single host-owned coordinator: one coalesced refresh per event burst (150ms debounce)"
  fi
} >"$out_dir/metadata.txt"

set +e
# The timeout is a backstop past the probe's own bounded stop timer so the
# FDM816_MODEL_DONE summary is usually emitted before the kill.
FDM816_MODE="$mode" FDM816_DURATION_S="$duration" \
  timeout "$((duration + 5))s" qs -p "$probe_dir" \
  >"$out_dir/quickshell-model.log" 2>"$out_dir/quickshell-model.stderr"
probe_status=$?
set -e
# timeout(1) returns 124 when it kills the bounded logger at the duration limit.
if [[ "$probe_status" -ne 0 && "$probe_status" -ne 124 ]]; then
  echo "capture-model-events: probe exited $probe_status" >&2
  exit "$probe_status"
fi

finished_ns="$(date +%s%N)"
grep 'FDM816_MODEL ' "$out_dir/quickshell-model.log" \
  | sed 's/^.*FDM816_MODEL //' >"$out_dir/model-events.jsonl" || true
grep 'FDM816_MODEL_DONE ' "$out_dir/quickshell-model.log" \
  | tail -n 1 | sed 's/^.*FDM816_MODEL_DONE //' >"$out_dir/model-done.json" || true

record_count="$(wc -l <"$out_dir/model-events.jsonl" | tr -d ' ')"
refresh_count=""
if command -v jq >/dev/null 2>&1 && [[ -s "$out_dir/model-events.jsonl" ]]; then
  refresh_count="$(jq -rs 'map(.refreshCount // 0) | max // 0' "$out_dir/model-events.jsonl" 2>/dev/null || true)"
fi

{
  echo "started_ns=$started_ns"
  echo "finished_ns=$finished_ns"
  echo "probe_exit=$probe_status"
  echo "model_record_count=$record_count"
  echo "max_observed_refresh_count=${refresh_count:-unknown}"
} >>"$out_dir/metadata.txt"

if [[ "$mode" == passive && -n "${refresh_count:-}" && "$refresh_count" != "0" ]]; then
  echo "capture-model-events: passive run observed refreshCount $refresh_count; purity violated" >&2
  exit 1
fi

printf 'FDM-816 model capture (%s): %s (%s records)\n' "$mode" "$out_dir" "$record_count"
