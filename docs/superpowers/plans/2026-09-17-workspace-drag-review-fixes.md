# Workspace Drag Review Fixes — Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to execute this plan sequentially, one task at a time. Do not delegate implementation. If blocked or repeating failed approaches, use the bounded Herdr/Astra consultation below. Steps use checkboxes for tracking.

**Goal:** Fix the eight findings from the workspace-monitor drag review without changing the dock's architecture or expanding the feature.

**Architecture:** Keep the existing host-owned `DockWorkspaceMonitorDrag`, shared `DockWindowActions`, stable presentation entries, and display-only projection. Correct gesture activation, source-grab lifetime, coordinate conversion, and cleanup in their current owners. Exercise production QML handlers with real Qt pointer events, then qualify the real dock in an isolated guest.

**Tech Stack:** Existing QtQuick/QtTest, Quickshell, QML/JavaScript, Python `unittest`, Node assertions, and named KVM development sessions. No new dependencies.

**Spec:** The eight review findings reproduced below are the complete fix scope. Read `AGENTS.md`, `docs/DELIVERY.md`, `docs/DEV_SESSIONS.md`, and `docs/WORKSPACE_DRAG_CONSOLIDATION.md` for host and delivery constraints. The existing `2026-09-17-workspace-drag-real-integration.md` is background, not another task list to restart.

## Global constraints

- Worktree: `/home/admin/Projects/smart-omarchy-dock/.worktrees/workspace-drag-consolidated`.
- Branch at planning time: `feat/workspace-drag-consolidated`.
- Reviewed head: `5ff09e85f6ab2e671e91b75f5a4a923321cf6a73`.
- Observed `origin/main`: `1a81fe650f686f1b8dfb10b25f5c0d1de6a4bab8`; merge base: `87c3c4f0836344769deaea99a48c25abfecc2e28`.
- `origin/main` includes the newer, unrelated desktop dev-switch change. Do not interpret its absence from this older branch as a deletion to implement, and do not absorb that work into these fixes.
- Preserve the pre-existing untracked `docs/superpowers/plans/2026-09-17-workspace-drag-real-integration.md` byte-for-byte. Do not stage, delete, rename, or rewrite it.
- This request authorizes creating this plan only. A later execution request authorizes the bounded fixes/tests described here; commits, pushes, PR publication, merging, and deployment remain excluded unless separately authorized.
- No second `DockWindowActions`, drag coordinator, settings writer, framework, package, configuration key, CLI command, or generic UI component.
- Do not change `DockHost.qml`, `DockWindowActions.qml`, the projection model, the compositor dispatcher, pin reordering, or launcher code to solve a local pointer/geometry problem.
- Do not edit installed plugin checkouts, `/usr/share/omarchy`, or host production settings. Use graphical authorization if a permitted operation needs sudo.
- Keep the existing zero-threshold grab mechanism and stable layer-shell keyboard mode. Gate semantic dragging separately using the platform distance. Do not change focus mode during a gesture.
- Only a released exclusive grab may dispatch. Hover, capture, scrolling, cancellation, and timeout never dispatch; rejection and timeout never retry.
- Headless Qt checks do not prove Hyprland focus, layer-shell grab survival, live image capture, auto-hide rendering, or hotplug correctness.
- Every new GUI window belongs on the coding agent's Hyprland workspace, silently and without initial focus. Do not move existing user windows or switch the user's active workspace.
- Keep the candidate Draft/unqualified until required native checks and independent review pass. Missing tools are an explicit gate, not a passing result.

## Scope and file ownership

| Finding | Current defect | Owning task |
| --- | --- | --- |
| F1 — High | `DockItem.qml:680`: 1px movement starts window dragging and suppresses an ordinary click | 1 |
| F2 — High | `DockWorkspaceGroup.qml:172`: source collapse/clipping disables the owned handler | 2 |
| F3 — Medium | `DockWorkspaceGroup.qml:187`: distance starts at the first move instead of the press | 1 |
| F4 — Medium | `Dock.qml:1164`: destination scrolling receives source-scene coordinates | 3 |
| F5 — Medium | `DockWorkspaceMonitorDrag.qml:376`: confirmation placeholder loses its size | 4 |
| F6 — Medium | `DockWorkspaceMonitorDrag.qml:263`: first reveal replaces unrelated frozen snapshots | 5 |
| F7 — Medium | `tests/test_workspace_drag.mjs:325`: source-string assertions do not test gesture/rendering contracts | 1–6 |
| F8 — Low | `DockWorkspaceGroup.qml:27`: every card is treated as the source while active | 2 |

Line numbers identify the reviewed version. Locate the named declaration after edits; do not apply edits by stale line number.

Allowed production files: `components/DockItem.qml`, `components/DockWorkspaceGroup.qml`, `components/Dock.qml`, and `components/DockWorkspaceMonitorDrag.qml`.

Allowed test files: create `tests/test_workspace_drag_input.py`; extend `tests/tst_workspacemonitordrag.qml`, `tests/tst_workspacelayout.qml`, `tests/tst_monitorsectionlayout.qml`, and `tests/test_workspace_drag.mjs` only where the task requires it. Reuse `DockAnimatedSlot`, `DockWorkspaceLayout`, `DockWorkspaceDrag`, and `DockWorkspaceMonitorDrag` in tests. No standalone test application or replacement preview implementation.

Allowed evidence documentation: append a clearly dated review-fix section to `docs/WORKSPACE_DRAG_CONSOLIDATION.md`. Keep large logs/screenshots outside Git. Do not rewrite historical results to make the current candidate appear qualified.

## Execution discipline and Astra escape hatch

Follow this loop: identify one failing behavior → add/run its regression → make the bounded edit → rerun that regression → inspect the diff → advance. Do not make fixes in several tasks at once. Record the current task and the last failing assertion in an external execution log before stopping or handing off.

**Stop changing code and consult Astra when any one condition holds:**

1. Two materially different fixes fail the same assertion.
2. Twenty minutes pass without new evidence explaining a failure.
3. You are about to undo/reapply the same edit for a second time.
4. The apparent solution requires leaving the allowed production files, changing layer-shell focus policy, replacing the grab mechanism, or adding a dependency.

Do not run the same unchanged test repeatedly. Do not suppress the assertion, increase arbitrary delays, skip the case, or remove the test to obtain green output.

### Ask Astra through Herdr, for instructions only

The user explicitly permits the executing agent to ask Astra for guidance when stuck. This is not permission for a second agent to edit the worktree.

- [ ] Read `/home/admin/.agents/skills/herdr/SKILL.md`. Verify `test "${HERDR_ENV:-}" = 1`. If false, do not control Herdr from outside its session; report that the consultation route is unavailable and retain the precise blocker.
- [ ] Discover the current CLI and layout, without focusing anything:

```bash
herdr --help
herdr agent
herdr pane
herdr agent list
herdr pane layout --current
```

- [ ] Use an existing idle Astra consultant only if its task ownership and model are confirmed. Otherwise create one sibling pane with `--no-focus` in the **current Herdr session**. For the first child, use the following command and read `.result.pane.pane_id` from its JSON response:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

If a child region already exists to the right, split an existing child pane downward instead; select its exact ID from the layout response. Never split below the owner pane. Set `astra_pane` to the returned new pane ID, not a guessed ID. Check that `workspace-drag-astra` is unused before starting it; if that name belongs to unrelated work, select a unique name and use it consistently.

```bash
herdr agent start workspace-drag-astra --kind codex --pane "$astra_pane" -- \
  --model gpt-6-astra -c model_reasoning_effort=high
herdr agent list
```

- [ ] Write `astra-question.md` in the external evidence directory established in Task 0. Include these six concrete facts: task/finding ID; expected versus observed result; exact command and failure output; relevant file/function names; the two attempted approaches and their diffs; current head plus dirty-file list. End with this instruction:

> You are the read-only Astra consultant for the workspace-drag review-fix plan. Do not edit files, create commits, launch a dock, dispatch compositor actions, or delegate work. Identify the root cause, give the smallest next change within the plan's scope, and name one test that will distinguish your explanation from the failed approaches. Read the plan and the relevant current source before answering. If the scope must change, explain why instead of implementing it.

- [ ] Submit once, then wait/read; do not resend because a wait times out:

```bash
herdr agent prompt workspace-drag-astra "$(cat "$dock_evidence/astra-question.md")"
herdr agent wait workspace-drag-astra --timeout 60000
herdr agent read workspace-drag-astra --source recent-unwrapped --lines 160
```

Continue bounded waits if still working, with user-facing progress updates. If blocked, inspect the state and response; do not answer an approval dialog blindly. Read all relevant output if truncated. Apply only a scoped, testable recommendation. Record Astra's advice and whether the distinguishing test supported it. If it does not, send the new evidence once rather than silently cycling.

- [ ] Once advice is understood and no follow-up is needed, verify the consultant is idle/done, close **only** the created pane, and verify cleanup. Never close an unrelated/reused user's pane.

```bash
herdr agent get workspace-drag-astra
herdr pane close "$astra_pane"
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
```

## Task 0 — Establish the exact starting state

**Files:** Read the constraints and named owners; no production edits.

- [ ] Run:

```bash
pwd
git status --short --branch
git rev-parse HEAD origin/main
git log --oneline HEAD..origin/main
git diff --stat
sha256sum docs/superpowers/plans/2026-09-17-workspace-drag-real-integration.md
```

Expected branch/head are listed above. Expected untracked files are the existing integration plan and this plan. If work by another actor exists, record it and do not overwrite it. If the reviewed code changed, inspect that delta before applying this plan; ask Astra if the fix assumptions no longer hold.

- [ ] Create an external evidence directory and save the head/base, initial status, old plan checksum, Qt version, and task progress there:

```bash
dock_evidence="${XDG_STATE_HOME:-$HOME/.local/state}/smartdock/workspace-drag-review-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$dock_evidence"
git rev-parse HEAD origin/main > "$dock_evidence/revisions.txt"
git status --short --branch > "$dock_evidence/initial-status.txt"
sha256sum docs/superpowers/plans/2026-09-17-workspace-drag-real-integration.md > "$dock_evidence/preserved-plan.sha256"
```

- [ ] Read both pointer handlers, all callers of `begin`, `finish`, `clearPointerState`, `clearPending`, and `refreshTargetGeometry`, plus the presentation slot and layout bindings. Use:

```bash
rg -n 'workspaceGrabChanged|workspaceMonitorGrabChanged|workspaceGestureOwned|workspaceMonitorGesture|clearPointerState|clearPending|refreshTargetGeometry|ghostSize|dragScenePosition' components tests
```

- [ ] Run the focused baseline and retain results:

```bash
node tests/test_workspace_drag.mjs
node tests/test_workspace_monitor_sections.mjs
QT_QPA_PLATFORM=offscreen QML_DISABLE_DISK_CACHE=1 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_workspacemonitordrag.qml -import components
QT_QPA_PLATFORM=offscreen QML_DISABLE_DISK_CACHE=1 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_workspacelayout.qml -import components
```

These passed during review. A baseline failure is investigated before editing, not automatically attributed to the current task.

**Exit condition:** Known head, preserved unrelated files, readable owners, recorded baseline.

## Task 1 — Preserve clicks and start dragging from the actual press distance

**Fixes:** F1, F3; establishes behavioral coverage for F7.

**Files:** Modify `components/DockItem.qml`, `components/DockWorkspaceGroup.qml`, and relevant structural assertions in `tests/test_workspace_drag.mjs`. Create `tests/test_workspace_drag_input.py`.

**Interfaces:** Existing `DockWorkspaceDrag.begin(source, members, scenePoint, icon)` and `DockWorkspaceMonitorDrag.begin(dock, workspace, label, count, monitor, scenePoint)` remain unchanged. Use native `DragHandler.centroid.scenePressPosition`; it is present in installed Qt metadata. The semantic drag threshold is `Application.styleHints.startDragDistance`, not a new numeric constant.

### 1A. Make the current failures executable first

- [ ] Reuse the test-generation pattern in `tests/test_browser_activity_preview.py`: read production QML, extract selected declarations unchanged into temporary QtQuick components, write a temporary `tst_*.qml`, and run the installed `qmltestrunner` with `QT_QPA_PLATFORM=offscreen`. Keep this new harness in one Python module; do not modify the browser-preview test.
- [ ] Use indentation-bounded extraction, failing loudly when the expected block is absent or ambiguous. This is extraction for execution, not a regex assertion that proves behavior. A local helper may follow this shape:

```python
def block(source, declaration, indent):
    prefix = " " * indent
    pattern = ("^" + re.escape(prefix + declaration)
               + r"[^\n]*\n.*?^" + re.escape(prefix) + r"\}")
    matches = re.findall(pattern, source, re.MULTILINE | re.DOTALL)
    if len(matches) != 1:
        raise AssertionError(f"Expected one production block: {declaration}")
    return matches[0]
```

Select handlers by their immediately following ID (`workspaceDragHandler` or `workspaceMonitorDragHandler`) so pin reordering cannot be extracted accidentally. Preserve the complete handler, including `onGrabChanged`, cancellation, enabled bindings, and cleanup timer. Include any new local gesture helper by name once it exists; the pre-fix harness must still compile when that helper is absent.

- [ ] Generate an icon surface and a header surface with these boundaries:

| Surface | Execute from production | Stub only |
| --- | --- | --- |
| Icon | gesture-owned/input-suppressed bindings, left-click `TapHandler`, workspace `DragHandler`, release timer, `workspaceGrabChanged`, `cancelWorkspaceDrag`, `dispatchPointerAction`, `dispatchApplicationAction`, and the new local helper | artwork URL; popup methods; app/window service methods returning deterministic values and counting activation/move calls |
| Header | gesture flags, source/input-suppressed bindings, header `TapHandler`, monitor `DragHandler`, release timer, grab/cancel methods, and the new local helper | label/count/style values, tooltip object with no-op reanchor, coordinator service spy recording begin/update/finish/cancel |

Use real QtQuick `Item`s with at least 240×80 input area and the same `root`/`header` IDs as production. Set icon `runningCount=1`, `sticky=false`, `presentationActive=true`, `workspaceDragEnabled=true`, and ordinary left action to `focus-or-launch`. Import the real `DockModel.js` for action resolution. Spy on the resulting window action, **not just `TapHandler.tapped`**: production intentionally suppresses actions after a real drag.

For header tests, increment `activations` in the stub root's `activated` signal handler. Coordinator spies must expose `active`, `awaitingConfirmation`, `sourceDock`, `sourceWorkspace`, and `captureReady`; `begin()` counts calls and establishes identity, `finish()` counts calls and clears active state, and `cancel()` clears active state without counting a move. Keep gesture-owned flags controlled by production code and its real timer.

- [ ] Add QtTest cases with fresh surfaces per case. This is the minimum event sequence for the two reviewed regressions:

```qml
function test_iconJitterIsClick() {
  mousePress(icon, 30, 30, Qt.LeftButton)
  mouseMove(icon, 31, 30, 20)
  mouseRelease(icon, 31, 30, Qt.LeftButton)
  compare(icon.beginCalls, 0)
  compare(icon.activationCalls, 1)
}

function test_headerFirstMoveCrossesThreshold() {
  var delta = Application.styleHints.startDragDistance + 7
  mousePress(header, 30, 30, Qt.LeftButton)
  mouseMove(header, 30 + delta, 30, 20)
  compare(header.beginCalls, 1)
  mouseRelease(header, 30 + delta, 30, Qt.LeftButton)
  compare(header.finishCalls, 1)
  compare(header.activations, 0)
}
```

Expose counters on the surface handles used above. Also cover both surfaces with: zero movement; movement strictly below the platform threshold; exactly the threshold; two movements crossing it; continued movement after start; a second click after release cleanup; and cancellation without finish. Use the runtime threshold to choose coordinates, never hardcode the observed local value of 8px. For a true drag, assert one begin and zero click actions. Use `tryCompare` for timer cleanup, not long arbitrary sleeps.

- [ ] Run `python3 -B -m unittest discover -s tests -p 'test_workspace_drag_input.py'`. Require assertion failures showing the icon action is lost and the header begin count is zero. Import/type/reference errors are harness failures; fix them before touching production behavior.

### 1B. Apply the bounded gesture correction

- [ ] In each component, add one small local gesture-update function. It accepts `(scenePoint, pressPoint)`, checks the platform distance while the gesture is not owned, marks ownership only after crossing that distance, invokes the existing begin path once, and forwards later positions only for that source. Do not add a shared gesture class.

Use this exact gate in both helpers:

```qml
var dx = scenePoint.x - pressPoint.x
var dy = scenePoint.y - pressPoint.y
if (Math.sqrt(dx * dx + dy * dy) < Application.styleHints.startDragDistance)
  return
```

For the icon helper, name it `updateWorkspaceGesture(scenePoint, pressPoint)`. Before the existing popup dismissal and `workspaceDrag.begin(...)`, set `workspaceGestureOwned = true`. Subsequent calls update the existing coordinator only when `workspaceDrag.sourceItem === root`. A rejected begin must not repeatedly retry on every move; ownership stays until release cleanup and no click action fires for the rejected drag attempt.

For the header helper, name it `updateWorkspaceMonitorGesture(scenePoint, pressPoint)`. Set `workspaceMonitorGestureOwned = true` at threshold crossing, then assign `workspaceMonitorGestureStarted` from the existing coordinator's boolean `begin(...)` return. Forward later motion only when that flag is true and both source dock/workspace match. Retain the successful-begin focus call.

- [ ] Call each helper in **both** the `active=true` branch and `onActiveTranslationChanged`, passing `centroid.scenePosition` and `centroid.scenePressPosition`. This handles a single initial movement already beyond threshold. Keep `dragThreshold: 0`, `target: null`, grab permissions, and the existing exclusive-release finish routing.

```qml
// Icon handler; the header handler calls its corresponding local helper.
onActiveTranslationChanged: if (active)
  root.updateWorkspaceGesture(centroid.scenePosition, centroid.scenePressPosition)
```

Do not set gesture ownership just because `DragHandler.active` became true. Remove the header's obsolete `workspaceMonitorPressPoint` property and assignments; do not maintain a second copy of Qt's press position. Keep release cleanup responsible for clearing gesture flags even when no semantic drag began.

- [ ] Guard the header tap action at dispatch time:

```qml
onTapped: if (!root.headerInputSuppressed) root.activated()
```

Reason: Qt can still deliver a release to a previously pressed tap handler after its enabled binding changes during the same gesture. Keep ordinary clicks working; do not broadly disable input before the platform threshold.

- [ ] Update only the structural checks whose literal expectations changed. Keep ownership/dispatch/architecture guards. Behavioral tests now own the claims about clicks and threshold crossing.
- [ ] Run the new Python test plus `node tests/test_workspace_drag.mjs`; inspect `git diff --check` and the two production diffs.

**Exit condition:** Both reviewed failures are red before the edit and green after it; true drags begin once and never activate the source by click; small motion still activates normally.

## Task 2 — Retain the clipped source grab and restrict source styling

**Fixes:** F2 and F8.

**Files:** `components/DockWorkspaceGroup.qml`, the new input test, and `tests/tst_monitorsectionlayout.qml` only if needed for its existing slot geometry fixture.

**Interfaces:** Keep `workspaceMonitorDragSource` as the source-identity predicate; preserve existing stable source entry/token and `DockAnimatedSlot` occupancy behavior.

- [ ] Extend the generated header fixture with the real `DockAnimatedSlot` and `DockWorkspaceLayout`, plus production viewport visibility calculation and handler enabled/cancellation bindings. Create a 240px-wide first card with a 42px header in a 300px viewport, initially fully visible. Start its gesture, then set the source slot's `present=false` to reproduce projection collapse. Confirm the header becomes clipped while the same header object remains alive.
- [ ] Assert that the coordinator stays active and cancellation count remains zero after collapse settles; release must still reach finish once. Run with animations disabled and enabled (wait for occupancy to settle using `tryCompare`). Also scroll the source header out of view during a gesture and assert grab survival. Before a gesture, an already clipped header must remain unable to start one.
- [ ] Add a second non-source header and a header on another dock. With a shared active/capture-ready coordinator, assert the real source predicate is true only for the matching dock **and** workspace. Check the production opacity binding yields `0.55` for source and `1` for others; before capture all are `1`. Repeat predicate checks while awaiting confirmation.
- [ ] Fix the source predicate by applying both identity tests to both lifecycle states:

```qml
readonly property bool workspaceMonitorDragSource: workspaceMonitorDrag
  && (workspaceMonitorDrag.active || workspaceMonitorDrag.awaitingConfirmation)
  && workspaceMonitorDrag.sourceDock === workspaceMonitorDragDock
  && workspaceMonitorDrag.sourceWorkspace === workspaceIdentity
```

Search every use of `workspaceMonitorDragSourceActive`. If it is still declaration-only, remove that duplicate unused predicate; otherwise bind it to the corrected predicate instead of maintaining two expressions.

- [ ] Change only the handler's visibility requirement so an existing grab survives clipping:

```qml
&& (active || root.workspaceMonitorGestureOwned || root.presentationVisible)
&& !root.windowDragActive
```

Keep switchability, workspace/controller availability, source lifecycle cancellation, and the existing exclusion of another monitor gesture. Do not set the entire card permanently visible/enabled, disable viewport clipping, give it fake dimensions, remove source collapse, or reparent/recreate its delegate.

- [ ] Run the input test and existing monitor-section/layout tests. Verify the source object/token is unchanged across hover/cancel and unrelated cards remain normally styled.

**Exit condition:** A collapsed/clipped source retains its grab through release; idle clipped headers cannot start a drag; only the actual source dims and uses its source cursor state.

## Task 3 — Convert the pointer into each dock's scene before scrolling

**Fixes:** F4.

**Files:** `components/Dock.qml`, `tests/test_workspace_drag_input.py`, and `tests/tst_workspacelayout.qml`.

**Interfaces:** `pointerVirtual` is desktop-logical space. `DockWorkspaceLayout.dragScenePosition` is local to that layout's containing window. Do not change the coordinator's source-local `updatePointer()` API.

- [ ] Add a binding-execution case to the Python-generated Qt fixture using the actual `dragScenePosition` expression extracted from `Dock.qml`. Supply source-scene and virtual coordinates independently so the test cannot pass by conflating them. For example:

```text
destination sceneOrigin = (1920, -120)
desired destination-local pointer = (280, 110)
coordinator pointerVirtual = (2200, -10)
coordinator pointerScene = (3736, -754)  # deliberately different source scene
expected destination dragScenePosition = (280, 110)
```

Also cover a negative destination origin and the window-drag branch, which must keep using `workspaceDrag.pointerScene` unchanged.

- [ ] Extend the real layout dwell test with `monitorDragActive=true`: place the converted point over `nextCards`, assert no immediate scroll, then positive scroll after dwell; leave the button and verify scrolling stops; end the drag and verify timers stop. Derive the button center using `mapToItem(null, ...)`, then add the destination origin to obtain virtual coordinates. Use the production conversion expression, not a handwritten duplicate in the test.
- [ ] Replace only the monitor-drag arm of the production binding:

```qml
dragScenePosition: root.workspaceDragActive ? workspaceDrag.pointerScene
  : root.workspaceMonitorDragActive ? Qt.point(
      root.workspaceMonitorDrag.pointerVirtual.x - root.sceneOrigin.x,
      root.workspaceMonitorDrag.pointerVirtual.y - root.sceneOrigin.y)
  : Qt.point(0, 0)
```

Do not replace the `updatePointer(root.workspaceMonitorDrag.pointerScene)` calls after scroll; that API still expects source-scene coordinates.

- [ ] Run the new input test, `tests/tst_workspacelayout.qml`, and `node tests/test_workspace_drag.mjs`.

**Exit condition:** Navigation receives destination-local coordinates for positive and negative monitor origins, dwell scrolling works there, and existing window dragging is unchanged.

## Task 4 — Keep placeholder dimensions through confirmation

**Fixes:** F5.

**Files:** `components/DockWorkspaceMonitorDrag.qml`, `tests/tst_workspacemonitordrag.qml`, and the new generated Qt fixture for the production placeholder dimension bindings.

**Interfaces:** Keep `ghostSize` as the captured size; no new persisted state or second size cache. Image/pointer state may end at release, but captured dimensions live until the pending projection ends.

- [ ] Extend the existing successful-dispatch test immediately after `finish(...)` with these assertions (the existing fixture card is 120×50):

```qml
compare(scene.drag.awaitingConfirmation, true)
compare(scene.drag.active, false)
compare(scene.drag.ghostUrl, "")
compare(scene.drag.ghostSize, Qt.size(120, 50))
```

- [ ] Execute the actual placeholder `naturalWidth`/`naturalHeight` bindings from `Dock.qml` in a real `DockAnimatedSlot` in the generated fixture. Assert width/height remain 120×50 while awaiting confirmation. This must catch a change in either the coordinator or consumer binding.
- [ ] Extend cleanup assertions: dimensions return to zero after confirmation, timeout, explicit cancellation, dispatch rejection/exception, source removal, destination removal, and failed begin. Exercise a second drag with a different card size and verify it uses that new size. Preserve stale-callback checks: an old capture callback must not repopulate dimensions/image or dispatch after cancellation/new generation.
- [ ] Remove the `ghostSize = Qt.size(0, 0)` assignment from `clearPointerState()`. Keep its image, capture-generation, reveal, pointer, and highlight cleanup.
- [ ] Add that dimension reset to `clearPending()`. Make `resetBeginFailure()` and `endSession()` both call `clearPointerState()` and `clearPending()` so all terminal paths clear dimensions. Retain `endSession()`'s reentrancy guard and single `ended()` emission. Replace duplicate metadata resets in those two functions with the existing `clearPending()` call; do not introduce another cleanup abstraction.
- [ ] Leave successful `finish()` using `clearPointerState()` only while pending. `captureGhost()` must still initialize a fresh size before capture. Do not retain the image URL simply to preserve dimensions.
- [ ] Run the coordinator suite and input/consumer fixture. Verify one dispatch, no retries, and idempotent cleanup on every covered path.

**Exit condition:** A successful release retains equal-size placeholder geometry until authoritative confirmation or cancellation/timeout, and every terminal path clears it.

## Task 5 — Refresh only the revealed or scrolled dock's snapshot

**Fixes:** F6.

**Files:** `components/DockWorkspaceMonitorDrag.qml`, `tests/tst_workspacemonitordrag.qml`.

**Interfaces:** `refreshTargetGeometry(dock)` updates that dock only. Calling it without a dock may retain its existing full-resnapshot behavior. Pointer motion must not resnapshot geometry.

- [ ] Add `test_revealAddsDestinationWithoutRefreshingSource` using existing fake docks. At begin, source is shown with section bounds A; destination is hidden, so no destination snapshot exists. After capture, change the source's live section bounds to B. Reveal the destination and give it visible bounds C, then call `refreshTargetGeometry(destination)`.
- [ ] Assert source snapshot and source fallback remain A, the new destination snapshot is C, both identities occur once, and target lookup still follows A. Repeat the destination refresh with new bounds D and assert no duplicate snapshot. Use different source bounds, such as A=(0,0,100,40) and B=(60,0,40,40), so a global rebuild cannot accidentally pass.
- [ ] Add the complementary targeted-scroll case: refreshing an already registered destination replaces only its entry, retaining the source and any third dock's snapshots. Keep existing rejected-section/fallback and clipped-bound tests.
- [ ] Restructure the targeted branch into one entry update and one flatten operation:

```qml
var merged = geometrySnapshots.slice()
var index = -1
for (var i = 0; i < merged.length; ++i) {
  if (merged[i].dock === dock) { index = i; break }
}
var snapshot = {
  dock: dock,
  sections: selected,
  fallback: geometryAvailable(dock)
    ? (typeof dock.workspaceMonitorViewportRect === "function"
      ? dock.workspaceMonitorViewportRect() : dock.dropRect)
    : Qt.rect(0, 0, 0, 0)
}
if (index < 0) merged.push(snapshot)
else merged[index] = snapshot
geometrySnapshots = merged
sectionHits = merged.reduce(function(result, entry) {
  return result.concat(entry.sections)
}, [])
return
```

Keep the existing `selected` construction and outer error handling. The no-dock branch can call `snapshotSectionHits()`. Do not move refresh into `updatePointer()`, shorten the reveal timer, or globally snapshot to compensate for projection movement.

- [ ] Run the coordinator suite and existing workspace JavaScript tests. Verify the reveal timer still stops/clears during cancellation and removal.

**Exit condition:** Adding a newly revealed destination cannot alter any other dock's frozen rectangles; deliberate scrolling updates only the selected dock.

## Task 6 — Close the validation gap and prepare a precise handoff

**Fixes:** F7; acceptance for all findings.

**Files:** Tests already named; append evidence to `docs/WORKSPACE_DRAG_CONSOLIDATION.md`. Do not change QEMU placement or seeding code: the review found no actionable defect there.

### 6A. Review the test boundary and run the complete automated gate

- [ ] Confirm the new test executes production handlers, bindings, release timers, and guarded action dispatch. There must be no handwritten duplicate of the changed threshold/ownership/coordinate logic in the harness. A mocked service counter is allowed; a mocked `DragHandler` is not.
- [ ] Confirm every F1–F8 row has an actual behavioral assertion. Source regexes may remain for architecture but are not the acceptance evidence for input, geometry, or lifetime.
- [ ] Run the repository's headless gate, preserving each command's real exit status in the evidence. Do not pipe through `tee` without `pipefail`:

```bash
for script in install.sh uninstall.sh scripts/smartdock scripts/run tests/check_*.sh; do
  bash -n "$script" || exit 1
done
for script in tests/check_*.sh; do bash "$script" || exit 1; done
for script in tests/test_*.mjs; do node "$script" || exit 1; done
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -B -m unittest discover -s provider/browser-profiles/tests -p 'test_*.py'
QT_QPA_PLATFORM=offscreen QML_DISABLE_DISK_CACHE=1 /usr/lib/qt6/bin/qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml components/DockWorkspaceGroup.qml \
  components/DockWorkspaceLayout.qml components/DockWorkspaceMonitorDrag.qml shell.qml
git diff --check
```

Run the Python commands independently so an inherited failure does not hide the new focused result. Existing browser-preview/resize failures are documented historical observations, not blanket exemptions: record exact output and compare against the relevant baseline before classifying them. Do not fix unrelated failures in this plan. A new failure in an affected surface blocks acceptance.

### 6B. Qualify the real dock in a fresh named guest

- [ ] Read the current `docs/DEV_SESSIONS.md` before launch. Resolve and record the **coding agent's** Hyprland workspace; do not assume it equals the currently focused workspace. Set `dock_workspace` only to that verified identifier. If ownership cannot be resolved, consult Astra before opening a window.
- [ ] In a dedicated supervisor terminal/pane, start one fresh standalone guest. Keep that process supervised; do not reuse an old guest name:

```bash
unset XDG_STATE_HOME
dock_session="workspace-drag-fixes-$(date +%Y%m%dT%H%M%S)"
./scripts/dev-session start "$dock_session" \
  --source "$PWD" \
  --base-image /home/admin/.local/state/smartdock/dev-sessions/_kvm-feasibility/images/Arch-Linux-x86_64-cloudimg.qcow2 \
  --mode standalone --workspace "$dock_workspace"
```

Record the exact `dock_session` value for the control terminal. `start` stays running; do not wait for it to exit before using the session. Wait for its ready record/`guest_setup_complete`, then control it from the other terminal.

- [ ] Verify the two recorded QEMU addresses have the two expected exact titles and are on `dock_workspace`, using a bounded `hyprctl clients -j` read and the session record. Verify host focus/workspace were not changed by launch. Keep input/capture in the guest, not on the host production dock.
- [ ] For every source edit after launch, run the following cycle before collecting new evidence:

```bash
./scripts/dev-session sync "$dock_session"
./scripts/dev-session dock "$dock_session"
./scripts/dev-session dock "$dock_session" -- status --json
./scripts/dev-session capture "$dock_session"
```

- [ ] Perform the following matrix on the **real dock**, never the archived preview. Record before/after workspace owner and dispatch count where observable, plus frames demonstrating the source/placeholder. Use actual press/move/release input; directly calling `begin()` is not native pointer qualification.

| Case | Exact action | Required result |
| --- | --- | --- |
| Click preservation | Click a running icon and workspace header with zero movement, then small movement below the platform threshold | One normal activation each; no drag or workspace move |
| Fast activation | Press header, make one movement exceeding threshold, release over a valid foreign monitor section | Ghost starts from the real press-relative gesture; one move on release; no source click |
| Stable source | Drag a wide first source card to a foreign section and dwell until its source slot fully collapses; repeat after scrolling its header out of view | Same gesture survives; source delegate is not destroyed/recreated; release still works |
| Source styling | Hold a captured drag while other cards are visible on both docks | Only matching source dims; other cards retain normal styling |
| Cross-dock scroll | Drag to the other monitor's overflow navigation button, dwell, then leave it | Destination scrolls after dwell; stops on leaving; source does not scroll spuriously |
| Current/all scopes | Repeat a valid move in `current-monitor` and `all` workspace monitor scopes, including same-dock foreign section | Correct owner is targeted and only one compositor move occurs |
| Hidden destination | Begin with destination auto-hidden, enter reveal edge, wait for reveal, then target it | Destination becomes targetable after settling; other frozen targets do not jump |
| Settlement | Release valid target; inspect until compositor owner changes | Placeholder stays equal-size during pending interval; projection clears after confirmation |
| Rejection/cancel | Escape during drag; release outside; try same-owner/pinned-ineligible target | No move; no ghost/highlight/reveal leak; next click and next drag work |
| Removal | Remove the selected destination output in the isolated guest during active drag; repeat pending removal in deterministic Qt tests | Session clears without duplicate dispatch or stale source state |
| Capture | Inspect the ghost against the source, then cancel and start another drag | Full-size undimmed capture, correct source identity, no stale image from previous generation |

Change guest configuration only through `dev-session dock NAME -- ...`, after status/schema/get discovery per `docs/AGENT_CONFIGURATION.md`. Use captured/effective values and restore touched keys. Do not change host settings for this matrix. Do not introduce a production delay or rejected-dispatch switch to make pending states easier to observe; deterministic Qt tests own exact timeout/exception timing.

- [ ] If the available computer/input tools cannot target the guest safely, take the Astra escape hatch. Do not write a new input-injection system or claim screenshots prove gestures. Record the missing native cases explicitly and stop acceptance at that gate.
- [ ] Run standalone startup smoke and the workspace-resize harness only in the named guest's isolated display/config context, with its existing dock stopped before starting another test host. Retain `Configuration Loaded`, startup exit status (124 is expected for a successful six-second timeout smoke), and the resize harness's full output/exit status. Restart the normal guest dock afterwards if needed for remaining cases. Never run the source smoke on the production display.
- [ ] Perform two sync/restart cycles. Verify the record retains `guest_seeded=true`, `evidence/guest-seed.json` is unchanged, and no additional seed clients appear. This is regression validation, not permission to modify `scripts/dev_session.py` or `guest-control.sh`.
- [ ] Stop the guest with `./scripts/dev-session stop "$dock_session"`. Confirm only its exact QEMU addresses disappear and host production settings remain unchanged.
- [ ] Full Omarchy two-monitor qualification remains a separate requirement. A stripped plugin guest is supplemental and cannot satisfy it. If the full environment is unavailable, label the candidate unqualified/Draft and list that specific missing gate.

### 6C. Final self-review and handoff

- [ ] Inspect `git diff --stat`, the complete production diff, and `git diff --check`. Check that only the allowed files changed and that no test merely restates the implementation.
- [ ] Verify the preserved integration-plan checksum using `sha256sum -c "$dock_evidence/preserved-plan.sha256"`.
- [ ] Record head/base, dirty diff state, per-finding test names, actual command results, guest name/evidence paths, and unresolved native/baseline gates in the dated evidence section. Evidence for uncommitted changes must explicitly say **working-tree candidate**, include `git diff --binary HEAD` and a SHA-256 of that saved patch outside Git, and never be described as exact-commit acceptance. Git diff excludes untracked files: also save the new input test and this plan in the evidence directory with their relative paths and SHA-256 values. Include all newly created candidate files in that manifest; exclude the preserved unrelated integration plan from the candidate patch.
- [ ] Request independent read-only review through the authorized review workflow after implementation and validation. Provide this plan, the full current diff, and the evidence index. Address only actionable in-scope findings; any further edit invalidates the affected acceptance evidence.
- [ ] Hand off the diff and evidence. If commits/delivery are subsequently authorized, record the resulting exact head/base and rerun required checks on that candidate according to `docs/DELIVERY.md`. Do not reuse the planning head's evidence after rebasing, committing, or modifying code.

**Done means:** F1–F8 have reproducible tests and scoped fixes; all affected automated checks pass; required native pointer/geometry checks are evidenced; independent review has no unresolved actionable findings; the named guest/consultant resources are stopped; and the original untracked plan and host deployment/settings remain untouched. If a native gate is unavailable, report “fixes implemented; native qualification pending,” not “complete.”
