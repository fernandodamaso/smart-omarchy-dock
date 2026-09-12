# SmartDock workspace dragging — implementation plan and worker handoff

Repository execution copy of the approved
[native Linear implementation plan](https://linear.app/fdamaso/document/smartdock-workspace-dragging-implementation-plan-and-worker-handoff-6835a84fdae6).
The native document remains the planning source. This copy records the same
behavioral contract, its implementation mapping, and the remote/local boundary.

- Parent: [FDM-888](https://linear.app/fdamaso/issue/FDM-888).
- Remote implementation: [FDM-889](https://linear.app/fdamaso/issue/FDM-889).
- Local Omarchy qualification: [FDM-890](https://linear.app/fdamaso/issue/FDM-890).
- Repository: `fernandodamaso/smart-omarchy-dock`.
- Candidate: `feat/fdm-889-workspace-drag`, [Draft PR #45](https://github.com/fernandodamaso/smart-omarchy-dock/pull/45).
- Implementation base: `4f5d77b0fc7bf20a48365cd2c54dab00a150b373`.
- Read the current `AGENTS.md` and `docs/DELIVERY.md` before continuing work.

Exact accepted head, review and CI run links belong in the PR and Linear
handoff, not a self-referential SHA inside this file. A passing remote candidate
is not an installed release or evidence of native pointer/compositor behavior.

## Goal and boundaries

Allow running windows represented by a dock icon to be dragged onto another
workspace card in effective top/bottom grouped layouts. Reuse the existing
host-owned window controller, presentation models and bounded workspace layout.
There is no new setting, service, dependency, framework, CI job or native popup.

Flat/vertical presentation, pinned ordering, existing configuration, utility
controls, ordinary click actions and application-wide hide/pin semantics remain
unchanged. Grouped-window dragging is not pinned reordering. The feature does
not create workspaces, move whole workspaces, follow moved windows, restore
minimized windows on drop, or drag between separate native dock surfaces.

The CLI aggregate branch `feat/fdm-914-cli-first` / PR #44 belongs to another
worker. Do not write to it, rebase this candidate onto it, or absorb unrelated
CLI/icon changes. Shared README changes must remain scoped. A later authorized
integration must retain CLI Settings removal and icon resolution while adapting
the drag proxy's artwork source to that branch's `DockAppIcon`; do not restore
obsolete Settings or replace its icon component with the old `IconImage`.

## Behavioral contract

### Exact source membership

At gesture activation, capture the exact represented toplevel objects and their
normalized addresses once. Deduplicate objects; do not reconstruct a group from
application IDs, a presentation lookup, or a later inventory snapshot. A grouped
icon captures its represented members only; an ungrouped icon captures one.

Revalidate captured object liveness, handle/address identity and sticky state
before committing. Closed objects are skipped, not replaced by another live
window at the same address or by a same-app window. All captured members closed
means cancellation. Missing/ambiguous handles, unsafe addresses or a sticky
surviving member reject the unsafe payload before the first side effect.

A known non-sticky window from **Other windows** may be a source when its live
handle/address is resolvable. Its source workspace is not guessed. Closed
launchers and sticky members are not draggable window sources.

### Live destinations and move semantics

A destination must be a present normal workspace card, using its canonical
identity and current live inventory. Accept positive numeric IDs including IDs
above 10 and supported named workspaces, including spaces and Unicode. The
compact display label `*` is not a workspace identity; a real workspace named
`*` is resolved as `name:*`.

Reject special/fallback sections, vanished workspaces, unsafe names, malformed
selectors, unknown monitor ownership, and cards outside current monitor scope.
Do not sanitize unsafe names into different destinations. Do not guess a
focused workspace or create one. In all-monitor mode, a remote workspace card
rendered inside the current native dock is valid; its workspace stays on its
own monitor.

The controller resolves the destination again at commit time. It submits one
addressed silent move for each visible surviving member that needs a change,
using the existing classic and Lua dispatch dialects. It never focuses or
follows the destination. Same-workspace members are no-ops.

Only the authoritative physical IPC workspace
`special:smartdock-minimized` proves that a member is SmartDock-minimized. A
saved origin or stale object-level workspace relationship is not sufficient.
A physically minimized member stays hidden: update its saved restore workspace
and destination monitor only, without a compositor move, focus or restore.
An explicit valid drop may establish a missing origin. A currently visible
member with a stale origin moves normally and clears that stale origin after
submission. Mixed groups apply these rules per captured member.

The controller's boolean reports a submitted move or origin-state change. It
is not a compositor acknowledgement, transaction, or guarantee that every
member moved atomically if live state changes during submission.

### Gesture ownership and cleanup

Use a dedicated left-button/no-modifier, two-axis `DragHandler`, with the normal
platform threshold and `target: null`. Keep it separate from the existing
one-axis pinned reorder handler. Below-threshold clicks keep their ordinary
behavior.

A scene-local coordinator owns source, captured members, final pointer,
hovered identity, proxy artwork/count and idempotent cleanup. It delegates
window operations to the existing controller. The proxy is a sibling of the
clipped card row, not a new native window. Dim the source while dragging.

Only an exclusive ungrab with a released event point may finish a drop.
`active=false` alone also occurs for cancellation and cannot commit. Keep
handler ownership latched through release delivery; the next-turn fallback
only cancels and clears the latch. Lost/stolen grabs, disabled handlers,
incompatible configuration/layout changes, source removal/reparenting,
screen/surface changes and destruction cancel without dispatch. Source clipping
during horizontal scrolling must not disable the live grab.

Always clear proxy, dimming, hover state, captured references, navigation timers
and the active session, including failure/exception paths. Duplicate finish or
cancel notifications must not dispatch twice or emit multiple end refreshes.
Keep `WlrKeyboardFocus.None`; do not add keyboard capture merely for dragging.

### Geometry, overflow and presentation lifetime

Use the release event's final scene position. Map scene coordinates through
the actual clipped viewport and each present card's current geometry. A visible
portion of a partially clipped card may accept a drop; whole-card containment
is not required. Both header and app body are targets. Gaps, utility controls,
Trash, navigation buttons, **Other windows**, clipped-out regions, and positions
outside this native dock are not targets. Do not commit remembered hover state.

During overflow, dwell over an actual previous/next navigation button for
250 ms, then scroll 12 logical pixels every 40 ms. Stop at the boundary, on
leaving the navigation rectangle, and on finish/cancel. Releasing over the
button is not a workspace activation or drop. Disable competing Flickable
interaction and active-card auto-reveal only while the window drag is active.
Retarget a stationary pointer whenever the viewport scrolls or live inventory
changes.

Freeze only imperative rendered item/card replacement while the drag owns a
source delegate. Keep window objects, destination inventory, monitor ownership
and validation live. Mark the presentation dirty on refresh requests; finish
or cancel schedules one existing zero-delay refresh and then normal active-card
reveal can resume. Do not freeze authoritative compositor state or introduce a
second scheduler/service. Preserve grouped geometry while fullscreen mode
changes during a session.

Keep auto-hide revealed for the active drag and suppress competing app actions,
menus, previews, tooltips, wheel cycling, hover magnification and attention
motion without clearing attention state. The original behavior resumes after
cleanup.

## Implementation tasks and ownership

### 1. Establish the source baseline and contracts

Read the live issue, parent, native plan, project conventions, current `main`,
`AGENTS.md`, `docs/DELIVERY.md` and overlapping PRs before editing. Use one
isolated feature branch and one Draft PR. Record the exact base; preserve
concurrent source/doc ownership. Establish failing behavior tests before
production changes and inspect the actual RED run rather than inferring it.

### 2. Extend the existing action authority

- `DockModel.js`: change only `moveWindowRequest` to accept safe normal numeric
  and named workspace targets, preserving addressed silent classic/Lua output.
- `DockWindowActions.qml`: capture exact members, validate identity/liveness,
  resolve live normal destinations and monitor ownership, and implement
  per-member visible moves versus minimized-origin updates.
- Preserve all unrelated settings, grouping, restore and focus behavior.

Production-method Node tests exercise this authority directly with small live
inventory adapters. Do not introduce duplicate request builders or a second
window controller merely for testing.

### 3. Add the scene-local session and wire pointer ownership

- `DockWorkspaceDrag.qml`: capture once, scene pointer/target resolution,
  feedback, release-time validation and idempotent finish/cancel/finally cleanup.
- `DockItem.qml`: separate handler, release latch, source artwork/dimming and
  input/popup suppression; preserve existing pinned reordering.
- `Dock.qml`: one coordinator per dock, real card hit testing, monitor scope,
  auto-hide hold and presentation freeze/one-refresh lifecycle.
- `DockWorkspaceGroup.qml`: transient destination highlight and header/tooltip
  suppression while retaining ordinary urgent/active styling.

Pure Qt tests instantiate the real coordinator. Production-method tests cover
the host hit-test/refresh functions and release callback. They are not evidence
that native compositor pointer delivery has been qualified.

### 4. Extend bounded workspace navigation

`DockWorkspaceLayout.qml` owns scene-to-viewport containment, navigation-button
rectangles, dwell/scroll/clamp behavior and viewport notifications. Reuse its
existing scroll offset and layout rather than introducing another viewport.

Pure Qt tests instantiate the real layout, cover partial cards and navigation
exclusion, dwell/start/leave/boundary/finish behavior, active-header reveal
suppression, and compose the real coordinator with the real layout to prove
stationary-pointer retargeting after scroll.

### 5. Verify and deliver the remote candidate

Run the repository's existing Headless CI on the exact candidate head. Keep
checks scoped to production behavior and existing structural contracts. Updated
structural guards must retain settings-refresh and urgent/active hierarchy
checks while accepting drag cancellation/highlight additions; do not bypass
behavior failures with weaker source-text assertions.

Focused commands (also included in the existing broad CI suite):

```bash
node tests/test_workspace_drag.mjs
node tests/test_grouped_actions.mjs
node tests/test_workspace_model.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
bash tests/check_visible_items_snapshot.sh
bash tests/check_workspace_visual_hierarchy.sh
git diff --check
```

Inspect all JavaScript suites, pure Qt tests, Python tests, structural guards,
shell syntax and diff checks. Review the final diff against this contract,
remove unrelated edits and verify the final exact-SHA run after the last file
change. Add README semantics and this repository plan copy. Record actual
results and any limitations, not only intended test commands.

The remote handoff must contain: base/head SHAs, source branch and Draft PR,
actual CI run/job links and results, AI review scope/findings/fixes, pending
local-only checks, exact checkout instructions, concurrency notes and next
issue. Mark FDM-889 Done and FDM-890 Ready only after this remote acceptance is
met. Keep the PR Draft, unmerged and undeployed; leave the parent open while
local qualification remains outstanding.

## FDM-890 — separate local Omarchy gate

This section is a handoff, **not work performed by FDM-889**. The local worker
must first read the live FDM-890 issue and accepted exact-head evidence, plus
current `AGENTS.md` and `docs/DELIVERY.md`. Use the canonical source checkout
`/home/admin/Projects/smart-omarchy-dock` or an isolated source worktree. Reuse
this branch and PR; do not patch an installed plugin or import the CLI branch.

Before checking out, inspect local changes and coordinate one writer. Fetch
the candidate and verify the checked-out SHA equals the accepted Linear/PR
head. If the branch advanced, inspect the delta and require fresh evidence for
that newer head; never silently qualify a different revision. Preserve and
restore settings, avoid simultaneous standalone/plugin instances, and follow
the repository's reversible local-run procedure.

### Required real-pointer/runtime matrix

1. Top and bottom grouped layouts: ordinary below-threshold click, horizontal
   and vertical threshold crossing, correct header/body drop, source feedback,
   no focus/follow, and same-workspace no-op. Check grouped and ungrouped exact
   member counts without pulling same-app windows from another card.
2. Mixed visible/minimized groups: visible addressed moves, hidden members stay
   minimized, restored members later use the destination workspace/monitor,
   stale origin handling, and missing-origin explicit destination behavior.
3. Existing empty, numeric-above-10, named/Unicode and remote-monitor cards;
   current-monitor restrictions, compact `*` identity, sticky rejection and
   resolvable **Other windows** sources. Never treat special/fallback sections
   as destinations.
4. Compact/full-length overflow: partial-card hit tests, source scrolled out of
   view, 250 ms navigation dwell, both boundaries, stationary-pointer retarget,
   auto-hide hold, gaps/navigation/Trash/outside release cancellation, stolen
   grab, closing captured windows, removed destinations, layout/settings
   changes and repeated drag/cleanup cycles.
5. Flat/vertical and pinned-order regressions; context menus, wheel actions,
   popup geometry, attention, utility controls, active-card reveal and normal
   live refresh after cleanup. Verify resize/surface lifetime regressions.

Use actual available hardware and name unavailable monitor/layout cases rather
than claiming them covered. Screenshots/logs should be tied to the tested head
and relevant cases; do not capture unrelated sensitive desktop content.

Run the local checks required by the current repository, including:

```bash
timeout 6s ./scripts/run --no-color
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  components/Dock.qml components/DockItem.qml \
  components/DockWindowActions.qml components/DockWorkspaceDrag.qml \
  components/DockWorkspaceGroup.qml components/DockWorkspaceLayout.qml
bash tests/runtime/check-workspace-resize.sh
```

The bounded launch timeout alone is not success: inspect startup/runtime logs,
record the actual Qt/Quickshell/Hyprland environment and demonstrate the matrix.
Only make scoped, demonstrated runtime fixes on this source branch. Push any
fix, rerun headless CI and record the new exact head before accepting it.
Restore settings and normal runtime ownership afterwards.

Local qualification is not authorization to merge or deploy. Any later release
must follow the separate live issue and `docs/DELIVERY.md` authorization. The
parent cannot be closed merely because the remote candidate exists.
