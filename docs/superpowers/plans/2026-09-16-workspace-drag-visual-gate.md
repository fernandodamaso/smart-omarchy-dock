# Workspace Drag Visual Prototype — Implementation Plan

> Historical design reference. The demo’s intended behavior is the target for
> stage-two production integration. Do not execute this historical implementation
> plan as part of branch consolidation. Its recorded runtime evidence does not
> qualify the consolidated branch.

> **For agentic workers:** Work inline using `superpowers:executing-plans` and
> `superpowers:using-git-worktrees`. The scope below is already approved. Proceed
> through implementation and verification, then stop for visual approval.

**Goal:** Build an isolated, interactive visual prototype for cross-monitor
workspace dragging before connecting the interaction to real workspace moves.

**Architecture:** Run a preview-only QML host inside a fresh named KVM guest. It
uses actual SmartDock card components with fixture data, derives temporary hover
layouts from immutable committed fixtures, and commits drops only to in-memory
fixture ownership.

**Tech stack:** Qt/QML, Quickshell, JavaScript model helpers, existing SmartDock
components, and the named KVM workflow in `scripts/dev-session`.

**Spec:** Approved conversation plan, “VM-first visual design gate for workspace
dragging,” revised into the decision-complete implementation steps below.

## Global constraints

- Follow `AGENTS.md`, `docs/DELIVERY.md`, and `docs/DEV_SESSIONS.md`.
- Existing PRs #71 and #72 provide production dragging but do not satisfy this
  visual gate; their presence is not a blocker.
- Change fixture ownership in memory only.
- Do not instantiate `DockHost`, `DockWindowActions`, or the production `Dock`
  host in the prototype.
- Do not dispatch Hyprland workspace commands, write dock settings, update the
  installed plugin, or fix production cross-monitor drops in this phase.
- Keep workspace identities, keyboard shortcuts, automatic workspace sorting,
  and configured monitor ordering unchanged.
- Do not merge or deploy before the user's visual approval.
- Work inline; subagent delegation is not authorized for this execution.

---

## Task 1: Create the isolated branch and record the design baseline

**Files:**

- Create: the isolated worktree selected by `superpowers:using-git-worktrees`
- Modify: none

- [ ] Read current `AGENTS.md`, `docs/DELIVERY.md`, and `docs/DEV_SESSIONS.md`.
- [ ] Fetch current remote state and create a fresh worktree and branch named
  `feat/70-workspace-drag-visual-gate` from current `origin/main`. Do not reuse
  `fix/72-stable-workspace-drag-focus` or overwrite an existing worktree.
- [ ] Record `git rev-parse origin/main` and `git rev-parse HEAD`; they must match
  before implementation begins.
- [ ] Record the exact installed Omarchy revision. Inspect current `qs.Ui`
  controls and one matching first-party call site before adding preview controls.
- [ ] Confirm that the installed production plugin and its settings are outside
  the worktree and remain untouched.

**Gate:** The branch is isolated from current main, the base SHA is recorded, and
no production process or deployed checkout has changed.

## Task 2: Add the pure fixture projection model

**Files:**

- Create: `tests/runtime/workspace-drag-preview/PreviewModel.js`
- Create: `tests/test_workspace_drag_preview.mjs`

**Interfaces:**

```text
workspaceCompare(left, right) -> number
project(fixtures, drag) -> { monitors, workspaceOwners }
commit(fixtures, workspaceIdentity, targetMonitor) -> fixtures
```

`fixtures` contains ordered monitor descriptors and workspace descriptors with
stable identities and owners. `drag` is either null or contains
`workspaceIdentity` and `targetMonitor`. Every returned object is newly derived;
the input fixtures are never mutated.

- [ ] Write Node tests proving that hover projection leaves committed fixtures
  unchanged, assigns the dragged workspace only in the derived presentation,
  preserves monitor order, sorts workspaces with the existing
  `DockWorkspaceModel.workspaceCompare`, rejects the current owner and pinned
  destinations, and commits a valid simulated move exactly once.
- [ ] Run the test and observe failure because the model does not exist.
- [ ] Implement the smallest projection model satisfying those cases. Import or
  reuse the repository's workspace comparator rather than duplicating its rules.
- [ ] Run the focused Node test and confirm it passes.

**Gate:** Committed fixture state and temporary hover state are separate, sorting
is deterministic, and no configuration or compositor API is involved.

## Task 3: Build the preview docks from real SmartDock visuals

**Files:**

- Create: `tests/runtime/workspace-drag-preview/PreviewDock.qml`
- Create: `tests/runtime/workspace-drag-preview/shell.qml`

**Interfaces:** `PreviewDock` consumes fixture monitors, the current derived
presentation, the shared preview drag controller, scope mode, animations state,
and simulated auto-hide state. It exposes monitor-section rectangles, reveal
rectangles, card lookup by workspace identity, and its physical monitor identity.

- [ ] Create an ordinary preview window with two clearly labeled simulated
  monitor areas. Each area contains a bottom dock built from actual
  `DockWorkspaceGroup`, `DockMonitorLabel`, and `DockAppIcon` components.
- [ ] Use deterministic local artwork and fixture badges. Do not depend on real
  applications, toplevels, workspaces, or desktop-entry discovery.
- [ ] Add baseline fixtures:
  - Monitor A: workspace `1` with one icon, workspace `2` with three icons and a
    badge, and empty workspace `3`.
  - Monitor B: workspace `4` with two icons and named workspace `Work` with its
    full label.
  - Give each monitor one active fixture workspace.
- [ ] Add preview-only controls for reset, all-monitor/current-monitor scope,
  pinned rejection, an initially empty destination monitor, overflow,
  destination auto-hide, and disabled animations.
- [ ] Use current Omarchy semantic tokens and an existing `qs.Ui` primitive when
  it satisfies the controls' focus, pointer, and theme contract.
- [ ] Scenario changes and reset must cancel an active gesture before replacing
  fixtures.

**Gate:** The preview renders representative real cards and monitor sections from
fixture state without starting a second production dock.

## Task 4: Implement preview gesture state and full-card capture

**Files:**

- Create: `tests/runtime/workspace-drag-preview/PreviewDrag.qml`
- Modify: `tests/runtime/workspace-drag-preview/PreviewDock.qml`
- Modify: `tests/runtime/workspace-drag-preview/shell.qml`
- Create: `tests/tst_workspace_drag_preview.qml`

**Interfaces:** The preview controller implements the contract already consumed
by the workspace header:

```text
begin(dock, workspace, label, count, monitor, scenePoint) -> bool
updatePointer(scenePoint) -> bool
finish(scenePoint) -> bool
cancel(reason)
active, sourceDock, sourceWorkspace
```

- [ ] Write QML tests for begin/update/finish/cancel, duplicate finish, stale
  capture callbacks, current-owner rejection, pinned rejection, and cleanup after
  fixture replacement.
- [ ] Run the focused QML test and observe failure before implementation.
- [ ] Reuse the existing workspace-header `DragHandler` through the controller
  contract. Preserve platform drag threshold, header activation, Escape, and
  click suppression; do not copy its pointer-input logic.
- [ ] On pickup, find the actual source card and call `grabToImage` before
  dimming it. Retain the result for the gesture, including logical dimensions
  and pointer offset.
- [ ] Ignore capture callbacks belonging to cancelled or superseded gestures.
  Capture failure cancels and restores the committed presentation.
- [ ] Render one non-interactive ghost in the shared preview-window overlay. It
  follows the pointer directly without positional easing.
- [ ] Keep source delegates alive under stable parents even while their visible
  layout gap closes. Ghosts and placeholders must never intercept input.
- [ ] Confirm release completes once and does not subsequently activate the
  workspace header.
- [ ] Run the focused QML and Node tests until both pass.

**Gate:** Drag pickup shows a pixel-faithful full-card ghost, the pointer grab
survives layout changes, and cancellation restores the exact committed view.

## Task 5: Add monitor targets, placeholders, and layout animation

**Files:**

- Modify: `tests/runtime/workspace-drag-preview/PreviewDrag.qml`
- Modify: `tests/runtime/workspace-drag-preview/PreviewDock.qml`
- Modify: `tests/runtime/workspace-drag-preview/shell.qml`
- Modify: `tests/tst_workspace_drag_preview.qml`
- Modify: `tests/test_workspace_drag_preview.mjs`

- [ ] Extend tests for same-dock monitor-section targeting, targeting another
  simulated dock, invalid background, automatic destination sort position,
  all-monitor/current-monitor scope, empty sections, auto-hide reveal, overflow,
  and animations disabled.
- [ ] Resolve targets by monitor section, including another monitor's section in
  the same simulated dock. A section includes its label, cards, and internal
  gaps. Clip target rectangles to the visible viewport.
- [ ] Treat unknown sections, utility controls, and the workspace's current owner
  as invalid. Unused dock background targets that dock's physical monitor.
  Explicit section identity takes precedence.
- [ ] Reject pinned cross-monitor moves and use the forbidden cursor without
  opening a destination placeholder.
- [ ] On valid hover, derive a presentation from committed fixtures with the
  dragged workspace assigned to the target monitor. Replace its destination card
  with a same-sized placeholder at the automatic sort position.
- [ ] Initially retain a subdued, card-sized placeholder at the source. Once a
  valid foreign target is active, animate the source gap closed and open the
  destination placeholder. Neighboring cards and monitor labels move with their
  sections.
- [ ] Use `260 ms` with `Easing.InOutCubic` for position and occupied-space
  changes. Do not stretch or shrink the captured ghost. Settle immediately when
  animations are disabled.
- [ ] Keep configured monitor order fixed and retain empty monitor targets during
  the gesture. Reconcile empty sections after completion.
- [ ] Snapshot section hit regions before applying hover projection. Animated
  geometry beneath a stationary pointer must not retarget the gesture. Refresh
  the baseline only after explicit scrolling; cancel on preview resize or fixture
  replacement.
- [ ] For simulated auto-hide, require the source dock to be visible first. A
  destination reveal strip opens its dock and keeps it open until the gesture
  ends.
- [ ] Valid release updates fixture ownership once, settles the ghost into the
  destination placeholder, and then removes transient state. Invalid release or
  Escape restores committed geometry.
- [ ] Run focused Node and QML tests.

**Gate:** Pickup, hover, target changes, simulated completion, and cancellation
produce stable, reversible visuals without custom workspace ordering.

## Task 6: Add an owned VM preview runner

**Files:**

- Create: `tests/runtime/workspace-drag-preview/run`
- Modify: `docs/superpowers/plans/2026-09-16-workspace-drag-visual-gate.md`

- [ ] Implement a guest-only launch/stop wrapper for the preview. It must require
  `SMARTDOCK_SESSION_NAME` and guest compositor environment, launch the preview's
  `shell.qml`, record the exact PID plus process start identity, and stop only
  that owned process.
- [ ] Reject broad process-name killing and reject execution outside a named guest
  session.
- [ ] Verify the wrapper with shell syntax checks and one start/status/stop cycle
  inside the guest.
- [ ] Record the exact tested launch, reset, capture, stop, and relaunch commands
  in this plan's execution ledger or appended evidence section.

**Gate:** The preview has an exact, repeatable guest lifecycle and cannot target
the host production dock.

## Task 7: Run the VM design qualification

**Files:** No new source files unless qualification reveals a defect in the
prototype.

- [ ] Start a fresh named standalone KVM session using the verified Arch image
  documented in `docs/DEV_SESSIONS.md`.
- [ ] Place the QEMU window silently on the coding agent's current Hyprland
  workspace without stealing focus. Verify its exact address and workspace with
  `hyprctl clients -j`.
- [ ] Let normal initialization stage Omarchy QML assets. Stop the automatically
  launched guest dock through the existing guest-control `stop-dock` action
  before launching the preview.
- [ ] Launch the preview through `scripts/dev-session exec`, inheriting the guest
  compositor environment and staged `qs.Commons`/`qs.Ui` imports.
- [ ] For each source iteration: stop the preview, sync the worktree, restart the
  preview, and capture evidence. Never run the regular guest dock beside it.
- [ ] Exercise actual press-drag-release input and verify:
  1. Full-card ghost fidelity, including icons, badge, and named header.
  2. Smooth source closure and destination opening.
  3. Stable targets without oscillation or pointer-grab loss.
  4. Same-dock section targeting and movement between simulated docks.
  5. Exact restoration after Escape and invalid release.
  6. Repeated moves, empty sections, overflow, auto-hide, and disabled animation.
  7. No accidental click activation after a drag.
  8. No workspace dispatches or settings writes.
- [ ] Capture representative PNG frames and logs beneath the named session's
  evidence directory. Label them explicitly as simulated-monitor evidence.
- [ ] Stop the preview and named VM session. Verify that the production dock PID,
  production settings hash, active workspace, and focus were unchanged.

**Gate:** Rendering and input pass in the VM. Simulated monitors qualify only the
visual design; they do not qualify real cross-window pointer delivery.

## Task 8: Validate and hand off for visual approval

**Files:** Only previously listed files.

- [ ] Run the focused Node and QML tests.
- [ ] Run `bash -n` on the preview runner and `git diff --check`.
- [ ] Run touched-file `qmllint` with the Omarchy shell import path.
- [ ] If any shared production component changed, also run every validation gate
  required by `AGENTS.md` and demonstrate unchanged production behavior.
- [ ] Review the diff for accidental configuration, schema, CLI, runtime-action,
  or deployed-plugin changes.
- [ ] Commit the prototype and record exact base/head SHAs. If a PR is opened,
  keep it explicitly marked as a design prototype.
- [ ] Present the runnable VM preview, representative captures, exact SHA,
  validation results, commands, and limitations to the user.

**Final gate:** Stop for explicit visual approval. Production integration,
failed-drop diagnosis, physical two-monitor verification, merging, and deployment
belong to the next phase.


## Execution evidence (2026-09-16)

- Branch: `feat/70-workspace-drag-visual-gate`
- Base/HEAD at implementation start: `87c3c4f0836344769deaea99a48c25abfecc2e28`
- Omarchy package inspected: `4.0.3-1` (`Ui.Button` / `Ui.Toggle`; first-party ToggleSwitch usage in bluetooth panel)
- Host production settings hash unchanged: `7ccbbaf5f2152fd9caf58a0f3665b11cc1177171c551f9878a2b268009d5a5ad`
- Session: `drag-visual-gate-a` (standalone), QEMU moved to host workspace `10` without follow-focus
- Guest commands:

```bash
./scripts/dev-session start drag-visual-gate-a --source <worktree> \
  --base-image ~/.local/state/smartdock/dev-sessions/_kvm-feasibility/images/Arch-Linux-x86_64-cloudimg.qcow2 \
  --mode standalone --workspace 10
./scripts/dev-session sync drag-visual-gate-a
./scripts/dev-session exec drag-visual-gate-a -- /home/admin/smartdock-candidate/tests/runtime/dev-session/guest-control.sh stop-dock
# then guest preview lifecycle:
SMARTDOCK_SESSION_NAME=drag-visual-gate-a OMARCHY_PATH=/home/admin/smartdock-omarchy-test \
  WAYLAND_DISPLAY=… HYPRLAND_INSTANCE_SIGNATURE=… \
  tests/runtime/workspace-drag-preview/run start|status|stop
grim -o Virtual-1 …/evidence/simulated-monitors-baseline.png
./scripts/dev-session capture drag-visual-gate-a
```

- Evidence: `~/.local/state/smartdock/dev-sessions/drag-visual-gate-a/evidence/simulated-monitors-*.png`
- Focused tests: `node tests/test_workspace_drag_preview.mjs` PASS; `qmltestrunner … tst_workspace_drag_preview.qml` 5/5 PASS
- Limitation: guest absolute ydotool coords are unreliable under pointer acceleration; interactive drag review in the QEMU window is required for ghost/placeholder visual approval. Simulated monitors do not qualify real cross-window pointer delivery.
