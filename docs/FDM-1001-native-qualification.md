# FDM-1001 — native Widget qualification

## Delivery scope

FDM-1001 qualifies the integrated FDM-997/FDM-998/FDM-999 candidate carried by
Draft PR #115. The entry head was
`5c594d5f5459b53f52685a559ca72bac6b5695db`; the final PR head and base are
recorded in the pull request because every follow-up commit changes that exact
identity.

FDM-1000 is **not included / not required for v1**. FDM-995 remains an
independent acceptance gate. This qualification does not authorize a merge,
deployment, installed-plugin update, or production-desktop preview.

## Accepted evidence

The maintainer selected a focused acceptance gate after the original exhaustive
matrix proved disproportionate to the change. The following evidence is the
FDM-1001 acceptance scope:

- The production-QML runtime fixture passed host, panel, delegate, Widget,
  resize writer-count, provider lifecycle, popup, layer, teardown, and settings
  persistence checks.
- The fail-closed native observer passed on two 1280×960 scale-1 outputs with
  four presented demo Widgets, conserved hierarchy/Widget/blank allocation,
  valid independent scroll ranges, and settled restore/input/reorder state.
- An inspected KVM visual stress sample passed with both sidebars on the right
  edge at effective width 480: separate panes, readable card chrome, usable
  fixed controls, and no scrollbar/resize overlap or malformed surfaces.
- Focused Python qualification and dev-session suites passed: 64 tests.
- The sidebar Widget Node structural suite, `omarchy plugin validate .`, Bash
  syntax, Python compilation, `qmllint` (with existing warnings), and
  `git diff --check` passed.
- The full QML run completed with 450 passing tests and the same four known
  baseline failures in `tst_herdr_remote_fallback.qml`.
- Provider diagnostics remained 4 acquisitions, 4 activations, 0 releases,
  0 suspensions, and 0 failures.

The retained local evidence root is
`~/.local/state/smartdock/dev-sessions/fdm1001-standalone-r3/evidence/`.
The guest was stopped with `qemu_alive=false`; the production settings hash was
unchanged.

## Not separately exercised

The following exhaustive matrix rows are explicitly non-blocking and are not
claimed as passes: synthetic/native wheel-action timelines, complete
Tab/Shift+Tab and caret traversal, native reorder and cancellation paths,
popup/background-drag interaction permutations, the full theme/font/edge/width
matrix, fractional-scale plugin interaction, physical touchpad behavior,
physical monitor/hotplug behavior, and full Omarchy-shell integration.

Automated source tests already exercise wheel routing, keyboard traversal,
reorder cancellation, popup geometry, allocation boundaries, and the relevant
FDM-994 regressions. The local KVM observer qualifies the integrated layout and
runtime settlement; it is not represented as a physical-device interaction
verdict.

## Qualification tooling

The follow-up commits add fail-closed, sanitized native observer telemetry and
verdict parsing, explicit config/evidence provenance, per-monitor persistence
readback, and fixture corrections found while running the production QML. The
tooling is test-only and does not add a runtime settings writer or alter the
production dock lifecycle.
