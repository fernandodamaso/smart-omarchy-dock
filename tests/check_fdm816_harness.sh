#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

fail() {
  echo "check_fdm816_harness: $*" >&2
  exit 1
}

required=(
  research/fdm816/README.md
  research/fdm816/decision.py
  research/fdm816/result-template.json
  research/fdm816/quickshell-probe/shell.qml
  scripts/fdm816/capture-environment.sh
  scripts/fdm816/capture-fixture.sh
  scripts/fdm816/capture-events.sh
  scripts/fdm816/capture-model-events.sh
  scripts/fdm816/bounded-clients-sampler.sh
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || fail "missing $file"
done

bash -n \
  scripts/fdm816/capture-environment.sh \
  scripts/fdm816/capture-fixture.sh \
  scripts/fdm816/capture-events.sh \
  scripts/fdm816/capture-model-events.sh \
  scripts/fdm816/bounded-clients-sampler.sh

probe=research/fdm816/quickshell-probe/shell.qml
model_script=scripts/fdm816/capture-model-events.sh

# Passive-mode purity: the capture script itself never refreshes, and every
# Hyprland.refresh*() call site in the probe is guarded by an explicit mode
# check (oneshot explicit-refresh snapshot or centralized coalesced refresh).
grep -E -q 'Hyprland\.refresh[A-Za-z]+\(\)' "$model_script" \
  && fail "capture-model-events.sh must never call Hyprland.refresh*()"
grep -q 'passive mode never calls Hyprland.refresh' "$model_script" \
  || fail "capture-model-events.sh must document passive-mode purity"
grep -q 'root.mode === "oneshot"' "$probe" \
  || fail "probe one-shot refresh must be guarded by an explicit mode check"
grep -q 'root.mode !== "centralized"' "$probe" \
  || fail "probe centralized refresh must be guarded by an explicit mode check"
grep -q 'FDM816_MODE' "$probe" \
  || fail "probe must select passive/centralized behavior from FDM816_MODE"
[[ "$(grep -c 'Hyprland.refreshToplevels()' "$probe")" -eq 2 ]] \
  || fail "probe must keep exactly two guarded refresh sites (oneshot + centralized)"

# Centralized ownership: one host-equivalent coalesced refresh, no per-screen
# pollers.
grep -q 'performCentralizedRefresh' "$probe" \
  || fail "probe must keep the single host-owned coalesced refresh function"
grep -q 'centralizedDebounce' "$probe" \
  || fail "probe must debounce centralized refreshes into one refresh per burst"
grep -q 'centralizedEventIsRelevant' "$probe" \
  || fail "probe must filter raw events before centralized refresh"
grep -q 'refreshInFlight' "$probe" \
  || fail "probe must prevent overlapping centralized refreshes"
grep -q 'refreshCompletedMs' "$probe" \
  || fail "probe must timestamp centralized refresh completion"
grep -q 'single host-owned coordinator' "$model_script" \
  || fail "capture-model-events.sh must state single host-owned refresh ownership"
grep -q 'single host-owned coordinator' research/fdm816/result-template.json \
  || fail "result template must record single host-owned refresh ownership"

# Duration bounds: model captures are capped at 1..120 seconds.
grep -q '120' "$model_script" \
  || fail "capture-model-events.sh must enforce the 120s duration cap"
"$model_script" /tmp/fdm816-harness-check badmode 5 >/dev/null 2>&1 \
  && fail "capture-model-events.sh must reject an unknown mode"
"$model_script" /tmp/fdm816-harness-check passive 0 >/dev/null 2>&1 \
  && fail "capture-model-events.sh must reject a 0s duration"
"$model_script" /tmp/fdm816-harness-check passive 121 >/dev/null 2>&1 \
  && fail "capture-model-events.sh must reject a 121s duration"

# Structured evidence schema: target identity, coordinate space, refresh
# observation, action markers, and artifact manifest.
for key in target coordinateSpace refreshObservation actionMarkers artifactManifest; do
  jq -e --arg key "$key" '.[$key]' research/fdm816/result-template.json >/dev/null \
    || fail "result template missing structured evidence section: $key"
done

# The blank template must never classify: probe is incomplete, scenarios are
# empty, and the numeric mapping is unverified.
python3 research/fdm816/decision.py research/fdm816/result-template.json >/dev/null 2>&1 \
  && fail "blank result template must not produce a decision"
printf '{"probeComplete": false, "evidence": {}}' \
  | python3 research/fdm816/decision.py --stdin >/dev/null 2>&1 \
  && fail "classifier must require probeComplete"

if grep -R -n -E 'while[[:space:]]+true|while[[:space:]]+:' scripts/fdm816; then
  fail "feasibility scripts must not contain unbounded polling loops"
fi

grep -q 'MAX_SAMPLES_CAP=20' scripts/fdm816/bounded-clients-sampler.sh \
  || fail "bounded sampler must keep the 20-sample hard cap"
grep -q 'MIN_INTERVAL_MS=200' scripts/fdm816/bounded-clients-sampler.sh \
  || fail "bounded sampler must keep the 200ms minimum interval"

for token in \
  'FDM-812' \
  'tiled resize' \
  'floating drag/resize' \
  'maximize/fullscreen' \
  'workspace/special-workspace' \
  'monitor scale/transform/rearrangement' \
  'hotplug' \
  'slow overlap-boundary movement' \
  'rapid overlap-boundary movement' \
  'event-driven' \
  'bounded adaptive refresh' \
  'documented degraded behavior' \
  'NO-GO'; do
  grep -q "$token" research/fdm816/README.md \
    || fail "README missing required matrix/decision token: $token"
done

if grep -R -n 'fdm816\|intellihide-feasibility' \
  DockHost.qml shell.qml config components 2>/dev/null; then
  fail "production paths must not depend on the feasibility harness"
fi

echo "check_fdm816_harness: PASS"
