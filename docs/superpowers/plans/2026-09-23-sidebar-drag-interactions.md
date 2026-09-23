# Sidebar Drag Interactions — Implementation Plan

> **Revision R1 — 2026-09-23, incorporating the five plan-review findings.** This document is now the complete canonical execution plan for [FDM-993](<https://linear.app/fdamaso/issue/FDM-993/plan-smartdock-sidebar-drag-interactions-and-feedback>). It supersedes the original attachment titled “Sidebar Drag Interactions — exact implementation plan,” which remains historical evidence, not execution instructions. Before implementation, synchronize this revision into `docs/superpowers/plans/2026-09-23-sidebar-drag-interactions.md` on the validated prerequisite branch; this planning update does not claim that the developer's local working-tree file has been changed.

> **For agentic workers:** Execute Tasks 1–6 in order. Use the Superpowers execution workflow available to your environment, with failing regression tests before behavior changes and a review gate at each task checkpoint. This plan depends on Task 1 of `docs/superpowers/plans/2026-09-23-sidebar-layout-fixes.md` (flat workspace groups with 4 px inner padding). Start the drag branch from that task's exact validated head; retarget and revalidate after it merges per `docs/DELIVERY.md`.

**Goal:** Implement the drag storyboard from the [SmartDock Sidebar Redesign canvas](<https://claude.ai/artifact/7HR4yc6DgWE4XEc3fMfefv>), frames W1–W7 and G1, so the user knows what they are dragging, where it will land, and whether the result was confirmed.

**Architecture:** Extend `DockSidebarController.beginRowDrag / dragDestination / updateRowDrag / finishRowDrag`, `DockSidebarViewport.dropKey()`, and `DockSidebarInteractionModel.hitTarget`. All compositor moves remain in the single `DockWindowActions` owned by `DockHost.qml`. Separate gesture state from bounded post-dispatch confirmation and presentation state; no second controller, drag proxy window, process, or settings writer.

**Tech stack:** Existing Quickshell / Qt Quick / QML and JavaScript helpers, Hyprland classic and Lua dispatch paths, Node fixtures, Qt Quick tests, and isolated KVM qualification.

**Evidence base:** The original plan recorded a feasibility pass at `5a619f4` and a source recheck at `8796991`. The subsequent review inspected the controller, viewport, shared actions and fixtures at `879699196cfdc73ab20d8cfe7bd44871ba57e8cc`. File/line references are approximate; re-check after the layout dependency lands. The linked canvas and unpublished layout-prerequisite file were not visually/source-qualified by that review; retain their existing handoff gates.

## Global constraints and decisions already made

* Preserve the host-owned action controller, exact captured window objects and addresses, window/workspace pins, minimized origins, named workspaces, projection freeze during the gesture, release revalidation, topology cancellation, click suppression, and native pointer-grab completion.
* Workspace-level targets highlight the whole workspace group with **fill only, no outline**, so the badge never touches a border.
* The “New workspace” slot appears once on **every** monitor when a window drag starts. It is not per-hovered-monitor; do not move targets under the pointer as hover changes.
* The ghost is a flat pill with no rotation, clipped to the sidebar; in the collapsed rail it shrinks to the icon only. The slot displays a dashed “+”, never a predicted workspace number.
* A workspace-drag placeholder sits in its **sorted** position using `WorkspaceModel.workspaceCompare` (numbers ascending, named after).
* Window drop on a monitor header (W3) is in scope; the whole monitor card highlights. It must never move a window to a workspace currently owned by a different monitor or relocate an existing workspace to repair an inconsistent header reference.
* Dispatch acceptance is not compositor confirmation. A timeout means **unconfirmed**, not failure or rollback. No compensating move is authorized by feedback.
* Preserve PR-only delivery, exact base/head evidence, no direct main merge/deployment, and no installed-plugin edits. Physical desktop preview requires an explicit user request; autonomous qualification uses a fresh named KVM guest.

## Open decision before Task 4 lands

When a window is already on this monitor but on a different workspace, should dropping it on the header move it to the monitor's active workspace? Proposed default: **yes**, matching Ctrl+click. Keep this as one guarded branch, record the owner's decision before Task 4 lands, and do not treat this review update as confirmation of that product decision.

## Branch and execution handoff

`feat/sidebar-drag-feedback`, stacked on the exact validated flat-hierarchy head. Tasks 1–3 change feedback/hit geometry without changing action destination policy; Task 4 changes header-drop behavior; Task 5 adds post-dispatch presentation. If review requests a split, Task 4 may use `feat/sidebar-monitor-header-drop`, with Task 5 stacked after it. Record exact parent/head SHAs for every PR and follow retarget/rebuild rules after the prerequisite merges.

[Source slice: FDM-994](<https://linear.app/fdamaso/issue/FDM-994/01-chatgptgithub-smartdock-sidebar-drag-01-implement-drag-targets>) owns Tasks 1–5, review, automated checks and Draft PR handoff. [Local slice: FDM-995](<https://linear.app/fdamaso/issue/FDM-995/02-local-omarchy-smartdock-sidebar-drag-02-qualify-native-drag>) owns Task 6 and narrow demonstrated runtime fixes on that exact candidate. The native <issue id="fea88aea-b984-464a-8810-64f82b1bfaeb" href="https://linear.app/fdamaso/issue/FDM-994/01-chatgptgithub-smartdock-sidebar-drag-01-implement-drag-targets">FDM-994</issue> → <issue id="c9d9906b-1717-4e50-a42d-8d48a7e34f12" href="https://linear.app/fdamaso/issue/FDM-995/02-local-omarchy-smartdock-sidebar-drag-02-qualify-native-drag">FDM-995</issue> dependency stays in place. Source Done does not mean compositor/pointer/rendering acceptance.

**NEXT:** the flat-hierarchy prerequisite's validated source handoff. Its missing dedicated issue is not replaced with an unrelated completed issue. Keep the existing Backlog/start gates until the prerequisite handoff is recorded; this revision does not promote or start execution.

## Review focus and required regressions

| Review finding | Owning tasks | Mandatory regression |
| -- | -- | -- |
| R1: header active-workspace reference disagrees with current owner | 4 | Header still references workspace 3 after workspace inventory moves it to another monitor: hover/release reject, zero dispatch. |
| R2: incomplete or uncorrelated success evidence | 5 | Workspace location appears before monitor relocation; remain pending until exact window/workspace/monitor evidence matches. Reject replacement handles and stale operation tokens. |
| R3: timeout incorrectly presented as failure/rollback | 5 | Accept transport, exceed deadline, then publish successful location: no rollback message, compensating move, or revived expired feedback. |
| R4: queued anchor restore undoes success scrolling | 5 | Execute real queued restore ordering with an offscreen destination and two mirrored panels: final destination stays visible only in the originating viewport. |
| R5: workspace-source rejection text is missing | 1–2 | Monitor-pinned workspace, same-monitor no-op, unknown/stale monitor, then unpin and valid hover: correct source-specific feedback and unchanged dispatch eligibility. |

---

## Task 1 — Source-kind-aware reasons for non-targets

**Own:** `components/DockSidebarController.qml` (`dragDestination`, `updateRowDrag`, cancellation), `tests/test_sidebar_drag.mjs`, and the existing interaction fixture as needed.

**Interface:** Add controller property `dragRejection`, initially `null`. For a geometrically hit but ineligible destination, use `{key, sourceKind, reason, identity?, monitor?}`. `sourceKind` is `window` or `workspace`; optional identity/monitor fields contain only verified canonical values. `dragDestination` still returns `null` for ineligible destinations and does not dispatch.

- [ ] Write failing fixture cases for both source kinds before changing classification.
- [ ] Window reasons: `same-workspace`, `pinned` (from `windowWorkspacePin`), `unknown-location`, `stale`; Task 4 adds `owner-mismatch` for an active-workspace/header ownership conflict.
- [ ] Workspace reasons: `same-monitor`, `workspace-pinned` (from `workspaceMonitorPin`), `unknown-location`, `stale`. A workspace's monitor pin is not a window's workspace pin and must not produce a window-oriented label.
- [ ] Classify the applicable pin restriction before reducing a generic false move predicate to a no-op. Use `workspaceMoveWouldChange` for windows and the existing workspace-to-monitor policy for workspaces; preserve current eligibility. Resolve identities/owners before composing labels. Do not invent workspace numbers or monitor names for unknown locations.
- [ ] Clear rejection at drag start, valid hover, leaving all target geometry, cancel, and release. A stale **source** still calls `cancelRowDrag("stale-source")` in `updateRowDrag`; never keep its live drag ghost. A stale destination may display rejection while the source remains valid.
- [ ] Run the task tests, then review/commit this checkpoint without introducing action dispatch changes.

**Acceptance:** Each reason has a fixture assertion; invalid hover has zero compositor calls; release remains single-consumption; a monitor-pinned workspace dropped elsewhere shows `workspace-pinned`; an unpinned workspace dropped on its current monitor shows `same-monitor`; removing the pin and hovering again clears rejection and produces a valid target. Retain stale-source cancellation and existing window pin/no-op regressions.

## Task 2 — Source dimming and ghost pill (W1, W5, G1)

**Own:** `components/DockSidebarViewport.qml` (proxy), `components/DockSidebarRow.qml` (source dimming), `components/DockSidebarRowInput.qml` (cursor), `components/DockSidebarInteractionModel.js` (pure formatting and offset), and relevant Node/QML tests.

**Interface:** The pure destination formatter consumes source kind plus `dragTarget`/`dragRejection`, and returns text and semantic tone. Identity-to-label formatting supports numeric and named workspaces; null destination and null rejection mean no destination line.

- [ ] Write failing formatter/source-opacity checks for both window and workspace drags.
- [ ] Dim the dragged window row, or all rows of a dragged workspace, to 0.4 opacity. Suppress source hover/press styling during the drag.
- [ ] Use Omarchy surface, border, shadow, typography and semantic color tokens. Ghost line 1 contains the window icon and shortened title, or the workspace badge and up to three app icons. Line 2 follows this source-kind-aware table:

| Source / state | Text | Tone |
| -- | -- | -- |
| Window → workspace | `→ Workspace <label>` | accent |
| Window → monitor header | `→ <Monitor> · workspace <label>` | accent |
| Window → new-workspace slot | `→ New workspace on <Monitor>` | accent |
| Workspace → monitor | `→ <Monitor>` | accent |
| Window / own workspace | `Already in workspace <label>` | muted |
| Window / workspace pin | Not-allowed icon + `Pinned to workspace <label>` | urgent |
| Workspace / current monitor | `Already on this monitor` | muted |
| Workspace / monitor pin | Not-allowed icon + `Workspace pinned to <Monitor>` | urgent |
| Either / unknown location | `Destination unavailable` | muted |
| Either / stale destination | `Destination changed` | muted |
| Window / owner mismatch | `Workspace no longer on this monitor` | muted |

- [ ] Width is `min(168, sidebar − 16)` with a nonnegative clamp; rail mode displays the icon only. Clip at the viewport boundary and clamp by the visible pill width, replacing the test that currently requires the 22 px leading-artwork behavior.
- [ ] Use the closed-hand cursor during every drag, including window sources. Disable row hover fills while `rowDragActive`; preserve grabbed-source input ownership and successful `UngrabExclusive` release.
- [ ] Run formatter tests and `tests/tst_sidebarinteraction.qml`, review and commit the checkpoint.

**Acceptance:** Verify source opacity, valid/blocked/no-op text for both source kinds, named labels, unknown/stale cleanup, clipped expanded/rail geometry, and rejected→valid transitions. No helper derives action eligibility from display text.

## Task 3 — Whole-group targets and new-workspace slots (W2, W4, W5, G1)

**Own:** `components/DockSidebarViewport.qml` (`dropKey`, new `workspaceSpanHits()`, workspace/monitor chrome), `components/DockSidebarRow.qml` (row fill and footer), and `hitTarget` in `components/DockSidebarInteractionModel.js`.

- [ ] Write failing hit-order, span-geometry and placeholder tests.
- [ ] For window drags, hit order is footer slots → workspace group spans built from painted `sectionSpanRect` and inset → monitor header/unclaimed card-padding-only regions introduced in Task 4. Preserve whole-card `monitorCardHits()` for workspace sources. Clip all target rectangles to the hierarchy viewport; exclude Widget tail and footer extra height from workspace/header targets. An invalid first hit ends the search: no fallback to a monitor action. Workspace spans reuse the section-span's existing row key.
- [ ] Highlight the whole workspace group through its chrome delegate with accent fill only (`Style.pressedFillFor` or equivalent) and accent its badge. Disable per-row `dropFill` for window drags. Ensure the final workspace group can highlight even where its separator is intentionally hidden.
- [ ] Assign gaps inside a monitor card deterministically to adjacent workspace groups. Add a few pixels of previous-valid-target stickiness only near shared workspace boundaries; never extend into a header, footer, other monitor or clipped-out area. Recompute after scroll/geometry changes and again at release.
- [ ] Draw a dashed “+” badge in the badge column and a dashed footer row. Idle, valid target (accent border/fill), and pinned-window blocked (urgent dashed border/not-allowed icon on every slot) states are distinct. Animate appearance over about 120 ms, honoring the animation preference without moving target geometry as hover changes.
- [ ] For workspace→monitor drags, accent the target card border as well as fill. Show dimmed placeholder content on light accent fill at its numeric/named sorted position, using drag-only extra height rather than a synthetic model row.
- [ ] Run task tests, review and commit the checkpoint.

**Acceptance:** `tests/test_sidebar_drag.mjs` covers hit priority, gaps, own-workspace stopping and no fallthrough; `tests/test_sidebar_geometry.mjs` compares hit and painted span rectangles including insets; `tests/tst_workspacemonitordrag.qml` covers card border and numeric/named placeholder order. Footer pseudo-keys cannot collide with real row keys. Preserve clipping, Widget-tail exclusion, autoscroll and empty-monitor behavior.

## Task 4 — Window drop on a monitor header (W3)

**Own:** Task 3 files plus `components/DockWindowActions.qml`, `components/DockSidebarController.qml`, `tests/sidebar_interaction_fixture.mjs`, and `docs/SIDEBAR_INTERACTIONS.md`.

**Interface:** Extract the existing active-workspace lookup as `monitorActiveWorkspaceIdentity(monitor)`, used by both header-drag resolution and `pullToplevelToMonitorWorkspace`. Keep the existing Ctrl+click semantics; header-specific ownership checks must not silently redesign that path. Valid header target: `{key, kind: "monitor", identity, monitor}`, with `monitor` taken from the verified resolved owner, not copied unchecked from the header.

- [ ] Write failing tests for stale header/owner disagreement during hover and between hover/release, in addition to the original header cases.
- [ ] `hitTarget` accepts a window→monitor only for the header or otherwise unclaimed card padding. No whole-card fallback over workspace rows, separators, Widget tail or footer. Workspace-source whole-card behavior is unchanged. Replace the blanket window→monitor rejection test with separate header-valid/content-invalid cases.
- [ ] Resolve a header destination in this order:
  1. Canonicalize the requested connector/monitor; reject a missing monitor.
  2. Read `monitorActiveWorkspaceIdentity(requestedMonitor)`; reject missing active workspace.
  3. Resolve that identity through `resolveWorkspaceDropTarget(identity)`; require a known canonical workspace and owner.
  4. Require `resolved.monitor === requestedMonitor`. Otherwise record `owner-mismatch`, return `null`, and dispatch nothing. Never relocate the workspace to make the header reference appear correct.
  5. Apply window pin classification and `workspaceMoveWouldChange([capturedTarget], resolved.identity)`; no-op and pinned cases get the Task 1 reasons.
  6. Return the verified identity and verified owner in `dragTarget`.
- [ ] Repeat the full owner-equality/source-validity check at release, compare with the captured hover identity/monitor as today, and reject changed active workspace, changed owner or topology. Do not rely on comparing two copies of the same unchecked header monitor value.
- [ ] Immediately before the shared action, require the resolved current owner still equals the expected header monitor. Dispatch through `moveCapturedToplevels([target], identity, true)`, not `pull…`, preserving live member revalidation, pins, minimized restore, no-op handling and ordered follow behavior. No focus-dependent selector and no workspace relocation for existing destinations.
- [ ] Accent the whole card's border/fill, the header label (rail: monitor glyph), and the resolved active workspace badge. Match `dragTarget.identity`, not frozen `row.active` state.
- [ ] Replace the “Window moves never target monitor headings” rule in `docs/SIDEBAR_INTERACTIONS.md` with these semantics and the recorded same-monitor decision. Run tests, review and commit the checkpoint.

**Acceptance in** `tests/test_sidebar_drag.mjs`**:** valid move, same workspace, pin, minimized source, named workspace, missing active workspace, changed active workspace before release, topology cancellation, and both ownership-conflict timings. Specifically leave DP-1's `activeWorkspace` pointing at workspace 3 while moving workspace 3's inventory owner to HDMI-A-1: hover/release must reject with zero dispatch, and must never issue `moveworkspacetomonitor` as a repair. Cover card/label/badge bindings in `tests/tst_sidebarinteraction.qml` and preserve classic/Lua action behavior.

## Task 5 — Correlated confirmation, stable success scrolling, and safe cancellation feedback (W6, W7)

**Own:** `components/DockSidebarController.qml` (confirmation state), `components/DockSidebarViewport.qml` (originating-surface presentation and scroll ordering), `components/DockWindowActions.qml` (new-workspace receipt without changing boolean callers), existing interaction fixtures, `tests/test_sidebar_drag.mjs`, and `tests/tst_sidebarinteraction.qml`.

### 5.1 Separate the gesture from the operation and its presentation

- [ ] Write failing state/transport/queued-callback tests before implementation.
- [ ] Before `cancelRowDrag("release")`, snapshot the source key, exact captured toplevel/address (window source), source workspace identity, source coordinates, pointer position, icon/label, validated destination information already known, originating panel connector and originating viewport generation. For a new-workspace request, capture only the requested monitor until the action receipt supplies the allocated workspace identity; never invent an expected workspace before allocation. Gesture cleanup still happens before compositor dispatch, preventing duplicate submission.
- [ ] Use an increasing controller-local operation token; every confirmation check, deadline callback, flash, snap-back and queued scroll captures it. A callback acts only if its token and originating surface generation remain current.
- [ ] Post-release presentation must not hold `interactionBusy`, retain a pointer grab, freeze the projection, or expose a second dispatch path. The viewport stores presentation data; the existing controller owns bounded operation tracking. Snapshot live data before cleanup invalidates drag bindings.

**Pending operation contract:** `{token, sourceKind, sourceKey, toplevel?, address?, sourceWorkspace, expectedWorkspace, expectedMonitor, originConnector, originSurfaceGeneration, deadline, state}`. Window operations require both exact `toplevel` object and normalized captured address; workspace operations have no fabricated window address. Expected identities are canonical. Presentation geometry/artwork lives in a separate snapshot, not in action identity.

### 5.2 Obtain the actual new-workspace result without breaking callers

- [ ] For existing-workspace/window→header moves, record the revalidated expected workspace **and monitor**, not just the workspace. For a workspace drag, record the captured workspace identity and expected destination monitor.
- [ ] Introduce `moveCapturedToplevelsToNewWorkspaceResult(members, monitorIdentity)` in the shared action, and its single-window adapter `moveCapturedWindowToNewWorkspaceResult(member, monitorIdentity)`. The accepted result is `{accepted: true, expectedWorkspace, expectedMonitor, members: [{toplevel, address}]}` from the exact allocation and final member/monitor revalidation used for the one submission. Known pre-dispatch rejection returns `{accepted: false}`. “Accepted” means submitted, never compositor-confirmed.
- [ ] Keep `moveCapturedToplevelsToNewWorkspace(...)` and `moveCapturedWindowToNewWorkspace(...)` strictly boolean-compatible by delegating once to the result-producing implementation and returning `.accepted === true`. The sidebar confirmation path consumes the structured result. Do not dispatch once for a receipt and again for the move, and do not turn old callers' `if (result)` into an always-truthy rejected object.
- [ ] Use the receipt's allocated identity and verified monitor. Do not predict a number from the footer, rerun allocation to infer the previous result, or accept an arbitrary later workspace as proof of the intended new-workspace move.

### 5.3 Define confirmation and timeout semantics

| State | Evidence | Presentation / allowed transition |
| -- | -- | -- |
| `rejected` | Known validation refusal before any dispatch | Optional visual snap-back to the exact still-visible source; no success and no compositor rollback. |
| `cancelled` | Gesture cancelled before submission | Optional safe snap-back or immediate cleanup; no dispatch. |
| `pending` | Request submitted; expected result not yet fully observed | Bounded neutral pending feedback; continue only through existing refresh signals and one deadline timer. |
| `confirmed` | Exact captured entity and complete expected location observed | Schedule success presentation after projection/anchor restoration settles. |
| `unconfirmed` | Deadline expires or transport outcome is ambiguous after possible submission | Show `Move not confirmed` or end feedback neutrally; no failure/rollback claim, retry, or compensating move. |
| ended/superseded | New drag, invalid surface/topology, source closes, or feedback ends | Invalidate token, stop timer and ignore queued/late callbacks. |

- [ ] Create the operation token and origin snapshot before dispatch. Once the shared action returns its accepted result, install the full pending record and immediately evaluate current live location once; then reevaluate through existing refresh signals. This catches a synchronous readback during submission without interpreting dispatch acceptance as confirmation or adding polling. If the token/surface was invalidated during submission, do not recreate its feedback.
- [ ] Window confirmation requires the **same live captured toplevel and address**, an unambiguous current workspace equal to `expectedWorkspace`, and a resolved current owner equal to `expectedMonitor`. Require the restored window to be out of the minimized storage workspace. Missing or inconsistent inventory stays pending; do not confirm a replacement object that reuses the same address.
- [ ] New-workspace confirmation uses the same full predicate. A window appearing in the new workspace before that workspace arrives on the requested monitor is not success.
- [ ] Workspace-drag confirmation resolves the captured workspace identity and requires its current owner to equal `expectedMonitor`. It is not confirmed merely because the workspace still exists. Missing/ambiguous identity does not manufacture success.
- [ ] Use existing refresh/readback signals plus one bounded single-shot deadline timer, initially 1500 ms with an injectable clock/deadline for tests. The deadline is a UI wait bound, not evidence of failure. Do not create a polling loop, second compositor watcher or per-frame JavaScript path. Runtime qualification may tune this internal bound with recorded evidence, without adding a setting.
- [ ] On timeout, end the pending operation as unconfirmed. A later location update may update the normal sidebar model, but cannot resurrect expired feedback, scroll, flash, or reverse the move.
- [ ] Only known pre-dispatch refusal/cancellation may animate the preserved ghost toward the exact source row over about 200 ms. Use `Move not allowed` for refusal or no text for cancellation, not “Couldn't move — returning.” If the source disappeared or is offscreen, end feedback without targeting another row. Honor the interface-animation preference. Do not treat an exception/unknown transport outcome after possible submission as guaranteed rejection.

### 5.4 Order success presentation after restoration, on the owning surface only

- [ ] Confirmation must not call `positionViewAtIndex` directly in a refresh handler while `requestRestore()`/`restoreAnchor()` is queued. Queue one token-scoped success presentation for the **originating viewport**, not every mirrored panel listening to the controller.
- [ ] Wait for projection reconciliation and the existing anchor-restoration lifecycle to settle (`pendingRestore === false` and `restoring === false`); use existing completion/events plus bounded deferred work, not an unbounded `Qt.callLater` retry loop. Recheck the operation token and surface generation before acting.
- [ ] Call `forceLayout()` as needed, then resolve the exact moved row's **current key/index** from the reconciled model, never a pre-drop index. Verify the entity still matches before presenting. If offscreen, use `positionViewAtIndex(index, ListView.Contain)`; apply the normal post-layout anchor capture so the success position becomes that connector/mode's saved anchor rather than being undone by a pending restore.
- [ ] Flash the exact row with an accent fill fading over about 400 ms. If folded or absent, do not expand groups, steal focus, or flash another window; use only a verified owning visible workspace group as a bounded fallback, or end feedback. Workspace drags use the verified workspace group rather than a window row.
- [ ] Preserve other mirrored panels' content position and connector×expanded/rail anchor memory. A destroyed/recreated origin viewport does not transfer its old feedback to another surface with the same connector.
- [ ] A new drag, topology/surface invalidation, closing the captured window or teardown invalidates pending confirmation, deadline, queued restore-dependent scroll, flash and snap-back. Do not keep any polling or feedback work alive after teardown.

### 5.5 Required regression matrix

- [ ] Existing workspace: accepted dispatch alone remains pending; exact live window + workspace + owner confirms once; false/pre-dispatch refusal has zero transport calls.
- [ ] Synchronous readback during submission: the immediate post-receipt location evaluation confirms only the complete expected location; no missed-event timeout and no feedback recreation after token/surface invalidation.
- [ ] New workspace: receipt contains the actually allocated identity; boolean wrapper callers remain booleans; there is exactly one submission in classic and Lua paths; workspace-before-monitor readback remains pending until the owner matches.
- [ ] Workspace source: same identity on the old monitor is not success; identity on the expected monitor confirms; missing/ambiguous workspace does not confirm.
- [ ] Reused address on a replacement toplevel, source closure, topology invalidation and superseded operation tokens never confirm or flash another entity.
- [ ] Accepted transport → deadline expiry → late successful readback does not claim failure/rollback, dispatch a compensating move, or revive feedback. Normal model refresh remains enabled.
- [ ] Reject-before-dispatch and cancel-before-dispatch have safe visual cleanup; missing/offscreen source never snaps to a different row; reduced-motion disables animation, not state cleanup.
- [ ] Queued restoration test: refresh schedules anchor restore, destination begins offscreen, confirmation arrives before the restore callback, and all queued callbacks run. The final target is visible, its correct anchor is saved, and no later restore jumps back.
- [ ] Mirrored viewport test: two panels, independent connector/mode anchors, mixed expanded/rail state. Only the originating live surface scrolls/flashes; the other panel's anchor/contentY stays unchanged. Destroy/recreate the source viewport and verify old callbacks are ignored.
- [ ] Folded/absent row fallback, numeric/named workspaces, minimized restoration, fresh drag cancellation, and teardown timer cleanup.
- [ ] Exercise actual deferred callbacks in the QML harness; a synchronous transport mock alone cannot qualify scroll ordering. Run Node/QML gates, review changed callers and commit the checkpoint.

## Task 6 — KVM and native qualification

- [ ] Start a fresh named KVM guest per `docs/DEV_SESSIONS.md`, sync the exact candidate worktree, restart the guest dock, and qualify W1–W7/G1 on two virtual outputs. Capture source dimming, ghost labels, group/header/footer targets, workspace-pin and same-monitor no-op feedback, sorted placeholders, rail mode, theme and animation preference.
- [ ] Verify real pointer press/drag/release, grab completion, cancellation, scrolling, confirmed success and known pre-dispatch refusal snap-back. Verify unconfirmed feedback never promises rollback. Controlled delayed/inconsistent readback is exercised through the substituted-transport tests, not by claiming a native failure was reproduced without evidence.
- [ ] Check offscreen confirmed destinations after restoration and independent mirrored-panel scroll positions; include workspace→monitor and new-workspace window moves, named workspaces and minimized restoration.
- [ ] Code only narrow demonstrated runtime defects on the exact source candidate. Each fix commit invalidates prior exact-head acceptance and requires targeted reruns plus the applicable validation gate. Record the final base/head, commands/results, guest identity, observations and storyboard captures; avoid private window titles/data in shared logs.
- [ ] Update the native matrix in `docs/SIDEBAR_INTERACTIONS.md` for header owner checks, both source-kind rejections, confirmed versus unconfirmed outcomes, and scroll ordering. Stop and clean up the guest and record stopped-state evidence and reset/rollback procedure.
- [ ] Physical desktop testing is only on explicit user request through `smartdock dev use` followed by `smartdock dev reset`. Never start a second dock beside production or edit its installed plugin.

## Risks and safeguards

* **Paint/hit geometry drift:** compare actual span rectangles/insets; no invalid-hit monitor fallback (Task 3).
* **Key collisions:** footer pseudo-keys must not name real rows; workspace spans deliberately reuse their workspace row key (Task 3).
* **Frozen projection:** highlights come from `dragTarget`, never `row.active`; confirmation uses live location evidence after release (Tasks 4–5).
* **Header/owner disagreement:** equality against resolved owner at hover and release, not two unchecked header values (Task 4).
* **Partial/late compositor effects:** full expected workspace+monitor predicate, exact entity, operation token and terminal unconfirmed state; no UI-driven rollback (Task 5).
* **Scroll restoration/mirrored surfaces:** restore first, resolve current index, contain/capture once, origin-surface guard (Task 5).
* **Performance/lifecycle:** bindings on existing items; no per-frame JavaScript beyond existing autoscroll, one bounded deadline timer, no work after teardown.

## Validation and completion evidence

For each affected checkpoint, first observe the targeted regression fail, implement the minimal scoped change, then rerun it and the relevant suites. Run `node tests/test_sidebar_drag.mjs`, `node tests/test_sidebar_geometry.mjs`, affected QML suites including `tests/tst_sidebarinteraction.qml` and `tests/tst_workspacemonitordrag.qml`, the complete applicable `AGENTS.md` gate, and `git diff --check` on the final candidate. Inspect shared-action callers to prove legacy boolean contracts remain intact.

Follow `docs/DELIVERY.md` for Draft PR-only delivery, exact base/head SHAs, source review, CI evidence and stacked-branch retarget/revalidation. Source handoff lists executed commands/results and explicitly unqualified compositor/pointer/rendering behavior. Local qualification begins on that exact head; fix commits require refreshed evidence.

Headless tests do not qualify native pointer grabs, focus, animation or rendering. KVM captures/observations qualify the tested guest context only; any full Omarchy/physical-desktop checks required by repository policy remain explicit gates. No runtime tests or implementation are claimed by this plan revision.

## Revision R1 change record

R1 integrates all five review findings into the owning tasks: header-to-workspace ownership equality; complete entity/workspace/monitor confirmation and allocation receipts; timeout-as-unconfirmed without rollback claims; restoration-ordered originating-viewport scrolling; and workspace-source pin/no-op feedback. Original feature scope, shared ownership, sorted placeholders, visual constraints, prerequisite, unresolved header product decision and source/local delivery split are retained. The original Markdown attachment is historical; this document is the execution source until its contents are synchronized to the repository plan path.
