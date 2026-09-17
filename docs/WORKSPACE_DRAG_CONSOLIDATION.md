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

## Stage-two backlog

- Prototype symlinks prevent plugin validation.
- Prototype accepts hidden destination targets.
- Production coordinator accepts unavailable destination sections.
- Detached QEMU window misses the no-focus launch rule.
- Restarting the guest dock reseeds applications and workspace placement.
- The real dock still lacks the complete reference placeholder and gap-animation behavior.
- The browser-preview Python failure also reproduces on local `main`.

## Status

Consolidated locally; feature integration and merge qualification remain
incomplete.
