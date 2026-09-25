# FDM-995 native qualification

## Candidate and environment

The source handoff started at HEAD
`cc60762a1b9c559dabd35c840897d8eb90cdea74`, based on
`51de331db28ebd17406c3ed02b9138df6c1e1b7e`. Runtime qualification used the
current dirty candidate, not the clean handoff commit:

- synced source digest: `eefe0936fa2219bf114291181793ef2972a19bb4ec739abafdbd6030c34d896f`;
- dirty-state (`git status --porcelain=v1 -z`) digest:
  `472823ef581e19029f602252f8b25af940a4a136a59215bc4334f3656d10574d`.

The three demonstrated fixes in that candidate are the footer `Bound` scope,
the viewport-owned restore timer and the sidebar-owned context-refresh timer.
The broad run used fresh guest `fdm995-native-r3`; focused gap qualification used
fresh guest `fdm995-native-r4`. Both used the standalone host, two virtual outputs
(`Virtual-1`, `Virtual-2`) and held-button input injected only through guest
ydotool. The r4 source-manifest digest was
`3ffda1b224a6ea8aaad6cfde923941ce4c163ce00a1cad8bda4e1c2b87327e5b`.
This is not physical-output or full-Omarchy-host qualification.

## Results

**Native passed:** two live panels and one observer dock; source workspace
dimming and monitor-group targeting; cross-monitor header move with origin-only
flash; numeric and named workspace-source moves; mirrored new-workspace slots
and confirmed allocation; SmartDock pin/unpin and minimize actions; pinned
rejection; minimized-source move; reduced-motion flash; collapsed right-edge
rail and live-reload settlement; two → one → two virtual-output topology
recovery; and held-drag autoscroll from `contentY 0` to `64` followed by an
outside-release rejection and restoration to `0`. A focused native round also
confirmed an initially offscreen destination after queued restoration: only the
Virtual-1 origin scrolled/flashed and saved `contentY 155`, anchor
`window:5+21`; the mirror remained at `contentY 72`, anchor `window:2+8`, through
an additional refresh. Closing a captured source cleared old token 3 without
confirmation or flash; a fresh drag then completed independently as token 6
without stale timer, snap, flash or presentation transfer. The same-monitor
header behavior was qualified, but owner approval of that provisional product
policy is still pending.

**Native partial plus substituted pass:** a native folded-destination operation
retained the fold, flashed only the verified workspace-group fallback and never
flashed a window row. Its categorical no-focus-steal predicate remains
inconclusive because normal pointer focus moved to the dragged source. The
production-QML harness fully covers folded/missing-row fallback, offscreen
origin-only containment, recreated-origin stale-owner rejection and owned
restore-timer coalescing (7/7). Observer sanitizer/parser tests passed 2/2;
drop-scroll/polish/widget source checks passed 3/3. Controlled delayed or
inconsistent readback, timeout/late success and other deterministic races remain
substituted evidence; they were not reproduced or claimed as native races.

**Blocked or not objectively completed:** the reverse-origin offscreen case;
categorical native no-focus-steal for folded fallback; and physical-monitor/
full-Omarchy-host qualification.

R13/R14 passed with separately disclosed observer-context warnings: missing icon
assets in the disposable observer copy and `DockMenuAction` width binding loops.
Both rounds recorded **zero candidate delayed-callback errors**. Inspection of
`fdm995-native-r3-contact-sheet.png` and the selected original frames found no
stale settled feedback or malformed surface; still images do not establish
timing behavior.

## Commands and evidence

The clean source handoff's `Headless CI` track passed at the base/head pair
above. It ran the repository command set below; that pass does not cover the
later dirty fixes.

```bash
for script in install.sh uninstall.sh scripts/smartdock scripts/run \
  tests/check_*.sh; do bash -n "$script"; done
for script in tests/check_*.sh; do bash "$script"; done
for script in tests/test_*.mjs; do node "$script"; done
python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m unittest discover -s provider/browser-profiles/tests -p 'test_*.py'
python3 -B -m unittest discover -s tests -p 'test_herdr_*.py' -v
python3 -B -m unittest discover -s provider/herdr/tests -p 'test_*.py' -v
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components -import tests/qml-imports
git diff --check 51de331db28ebd17406c3ed02b9138df6c1e1b7e...cc60762a1b9c559dabd35c840897d8eb90cdea74
```

The complete Headless CI matrix was not rerun on the dirty candidate. Its local
exact-candidate evidence records these targeted reruns and results:

```bash
python3 tests/test_sidebar_native_observer.py
# PASS: 2

node --test tests/test_sidebar_drop_scroll.mjs \
  tests/test_sidebar_polish_behaviors.mjs tests/test_sidebar_widgets.mjs
# PASS: 3

QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_sidebardropfeedback.qml -import components
# PASS: 7; known harness-only Connections warnings retained in the log
```

Final worktree validation also passed shell syntax, all 23 sidebar Node tests,
the observer's two Python tests, `omarchy plugin validate .`, `qmllint` (existing
warnings only) and `git diff --check`. The full offscreen QML run passed 392
tests and failed the four cases in `tst_herdr_remote_fallback.qml`. An isolated
checkout of unchanged HEAD `cc60762` reproduced those same four failures, so
they are a pre-existing baseline gate rather than a regression from this work.
The standalone `./scripts/run` smoke was not launched beside the already-running
production Omarchy Quickshell process; the fresh standalone KVM sessions provide
the source-host runtime smoke instead.

Qualifying observer rounds set `OMARCHY_PATH=$HOME/smartdock-omarchy-test`,
`SMARTDOCK_ISOLATED_RUNTIME=1`, a round-specific
`SMARTDOCK_RUNTIME_LOG=/tmp/<round>.jsonl`, and
`SMARTDOCK_NATIVE_SECONDS=60` or `90` when running
`bash tests/runtime/check-sidebar.sh --native`. The first invocation omitted
`OMARCHY_PATH` and failed during harness import resolution before product code;
it is excluded from qualification.

Sanitized broad-run evidence is local at
`~/.local/state/smartdock/dev-sessions/fdm995-native-r3/evidence/`; focused gap
evidence is at
`~/.local/state/smartdock/dev-sessions/fdm995-native-r4/evidence/`. The primary
records in each directory are `qualification-manifest-sanitized.json`,
`qualification-results-sanitized.json`, `runtime-gates-sanitized.json`,
`commands-results-sanitized.txt`, the sanitized JSONL timelines, storyboard
captures and stopped-status record. The r3 directory also contains
`fdm995-native-r3-contact-sheet.png`.

## Cleanup and validity

Production settings had the same SHA-256 before qualification, immediately
before stop and after stop; the host workspace/window and installed plugin were
unchanged. Both KVM guests are stopped and their stopped-status records report
`qemu_alive=false`; no physical `smartdock dev use` switch occurred, so no
desktop reset was needed. Restarting a guest remains the rollback for its
disposable state. The documentation was updated after r4 without changing the
qualified production or observer bytes. Any further code change invalidates
this exact-candidate native evidence and requires the affected qualification to
be repeated.
