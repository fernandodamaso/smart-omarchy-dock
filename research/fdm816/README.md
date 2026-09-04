# FDM-816 — intelligent-hide geometry freshness feasibility harness

This directory is a **repository-side research harness only**. It does not implement intelligent hide, add production polling, or prepare FDM-817.

## Reviewed outcome

The reviewed pinned-runtime result is **`NO-GO`**. Pure tiled resize, floating drag/resize, and visual-proxy overlap-boundary movement did not expose a usable event that could start a bounded refresh burst. The experiment's sampler worked only when started manually, and no deterministic stability-based stop signal was verified.

A manually started sampler does not prove a production strategy. Without a verified non-polling start trigger and stop condition, arbitrary geometry changes require continuous `hyprctl` polling, which this project rejects.

The sanitized result is in `results/reviewed-result.json`.

## Scope boundaries

Allowed here:

- capture pinned Omarchy, Hyprland, Quickshell, Qt/Wayland, and backend versions;
- capture representative `hyprctl` client, monitor, workspace, and active-state fixtures;
- capture Quickshell `ToplevelManager` and `Quickshell.Hyprland` model state;
- record raw fullscreen/maximized numeric fields without assuming their meaning;
- capture the Hyprland event socket for a bounded duration;
- run a short, capped `hyprctl clients -j` research sample;
- classify one completed evidence record.

Explicitly out of scope:

- production timers or continuous `hyprctl` polling;
- intelligent-hide settings or UI;
- stable dock rectangle or intersection logic;
- visibility state-machine or reserve-space changes;
- production refresh wiring or broad refactors.

**FDM-812 dependency:** FDM-812 must provide a validated per-screen dock rectangle, client rectangles in the same coordinate space, pure intersection behavior, and explicit unknown/stale handling before intelligent hide can be implemented.

## Refresh ownership and bounds

Any future refresh fallback must have one host-owned coordinator. Per-screen docks and individual items must not own pollers.

The research sampler enforces a 20-sample hard cap and a 200 ms minimum interval. Those limits are necessary but not sufficient. A `bounded adaptive refresh` decision additionally requires evidence for:

- a production-available, non-polling `startTrigger`;
- `startTriggerVerified: true`;
- a deterministic `stopCondition`;
- `stopConditionVerified: true`.

If no start trigger exists, set `continuousHyprctlPollingRequired` to `true`. Do not disguise always-on polling as a bounded burst.

## Harness files

- `scripts/fdm816/capture-environment.sh` — version/package capture.
- `scripts/fdm816/capture-fixture.sh` — one-shot Hyprland and Quickshell fixture capture.
- `scripts/fdm816/capture-events.sh` — timestamped event-socket capture with a hard duration limit.
- `scripts/fdm816/capture-model-events.sh` — bounded passive or centralized Quickshell model capture.
- `scripts/fdm816/bounded-clients-sampler.sh` — research-only capped `hyprctl clients -j` samples.
- `research/fdm816/quickshell-probe/shell.qml` — isolated one-shot/passive/centralized model logger.
- `research/fdm816/result-template.json` — evidence schema.
- `research/fdm816/decision.py` — final-decision classifier.
- `tests/test_fdm816_decision.py` and `tests/check_fdm816_harness.sh` — repository checks.

## Required experiment matrix

Run every row against the exact recorded versions and match one ordinary application window between `hyprctl clients` and the Quickshell probe.

| Scenario | Evidence to record |
| --- | --- |
| tiled resize | event names/timestamps, client `at`/`size`, model geometry, mismatch latency, burst trigger availability |
| floating drag/resize | event cadence, geometry/model freshness, start trigger, stop condition |
| maximize/fullscreen | raw `fullscreen` and `fullscreenClient` values, state mapping, events, latency |
| workspace/special-workspace | workspace IDs/names, monitor workspace, event sequence, freshness |
| monitor scale/transform/rearrangement | monitor geometry/scale/transform, client geometry, event sequence, freshness |
| hotplug | monitor/client/workspace transition, stale duration, restoration, recovery |
| slow overlap-boundary movement | geometry step, event/protocol signal, stale duration, start/stop evidence |
| rapid overlap-boundary movement | missed transitions, worst stale duration, event volume, CPU/log impact |

Do not infer numeric meanings from memory. Toggle each state on the pinned system and record the observed mapping.

## Candidate evaluation

Evaluate all four candidates from the same evidence:

1. **event/protocol** — existing events or protocols cover every required transition without repeated `hyprctl` calls.
2. **centralized refresh** — an observed event triggers one host-owned coalesced refresh that closes model lag.
3. **bounded adaptive refresh** — a verified non-polling signal starts a finite burst, a verified condition stops it, and the measured caps/performance cover every row.
4. **documented degraded behavior** — exact user-visible limitations are documented and explicitly accepted.

The only allowed decisions are:

- `event-driven`
- `bounded adaptive refresh`
- `documented degraded behavior`
- `NO-GO`

The classifier requires a full result record. Standalone booleans, incomplete scenarios, unverified numeric mapping, or an unverified adaptive start/stop path are rejected.

## Local workflow

Run from the canonical source checkout, never an installed plugin copy.

### 1. Create a local run directory

```bash
RUN="research/fdm816/results/local-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
./scripts/fdm816/capture-environment.sh "$RUN/environment"
cp research/fdm816/result-template.json "$RUN/result.json"
```

### 2. Capture fixtures

```bash
./scripts/fdm816/capture-fixture.sh baseline "$RUN"
./scripts/fdm816/capture-fixture.sh tiled-before "$RUN"
# perform the action
./scripts/fdm816/capture-fixture.sh tiled-after "$RUN"
```

### 3. Capture raw and model events

```bash
./scripts/fdm816/capture-events.sh "$RUN/events/tiled-resize" 20
./scripts/fdm816/capture-model-events.sh "$RUN/model/tiled-resize" passive 20
```

Use `centralized` mode only to test one event-triggered host-owned refresh.

### 4. Quantify a measured gap

```bash
./scripts/fdm816/bounded-clients-sampler.sh floating-gap "$RUN" 250 12
```

Starting this command manually is research orchestration, not evidence of a production start trigger. Record what production signal would start and stop the burst.

### 5. Classify the completed record

```bash
python3 research/fdm816/decision.py "$RUN/result.json"
python3 research/fdm816/decision.py --write "$RUN/result.json"
```

## Evidence privacy

Local captures can contain window titles, application classes, process listings, paths, and journal data. `research/fdm816/results/.gitignore` keeps raw runs and archives out of Git. Commit only a deliberately sanitized summary when project review requires it.

## Repository checks

```bash
python3 tests/test_fdm816_decision.py
bash tests/check_fdm816_harness.sh
bash -n scripts/fdm816/*.sh
```

The normal Omarchy startup, QML, plugin, and lint gates require the real desktop runtime. Report them as unavailable when that environment is absent; do not pretend a repository-only check replaced them.
