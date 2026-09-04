#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
label="${1:?usage: bounded-clients-sampler.sh LABEL [OUTPUT_DIR] [INTERVAL_MS] [SAMPLES]}"
out_dir="${2:-$root_dir/research/fdm816/results/manual}"
interval_ms="${3:-250}"
samples="${4:-12}"
MAX_SAMPLES_CAP=20
MIN_INTERVAL_MS=200

[[ "$interval_ms" =~ ^[0-9]+$ ]] || { echo "interval must be integer milliseconds" >&2; exit 2; }
[[ "$samples" =~ ^[0-9]+$ ]] || { echo "samples must be an integer" >&2; exit 2; }
(( interval_ms >= MIN_INTERVAL_MS )) || { echo "interval must be >= ${MIN_INTERVAL_MS}ms" >&2; exit 2; }
(( samples >= 1 && samples <= MAX_SAMPLES_CAP )) || { echo "samples must be 1..${MAX_SAMPLES_CAP}" >&2; exit 2; }

run_dir="$out_dir/$label-bounded-sampler"
mkdir -p "$run_dir"

{
  echo "label=$label"
  echo "captured_at=$(date --iso-8601=ns)"
  echo "interval_ms=$interval_ms"
  echo "samples=$samples"
  echo "hard_cap=$MAX_SAMPLES_CAP"
  echo "repository_head=$(git -C "$root_dir" rev-parse HEAD 2>/dev/null || echo unavailable)"
  echo "warning=research-only bounded hyprctl sampling; never a production polling design"
} >"$run_dir/metadata.txt"

printf 'sample\tstarted_ns\tfinished_ns\tduration_ms\texit_code\n' >"$run_dir/timings.tsv"
sleep_seconds="$(awk -v ms="$interval_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"

for ((index=1; index<=samples; index++)); do
  started_ns="$(date +%s%N)"
  set +e
  hyprctl clients -j >"$run_dir/clients-$(printf '%03d' "$index").json" \
    2>"$run_dir/clients-$(printf '%03d' "$index").stderr"
  exit_code=$?
  set -e
  finished_ns="$(date +%s%N)"
  duration_ms="$(awk -v start="$started_ns" -v end="$finished_ns" \
    'BEGIN { printf "%.3f", (end - start) / 1000000 }')"
  printf '%d\t%s\t%s\t%s\t%d\n' \
    "$index" "$started_ns" "$finished_ns" "$duration_ms" "$exit_code" \
    >>"$run_dir/timings.tsv"
  if (( index < samples )); then
    sleep "$sleep_seconds"
  fi
done

printf 'FDM-816 bounded sampler: %s\n' "$run_dir"
