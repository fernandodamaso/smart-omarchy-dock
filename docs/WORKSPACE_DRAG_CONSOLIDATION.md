# Workspace drag branch consolidation

## Inputs

- `origin/main`: `87c3c4f0836344769deaea99a48c25abfecc2e28`
- Local `main`: `4026d8bee7113d49994917bd99a6cb57247eef51`
- `feat/kvm-production-parity`: `018caef125c5ae710bc2ccdf219458e14fba8f30`
- `feat/70-workspace-drag-visual-gate`: `ac41a66cc7d634679938f775d9cde7910ec3cbf1`

The consolidated branch is based on the production-parity commit and merges
the visual-gate branch with the resolutions recorded below.

## Resolutions

The parity versions were retained for the three overlapping files:

- `scripts/dev_session.py` retains the complete launcher, including its two
  outputs, owned-window handling, AT-SPI support, periodic FD guard, font setup,
  and current guest lifecycle.
- `tests/test_dev_session.py` retains the complete parity test file, including
  the FD-guard test without duplicating it from the prototype merge.
- `docs/DEV_SESSIONS.md` retains the parity documentation with one FD-guard
  section and the two-output production-testing instructions.

The prototype-only preview directory, its focused tests, and the historical
workspace-drag visual-gate plan were imported. The archived prototype
`PreviewDock.qml` icon-string edit was copied into the consolidated worktree.

## Local changes

- The prototype icon fix was copied from the verified archive.
- The prototype font-package and cache changes were already present in the
  parity launcher and development-session documentation.
- The prototype `.superpowers/` notes were archived outside Git and were not
  imported into this branch.
- Archive: `/home/admin/.local/state/smartdock/branch-consolidation/20260917T000000Z`

## Validation

Logs are stored outside Git in the archive's `logs/` directory. Results are
recorded here after the checks run.

| Check | Result | Log |
| --- | --- | --- |
| Preservation checks | PASS: source statuses, archived hashes, parity areas, merge state, conflict markers, and whitespace checks | `logs/preservation-checks.txt` |
| `node tests/test_workspace_drag_preview.mjs` | PASS | `logs/node-preview.txt` |
| `node tests/test_workspace_drag.mjs` | PASS | `logs/node-workspace.txt` |
| `test_dev_session*.py` | PASS: 61 tests | `logs/python-dev-session.txt` |
| `qmltestrunner -input tests -import components` | PASS: 228 tests | `logs/qmltestrunner.txt` |
| Four required `bash -n` checks | PASS | `logs/bash-scripts-dev-session.txt`, `logs/bash-guest-control.txt`, `logs/bash-preview-runner.txt`, `logs/bash-preview-qualify.txt` |
| Plugin validation blocker reproduction | EXPECTED FAIL: prototype `tests/runtime/workspace-drag-preview/assets` symlink rejected | `logs/plugin-validate.txt` |
| Browser-preview blocker reproduction | EXPECTED FAIL: 1 Python test with 5 QML failures; same result on local `main` | `logs/browser-preview.txt`, `logs/browser-preview-main.txt` |

## Real integration

- Preview symlinks are removed; `omarchy plugin validate .` now passes.
- `projectMonitorDrag()` is a non-mutating display projection. The live
  compositor presentation remains authoritative; the source delegate stays at
  its stable identity while an inert equal-size destination placeholder is
  shown during hover and confirmation.
- Capture, platform drag-distance activation, frozen/clipped target geometry,
  reveal-settle refresh, one-shot dispatch, compositor confirmation, timeout,
  and monitor-removal cleanup are covered by the focused and full QML suites.
- The development-session launcher matches both exact QEMU head titles,
  records `qemu_window_addresses`, compares stable focus/workspace identities,
  and persists one-time guest seeding across sync/restart.

Automated results on the current working head:

| Check | Result |
| --- | --- |
| Structural shell checks | PASS |
| JavaScript model tests | PASS |
| Python tests (`tests`) | 116 pass; 1 known browser-preview baseline failure |
| Python provider tests | PASS: 20 tests |
| QML tests | PASS: 230 tests |
| `omarchy plugin validate .` | PASS |
| Targeted `qmllint` gate | PASS with existing unqualified-access/import warnings |
| `timeout 6s ./scripts/run --no-color` | Startup reached `Configuration Loaded`; expected timeout 124 |
| Workspace resize harness | Baseline issue: prints `workspace-resize: PASS` but exits 1 because stripped-shell `ReferenceError: ToplevelManager is not defined` is matched by the harness; reproduced on `main` |
| Browser preview | Baseline issue: 5 QML failures; reproduced unchanged on `main` `4026d8bee7113d49994917bd99a6cb57247eef51` |

KVM evidence is retained outside Git under
`~/.local/state/smartdock/dev-sessions/workspace-drag-kvm-20260917/`:

- `record.json`: ready standalone guest, outputs `Virtual-1`/`Virtual-2`, two
  exact QEMU addresses on workspace `2`, and `guest_seeded: true`.
- `evidence/guest-seed.json`: verified seed payload for four guest clients.
- `evidence/frame-001.png` and `frame-002.png`: two-head guest captures.
- Two sync/restart cycles retained the seed file timestamp and size and did
  not create another seed payload. Stop removed all named QEMU windows and the
  host production settings SHA-256 stayed
  `c0f5098ec03ef1da1006dbed8e30d44a836b9e8ca81880969379ff77e9cc4bd8`.

The exact Omarchy environment used for imports was `omarchy 4.0.3-1`, with
`/usr/share/omarchy/version` reporting `4.0.0.alpha`.

## Remaining qualification

- Full Omarchy two-monitor qualification remains unresolved; only the stripped
  standalone guest was available.
- The exposed computer-use surface could not target the native QEMU windows,
  so actual press-drag-release pointer evidence for the real dock was not
  collected. The guest capture and seed/restart checks are supplemental only.
- Keep the PR Draft until those physical gates and the independent review are
  complete. The browser-preview and resize results remain separate baseline
  issues and were not changed by this branch.

## Status

Real integration is implemented and locally validated; delivery and physical
qualification remain incomplete by design. Do not merge, deploy, or update the
installed plugin from this branch.

## Review fixes — working-tree candidate (2026-09-17)

The eight findings in `docs/superpowers/plans/2026-09-17-workspace-drag-review-fixes.md`
were applied to the working tree from head
`5ff09e85f6ab2e671e91b75f5a4a923321cf6a73`. No commit, push, merge, deployment,
installed-plugin edit, or host-settings mutation was made. The pre-existing
integration plan remains byte-for-byte preserved; its checksum is recorded in
`~/.local/state/smartdock/workspace-drag-review-20260917T123008/preserved-plan.sha256`.

The candidate now measures semantic drag distance from Qt's press position,
preserves owned handlers through source clipping/collapse, keeps source and
destination coordinate spaces separate, retains captured placeholder size
through confirmation, merges revealed geometry without replacing unrelated
snapshots, and gates presentation styling and updates by source identity.
The final review pass also fixed Escape focus routing, clears icon click
suppression after an outside release, starts an icon drag on a single initial
move beyond the platform threshold, and makes the input fixture execute the
production suppression bindings.

Headless evidence is stored outside Git at
`~/.local/state/smartdock/workspace-drag-review-20260917T123008/`:

- Production Qt pointer harness: 15 passed (`workspace_input_final.log`).
- Focused monitor-drag and layout suites: 14 and 10 passed.
- Full QML suite: 234 passed, 0 failed (`qml_tests_final.log`).
- All `tests/test_*.mjs`, provider tests (20), shell syntax, plugin validation,
  targeted `qmllint`, and `git diff --check`: passed.
- Full Python suite: 118 tests with one known browser-preview baseline failure
  containing five QML assertions; the workspace-drag input cases in that run
  passed. This remains the documented pre-existing baseline failure.
- Standalone startup smoke reached `Configuration Loaded` and exited 124 at
  the six-second timeout; stripped-shell `ToplevelManager` warnings are the
  existing startup-harness limitation.

The read-only independent review was performed by Herdr agent `astra-review2`
using `gpt-6-astra` at high reasoning effort. Astra identified three additional
in-scope regressions and one fixture-coverage gap; each was corrected and the
affected/full suites were rerun. The review transcript is retained at
`astra-review-final.log` in the evidence directory.

The isolated guest session `workspace-drag-fix-20260917` used standalone mode
with `Virtual-1` and `Virtual-2`, completed two sync/restart cycles, and
produced `frame-001.png` through `frame-003.png`. Its two QEMU windows were
silently placed on coding workspace 2 at addresses
`0x564e341d0f80` and `0x564e341d3da0`; the session was stopped and both windows
were removed. The seed evidence retained timestamp/size `1789660559 1978` and
SHA-256
`225f6ccc50e664e5627e261a960e44184c0ea3bf419766e850c29fed2fd8f7b8` across
both restarts. Host production settings retained SHA-256
`c0f5098ec03ef1da1006dbed8e30d44a8366dbed8e30d44b9e8ca81880969379ff77e9cc4bd8`.

Native press-drag-release qualification on the real dock remains pending: the
available computer-use surface exposed Chrome but could not target the native
QEMU windows. Guest startup, captures, and seed persistence are supplemental
evidence only and do not qualify Hyprland pointer grabs, focus, auto-hide, or
live image behavior. Keep this candidate Draft/unqualified until those native
checks are performed.
