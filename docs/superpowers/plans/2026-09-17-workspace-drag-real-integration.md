# Real Workspace Drag Integration — Implementation Plan

> **Executor:** Use one `gpt-5.6-luna` agent at `xhigh` reasoning effort. Work
> sequentially in the existing consolidated worktree. Do not delegate
> implementation tasks. Request an independent review only after the candidate
> is complete and validated.

**Goal:** Turn the consolidated workspace-card drag and KVM work into one
production implementation with reversible hover presentation, exact compositor
settlement, reliable two-head test sessions, and reviewable evidence.

**Architecture:** Keep `DockWorkspaceMonitorDrag` as the one host-owned gesture
coordinator and `DockWindowActions` as the one move dispatcher. Keep the
compositor-built `workspacePresentation` immutable during hover. Derive a
display-only presentation that leaves the source entry and delegate at its
original stable key, collapses only its occupied card width, and inserts an
inert destination placeholder at the normal workspace sort position. After one
release dispatch, retain that projection until `DockWindowActions` reports the
new owner or a fixed two-second timeout expires.

**Tech stack:** Qt/QML, the existing JavaScript presentation models,
Quickshell/Hyprland APIs, Python KVM session tooling, Node model tests,
`qmltestrunner`, and the existing delivery workflow.

**Approved design:** The user-provided “Complete the real interaction,” “Fix the
testing environment,” and “Validation and delivery” requirements in the
2026-09-17 conversation. Do not reopen those product decisions during
implementation.

## Starting point

- Worktree: `/home/admin/Projects/smart-omarchy-dock/.worktrees/workspace-drag-consolidated`
- Branch: `feat/workspace-drag-consolidated`
- Consolidation head: `79e1c1c2bb2facaff94142e9beb31da136624c94`
- PR base at consolidation time: `origin/main` at
  `87c3c4f0836344769deaea99a48c25abfecc2e28`
- Consolidation report: `docs/WORKSPACE_DRAG_CONSOLIDATION.md`
- Known inherited blockers:
  - tracked preview symlinks fail `omarchy plugin validate .`;
  - the local browser-preview test fails identically on `main`;
  - production hover has no source-gap/destination-placeholder projection;
  - section geometry refreshes on every pointer update;
  - the detached QEMU head misses the title-specific no-focus rule;
  - guest dock restart reseeds applications.

Before editing, run:

```bash
cd /home/admin/Projects/smart-omarchy-dock/.worktrees/workspace-drag-consolidated
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
```

Stop if the worktree is dirty for any reason other than this plan file, if the
branch name differs, or if the recorded consolidation commit is no longer an
ancestor of `HEAD`. Fetch remote refs before recording the final delivery base,
but do not rebase or rewrite the consolidation merge until the implementation
is complete and reviewed.

## Non-negotiable invariants

- Do not add a second drag controller, window-action instance, settings writer,
  CLI command, schema field, or dock configuration key.
- Do not edit an installed Omarchy plugin checkout or the host production
  `~/.config/smartdock/dock.json`.
- Do not launch the fixture preview beside the real guest dock.
- Do not make hover state authoritative. Only Hyprland ownership read through
  the existing `DockWindowActions.resolveWorkspaceDropTarget()` path confirms a
  move.
- Do not retry a rejected or unconfirmed move automatically.
- Do not change workspace ordering rules. Use `workspaceCompare()` and the
  monitor order already present in `workspacePresentation.monitorGroups`.
- Do not remove the press-time layer-shell grab. Preserve it and add a separate
  platform drag-distance gate before beginning the workspace-monitor gesture.
- Keep the PR Draft until every required gate, including full Omarchy physical
  two-monitor qualification, is complete. Do not merge or deploy in this plan.

## Internal state contract

Keep the coordinator simple. Extend its existing booleans rather than creating
a state-machine framework:

```text
active                  pointer gesture owns the grab
awaitingConfirmation    one move was dispatched; compositor confirmation pending
captureReady            full source-card image and dimensions are available
hoveredMonitor          currently valid hover target while active
pendingMonitor          released destination while awaiting confirmation
projectionMonitor       hoveredMonitor when active, pendingMonitor while waiting
moveDispatched          guards the single dispatch
```

The coordinator continues to expose:

```text
begin(dock, workspace, label, count, monitor, scenePoint) -> bool
updatePointer(scenePoint) -> bool
finish(scenePoint) -> bool
cancel(reason)
```

Add only these internal calls:

```text
refreshTargetGeometry(dock)
reconcileCompositorOwnership()
confirmationTimedOut()
```

`finish()` must re-run target validation, reject release before capture is
ready, call `moveWorkspaceToMonitor()` once, clear pointer/ghost state, and keep
the display projection until confirmation or timeout. `cancel()` must never
dispatch.

The display projection helper belongs in `DockWorkspaceModel.js`:

```text
projectMonitorDrag(presentation, drag, visibleMonitorIdentity) -> presentation
```

`drag` contains only the already-captured source metadata and validated target:

```text
workspaceIdentity, sourceMonitor, targetMonitor, label, count
```

The helper must not mutate `presentation`. It must:

1. keep the real source group at the same stable `identity` and array position;
2. flag that source group so its existing `DockAnimatedSlot` occupies zero card
   width while its delegate remains alive;
3. insert one placeholder with a collision-proof internal identity and the
   source workspace identity as its sort key;
4. put that placeholder in the destination monitor section using existing
   monitor order and `workspaceCompare()`;
5. preserve every existing monitor group, including a temporarily empty source
   section;
6. add a placeholder only in a dock presentation that can display the target
   monitor. This covers both all-monitor same-dock sections and current-monitor
   destination docks.

## Task 1: Remove the preview symlink validation blocker

**Files:**

- Modify: `tests/runtime/workspace-drag-preview/PreviewDock.qml`
- Modify: `tests/runtime/workspace-drag-preview/run`
- Delete: `tests/runtime/workspace-drag-preview/components`
- Delete: `tests/runtime/workspace-drag-preview/assets`

- [ ] Run `omarchy plugin validate .` and retain the current symlink rejection
  in the local evidence log.
- [ ] Change the preview import to `../../../components` and its icon URLs to
  `../../../assets/...`. These paths work from the checked-in preview directory
  without repository symlinks.
- [ ] Change the preview runner to stage files under
  `$run_dir/tests/runtime/workspace-drag-preview`, create runtime-only
  `$run_dir/components` and `$run_dir/assets` links, and launch the nested
  preview path. Runtime links live under the guest session state directory and
  are not part of plugin validation.
- [ ] Delete the two tracked symlinks. Do not copy production components into
  the repository preview directory.
- [ ] Run:

```bash
bash -n tests/runtime/workspace-drag-preview/run
node tests/test_workspace_drag_preview.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_workspace_drag_preview.qml -import components
omarchy plugin validate .
git diff --check
```

**Gate:** The reference demo remains runnable and its tests pass; plugin
validation no longer rejects repository symlinks.

## Task 2: Add the pure production projection

**Files:**

- Modify: `components/DockWorkspaceModel.js`
- Modify: `tests/test_workspace_monitor_sections.mjs`
- Modify: `tests/test_presentation_model.mjs`

- [ ] First add failing model tests for:
  - input presentation is unchanged;
  - source group keeps its identity and stable presentation token;
  - source group is flagged unoccupied only when a valid foreign target exists;
  - exactly one inert placeholder is inserted;
  - placeholder uses the source identity for numeric/named workspace sorting;
  - configured monitor order is unchanged;
  - an empty source monitor group remains present;
  - all-monitor projection inserts into another section in the same dock;
  - current-monitor source projection closes only the source, while the target
    dock projection inserts only the placeholder;
  - clearing the drag returns a presentation semantically identical to live
    compositor state.
- [ ] Run the two tests and observe the new assertions fail.
- [ ] Implement `projectMonitorDrag()` with shallow copies of only the group and
  monitor-group arrays it changes. Reuse `workspaceCompare()`; do not duplicate
  workspace parsing or monitor-order logic.
- [ ] Use explicit internal fields on derived entries, for example
  `_monitorDragSource`, `_monitorDragOccupied`, `_monitorDragPlaceholder`, and
  `_monitorDragSortIdentity`. Do not let these fields enter saved settings or
  compositor state.
- [ ] Give the placeholder an internal identity such as
  `workspace-monitor-placeholder:<workspaceIdentity>`. The actual workspace
  retains its original identity.
- [ ] Recompute `firstWorkspaceIdentity` for destination prefixes, but retain an
  empty source section through its original monitor-group record.
- [ ] Run:

```bash
node tests/test_workspace_monitor_sections.mjs
node tests/test_presentation_model.mjs
node tests/test_workspace_monitor_model.mjs
git diff --check
```

**Gate:** Projection is deterministic, reversible, non-mutating, and uses the
existing reconciliation keys.

## Task 3: Make capture and gesture activation safe

**Files:**

- Modify: `components/DockWorkspaceMonitorDrag.qml`
- Modify: `components/DockWorkspaceGroup.qml`
- Modify: `tests/tst_workspacemonitordrag.qml`
- Modify: `tests/test_workspace_drag.mjs`

- [ ] Add failing QML tests for missing card, thrown capture, empty capture
  result, stale asynchronous callback, source invalidation, Escape/cancel, and
  repeated cleanup. Every failure must leave zero moves and clean all drag
  fields.
- [ ] Capture the card width, height, and `mapToItem(null, 0, 0)` origin before
  changing any appearance. Compute `grabOffset` from that snapshot. Never read
  the card size again in the callback.
- [ ] Make capture request failure abort `begin()`. Make an empty asynchronous
  capture result call `cancel("capture failed")`. Retain the returned image
  object for the whole gesture so its URL remains valid.
- [ ] Keep `dragThreshold: 0` on the header `DragHandler` because the layer-shell
  surface needs the press-time grab. Do not call `begin()`, set
  `workspaceMonitorGestureOwned`, dim the card, or suppress taps at press time.
- [ ] Store the press point and begin only after translation reaches
  `Application.styleHints.startDragDistance`. A release below that distance must
  remain an ordinary `TapHandler` click.
- [ ] Keep the monitor drag handler inside the header. Do not move it over the
  full card, where it would steal window-icon drags and context menus.
- [ ] Update the structural regression to require both the press-time handler
  and the manual platform-distance gate. Retain its checks for `TapHandler`,
  window-to-workspace drag, pointer-grab release, and the shared controller.
- [ ] Run:

```bash
node tests/test_workspace_drag.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_workspacemonitordrag.qml -import components
git diff --check
```

**Gate:** A click never starts or captures a drag, while a threshold-crossing
gesture keeps the press-time grab and captures the complete unmodified card.

## Task 4: Freeze and validate target geometry

**Files:**

- Modify: `components/DockWorkspaceMonitorDrag.qml`
- Modify: `components/Dock.qml`
- Modify: `components/DockWorkspaceLayout.qml`
- Modify: `tests/tst_workspacemonitordrag.qml`
- Modify: `tests/tst_workspacelayout.qml`
- Modify: `tests/test_workspace_drag.mjs`

- [ ] Replace the flat live `sectionHits` refresh with pickup-time snapshots per
  dock containing the clipped section rectangles and clipped workspace viewport
  fallback. Do not refresh snapshots in `updatePointer()`.
- [ ] Make `workspaceMonitorSectionHits()` return no target rectangles for a
  hidden dock. Clip every section against `workspaceMonitorViewportRect()`.
- [ ] Use the workspace viewport, excluding overflow buttons and trailing
  utilities, for the current-monitor fallback target. Never use the whole dock
  background as a drop target.
- [ ] Preserve explicit-section precedence: if the pointer covers a section for
  the current owner or a pinned/unavailable target, reject it and do not fall
  through to the dock fallback.
- [ ] Keep a hidden dock in the registry only so its normal `revealRect` can be
  tested. Entering any other hidden area must not reveal or target it.
- [ ] On reveal-strip entry, set `dragRevealed`, wait for the existing 180 ms
  reveal motion to settle, refresh only that dock snapshot, then re-evaluate the
  saved pointer position. Do not add a new animation duration.
- [ ] Add one `DockWorkspaceLayout` signal for deliberate viewport movement.
  Emit it from drag-scroll steps and completed user scrolling, but not from Row
  relayout or hover projection. The dock calls
  `refreshTargetGeometry(root)` only from this signal and completed reveal.
- [ ] Reuse the existing edge-scroll path for overflow while either window drag
  or workspace-monitor drag is active. Feed it the active controller’s scene
  point.
- [ ] Add failing-then-passing regressions for:
  - invisible section rejection;
  - reveal-strip-only activation;
  - utility and overflow-control rejection;
  - current-owner and pinned rejection;
  - frozen rectangles while the source closes and placeholder opens;
  - refresh after deliberate scrolling;
  - refresh only after destination reveal settles;
  - same-dock foreign section and cross-dock current-monitor targets;
  - unavailable dock and monitor removal cleanup.
- [ ] Run:

```bash
node tests/test_workspace_drag.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_workspacemonitordrag.qml -import components
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_workspacelayout.qml -import components
git diff --check
```

**Gate:** Hover-driven layout changes cannot retarget a stationary pointer;
only an explicit scroll or completed reveal replaces target geometry.

## Task 5: Render the source gap and destination placeholder

**Files:**

- Modify: `components/Dock.qml`
- Modify: `components/DockWorkspaceGroup.qml`
- Modify: `tests/test_workspace_monitor_sections.mjs`
- Modify: `tests/test_workspace_drag.mjs`
- Modify: `tests/tst_workspacemonitordrag.qml`

- [ ] Keep `root.workspacePresentation` as the live compositor presentation.
  Add a derived display presentation using `projectMonitorDrag()` and use it
  only for the workspace-card repeater and monitor-prefix lookup. Keep badge,
  window, fullscreen, and activation data bound to live state.
- [ ] Do not remove the source group from the display model. Bind its
  `DockAnimatedSlot.present` to the derived occupied flag. This collapses the
  source card width while the same `DockWorkspaceGroup` object and pointer
  handler remain alive.
- [ ] Insert the derived placeholder through the same
  `DockPresentationModel`. Give its slot the captured `ghostSize`, set
  `animateEntrance`, and render a disabled rectangle using current Omarchy
  semantic colors. Do not instantiate active controls for the placeholder.
- [ ] Hide the source card only after `captureReady`; before a valid target it
  may retain the existing subdued pickup state. On valid hover, close its slot
  and open the destination placeholder.
- [ ] Use the existing `DockAnimatedSlot` motion unchanged: 260 ms,
  `Easing.InOutCubic`, and immediate settling when interface animations are
  disabled. Row neighbors will move as occupied widths animate.
- [ ] Keep the ghost outside these slots. It must bind directly to pointer
  position and captured offset, with no `Behavior`, scale, or easing.
- [ ] Ensure the placeholder works when the target is another monitor section
  in the same all-monitor dock and when it is a separate current-monitor dock.
- [ ] Preserve monitor prefixes in configured order and keep the source prefix
  visible when its only card has zero occupied width.
- [ ] Add regressions that assert:
  - source reconciliation token does not change during hover/cancel/confirm;
  - placeholder identity is separate and appears once;
  - placeholder dimensions equal the captured card;
  - placeholder input is disabled;
  - source and destination occupied widths settle immediately with animations
    disabled;
  - ghost code contains no positional behavior or scale;
  - app-card drag, pin reordering, click activation, keyboard activation, and
    context-menu paths remain wired to their existing handlers.
- [ ] Run focused Node and QML tests, then the complete QML suite:

```bash
node tests/test_workspace_monitor_sections.mjs
node tests/test_workspace_drag.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components
git diff --check
```

**Gate:** The real dock reproduces the reference demo’s source closure and
destination opening without replacing the source delegate or altering live
ownership.

## Task 6: Dispatch once and settle against compositor ownership

**Files:**

- Modify: `components/DockWorkspaceMonitorDrag.qml`
- Modify: `components/Dock.qml`
- Modify: `tests/tst_workspacemonitordrag.qml`
- Modify: `tests/test_workspace_drag.mjs`

- [ ] Add failing QML tests for invalid release, duplicate release, dispatch
  returning false, dispatch throwing, delayed compositor confirmation,
  compositor rejection, timeout, source invalidation, and monitor removal.
- [ ] On release, refresh/revalidate the exact target against current
  `canMoveWorkspaceToMonitor()`. Reject release if capture is incomplete, the
  owner is unchanged, the workspace is pinned, the target disappeared, or the
  dock is unavailable.
- [ ] Set the one-shot guard before calling the shared
  `windowActions.moveWorkspaceToMonitor()`. A second release must return false
  even while confirmation is pending.
- [ ] A successful dispatcher return means only that the silent request was
  sent. End pointer ownership and remove the ghost, highlight, reveal hold, and
  keyboard focus, but retain `pendingMonitor` and the display projection.
- [ ] Add a fixed `Timer { interval: 2000; repeat: false }`. Do not make this a
  setting or public tuning property.
- [ ] At the end of each live workspace refresh, call
  `reconcileCompositorOwnership()`. That function must read
  `windowActions.resolveWorkspaceDropTarget(sourceWorkspace)` and clear pending
  state only when the returned monitor equals `pendingMonitor`.
- [ ] If ownership is still unconfirmed at timeout, clear the projection and
  show the live compositor presentation. Do not dispatch again.
- [ ] During an active gesture, a missing source or an owner different from the
  captured source cancels without dispatch. Monitor-inventory change uses the
  existing dock cancellation path for both active and pending phases.
- [ ] Test the timeout cleanup by calling the timer’s shared
  `confirmationTimedOut()` function directly; do not add a test-only duration
  option.
- [ ] Run:

```bash
node tests/test_workspace_drag.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_workspacemonitordrag.qml -import components
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components
git diff --check
```

**Gate:** One release sends at most one silent request, the optimistic layout
persists only until authoritative confirmation, and rejection always resolves
to the actual compositor state.

## Task 7: Fix two-head launch placement and one-time guest seeding

**Files:**

- Modify: `scripts/dev_session.py`
- Modify: `tests/runtime/dev-session/guest-control.sh` only if the host record
  cannot prove one-time seeding without a guest marker
- Modify: `tests/test_dev_session.py`
- Modify: `tests/test_dev_session_review.py`
- Modify: `docs/DEV_SESSIONS.md`

- [ ] Add failing Python tests that inspect the launch rule and require it to
  match both exact owned titles:
  - `QEMU (SmartDock NAME)`
  - `QEMU (SmartDock NAME): virtio-vga.1`
- [ ] Use one escaped regex with an optional detached-head suffix in both
  `_launch_rule()` and `_disable_launch_rule()`. Establish it before QEMU is
  spawned and leave it enabled until both heads have been detached, identified,
  and verified.
- [ ] After detaching, require exactly two PID-owned clients with the two
  expected titles, two distinct exact addresses, and the requested workspace.
  Store the ordered address list as `qemu_window_addresses`; retain the existing
  leftmost `qemu_window_address` for compatibility.
- [ ] Compare the before/after host active workspace and active window evidence.
  Treat changed focus or workspace as a placement failure. Never move a
  class-selected or non-owned QEMU window.
- [ ] Add `guest_seeded` to the private session record. Set it only after
  `seed-desktop` returns success and its verified payload is written to
  `evidence/guest-seed.json`.
- [ ] On later `dock NAME` restarts, skip `seed-desktop` when `guest_seeded` is
  true. Do not reset it in `sync`. A fresh session name starts false.
- [ ] Add tests proving:
  - both title variants match the rule;
  - both exact addresses are recorded and on the coding agent workspace;
  - active workspace/window remain unchanged;
  - the second `start_guest_dock()` starts one dock but performs zero additional
    seed calls;
  - sync plus restart retains `guest_seeded` and does not alter arranged guest
    workspaces/windows;
  - the exact previous guest dock is stopped before a new one starts.
- [ ] Document the address list and one-time seed behavior. Keep the fresh-name
  rule and one-real-dock-per-guest rule explicit.
- [ ] Run:

```bash
python3 -m unittest tests.test_dev_session tests.test_dev_session_review
bash -n scripts/dev-session tests/runtime/dev-session/guest-control.sh
git diff --check
```

If module-form unittest discovery is not supported by the checkout layout, use
the repository’s known working equivalent:

```bash
python3 -m unittest discover -s tests -p 'test_dev_session*.py'
```

**Gate:** Both QEMU windows are silently placed without focus theft before the
rule is removed, and restarting the candidate dock never reseeds the session.

## Task 8: Run all automated regressions

**Files:** Only files already listed. Fix production defects at their shared
owner; do not weaken tests.

- [ ] Run every shell structural guard:

```bash
for script in tests/check_*.sh; do bash "$script"; done
```

- [ ] Run every JavaScript model test:

```bash
for test_script in tests/test_*.mjs; do node "$test_script"; done
```

- [ ] Run Python tests:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m unittest discover -s provider/browser-profiles/tests -p 'test_*.py'
```

- [ ] Run pure QML tests:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components
```

- [ ] Confirm the named regression inventory is present and runnable:
  invisible targets, reveal-strip gating, stable source delegate, placeholder
  ordering/size, cancellation, duplicate release, compositor rejection,
  two-second timeout, both QEMU titles, and restart without reseeding.

**Gate:** No new failure is accepted as baseline. Fix all failures caused by the
branch before continuing.

## Task 9: Run the complete local validation gate

- [ ] Record the installed Omarchy revision used for `qs.Ui`, `qs.Commons`, and
  `qmllint` imports. This change should reuse existing primitives and should not
  introduce a new generic UI component.
- [ ] Run the repository-required gate:

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml components/DockWorkspaceMonitorDrag.qml \
  components/DockWorkspaceGroup.qml components/DockWorkspaceLayout.qml shell.qml
bash tests/runtime/check-workspace-resize.sh
git diff --check origin/main...HEAD
```

- [ ] For the six-second smoke command, accept timeout only after verifying the
  log shows successful dock startup and no QML load/runtime error.
- [ ] Run the browser-preview reproduction separately on this branch and a
  clean `main` checkout:

```bash
python3 -m unittest discover -s tests -p 'test_browser_activity_preview.py'
```

- [ ] If the browser-preview result is byte-for-byte or assertion-for-assertion
  equivalent to the already-recorded `main` failure, link it as a separate
  baseline issue and record both SHAs/results in the Draft PR. Do not change
  browser preview code in this workspace-drag branch.
- [ ] If the branch adds or changes that failure, treat it as a branch
  regression and fix it here.

**Gate:** Plugin validation and every branch-owned local gate pass. A required
baseline failure keeps the PR Draft until its separate disposition is clear.

## Task 10: Qualify the real interaction in fresh KVM sessions

Use the verified image from `docs/DEV_SESSIONS.md`. Use fresh names; do not
reuse prior evidence directories.

### Session A — all-monitor scope

- [ ] Start one standalone guest from this worktree on the coding agent’s
  current Hyprland workspace. Verify both recorded QEMU addresses and titles are
  on that workspace and the user’s active workspace/window did not change.
- [ ] Start exactly one real dock. Record seeded client addresses, workspace
  owners, and window count.
- [ ] Use actual press-drag-release pointer input to cover:
  - numeric, named, empty, active, and inactive workspace cards;
  - another monitor section within the same dock;
  - configured monitor order;
  - pinned rejection and current-owner rejection;
  - Escape and invalid background cancellation;
  - animations enabled and disabled;
  - monitor removal during an active gesture.
- [ ] Sync source and restart the dock. Verify the original seeded window
  addresses and arranged workspace ownership survive and no new foot/thunar
  windows appear.

### Session B — current-monitor scope

- [ ] Start a second fresh standalone guest and one real dock.
- [ ] Use actual pointer input to cover:
  - cross-dock drag to the other monitor;
  - hidden destination that rejects all areas except its reveal strip;
  - completed reveal followed by a valid target;
  - overflow edge scrolling followed by refreshed target geometry;
  - release during unavailable destination and compositor rejection;
  - two-second rollback with no automatic retry.

### Compatibility checks in both sessions

- [ ] A short header click activates once and never shows a ghost.
- [ ] Keyboard Return/Space activation still works.
- [ ] App context menus open and act on the selected app.
- [ ] Pinned app reordering works.
- [ ] Window-icon drag to another workspace card works.
- [ ] Ordinary window previews and window activation work.
- [ ] Only one move request appears for each completed workspace-monitor drag.
- [ ] The ghost preserves complete card dimensions, icons, badges, label, and
  pointer offset. It does not scale or ease.
- [ ] Source closure, neighbor motion, destination opening, cancel restoration,
  and confirmation settlement match the reference demo at 260 ms.
- [ ] Capture representative before, pickup, hover, release, cancellation,
  disabled-animation, reveal, and overflow PNGs. Store guest logs and ownership
  snapshots beside them.
- [ ] Stop both named sessions and verify production settings hash, installed
  plugin checkout, host focus, and host active workspace are unchanged.

**Gate:** Both scope modes pass with real input and real compositor ownership.
Function calls or the fixture preview do not qualify this gate.

## Task 11: Complete full Omarchy two-monitor qualification

- [ ] Use a dedicated full Omarchy two-monitor environment with a private copy
  of the candidate source and private SmartDock settings. Do not update the
  installed production plugin.
- [ ] Repeat the core all-monitor and current-monitor press-drag-release cases,
  pins, auto-hide reveal, overflow, animations disabled, cancellation, and
  monitor removal.
- [ ] Verify the host-owned coordinator and shared window-action controller are
  the only instances in plugin mode.
- [ ] Record exact environment revision, base/head SHAs, monitor inventory,
  commands, captures, and results.
- [ ] Treat the stripped plugin guest as supplemental evidence only. If a full
  Omarchy two-monitor environment is unavailable, leave the PR Draft and record
  this gate as unresolved.

**Gate:** Full Omarchy physical behavior passes on the exact candidate SHA.

## Task 12: Review and deliver one Draft PR

- [ ] Review the final diff for accidental CLI/schema/config/settings-writer,
  deployed-plugin, browser-preview, and unrelated UI changes.
- [ ] Update `docs/WORKSPACE_DRAG_CONSOLIDATION.md` with the final integration
  status and links to sanitized evidence. Keep detailed machine-local logs under
  `~/.local/state/smartdock/` rather than committing them.
- [ ] Commit coherent checkpoints. Before the final evidence run, squash only if
  it improves review; any rewrite invalidates old evidence.
- [ ] Fetch `origin`, confirm the intended PR base, and record:

```bash
git rev-parse origin/main
git rev-parse HEAD
```

- [ ] Run the complete automated and local gates again on that exact head.
- [ ] Push `feat/workspace-drag-consolidated` and open one Draft PR against
  `main`. The PR must state the concrete before/after behavior, exact base/head
  SHAs, automated results, KVM evidence, full Omarchy evidence, and the separate
  browser-preview baseline link.
- [ ] Request independent code review of the exact PR head. The reviewer must
  inspect capture ordering, stable delegate lifetime, target clipping/freezing,
  one-shot release, timeout cleanup, monitor removal, title rules, seed
  persistence, and the absence of new configuration/public APIs.
- [ ] Address review findings, then rerun every affected gate and replace the
  recorded head SHA.
- [ ] Mark the PR Ready only when Headless CI, local validation, fresh KVM
  qualification, full Omarchy two-monitor qualification, and independent review
  all pass for the same head/base pair.
- [ ] Stop with the PR open. Do not merge `main`, update the installed plugin,
  or deploy.

## Final acceptance checklist

- [ ] One host-owned `DockWorkspaceMonitorDrag`; one shared
  `DockWindowActions`.
- [ ] Full source card captured before appearance changes.
- [ ] Stable source delegate and pointer grab through the gesture.
- [ ] Source gap and inert equal-size destination placeholder use existing
  presentation/animation components.
- [ ] 260 ms `InOutCubic`; animation-disabled immediate settlement; direct
  unscaled ghost.
- [ ] Both monitor scopes, same-dock foreign sections, monitor order, empty
  temporary sections.
- [ ] Viewport clipping, reveal-strip gating, frozen geometry, deliberate
  refresh only.
- [ ] Pins/current owner/utilities/unavailable surfaces rejected.
- [ ] Every cancellation path restores live state with zero dispatches.
- [ ] Exactly one silent move; authoritative confirmation or two-second rollback;
  no retry.
- [ ] Click, keyboard, menu, app reorder, preview, and window-drag regressions
  pass.
- [ ] Both QEMU titles are silently placed and exact addresses verified.
- [ ] Guest seed occurs once; sync/restart preserves windows/workspaces.
- [ ] Complete automated/local/KVM/full-Omarchy evidence recorded for exact
  base/head SHAs.
- [ ] Independent review complete; single PR remains separate from merge and
  deployment.
