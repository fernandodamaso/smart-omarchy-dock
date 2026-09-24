# Sidebar Widgets — R1 implementation and delivery contract

Synchronized 2026-09-24 from FDM-996 and its five R1 child descriptions,
including their 2026-09-24 execution-routing updates. This section supersedes
the recovered original proposal retained verbatim in the historical appendix.
The full linked Linear descriptions remain authoritative for future revisions.

## Authority, source and routing — FDM-996

- Parent: https://linear.app/fdamaso/issue/FDM-996 . Coordination only (`planning`),
  not an executable task. Source implementation precedes local qualification.
- Original source/design handoff: `feat/sidebar-widget-split-scroll` at
  `c660325bf437e4330b00f12cdd2beb3679d79ab9`, based on
  `51de331db28ebd17406c3ed02b9138df6c1e1b7e`.
- FDM-997 source candidate starts from current `main`
  `22ed8f26ffbc531de8470c49528454e16be4be35` plus the original handoff assets;
  it does not modify the stable handoff branch or absorb unrelated drag work.
- Preserve the complete `docs/widget-gallery/reference/sidebar-redesign-2026-09-23/`
  directory: index/Current/Main/Split.html, README, source/*.dc.html and
  source/canvas.json. Main is the Proposed visual reference for 05/06; Split
  guides 07/08. Static renders work without the private design-canvas runtime.
  Treat colors as token guidance, not sampled QML literals or a pixel contract.
- FDM-997/05 and FDM-998/06 are remote (`execution:chatgpt-github`) source slices,
  may share an independently reviewed polish Draft PR from current main, and do
  not need FDM-994 solely for visual changes. This execution implements 997 only.
- FDM-999/07 is remote, after accepted 997, 998 and 994 source is on the actual
  candidate. FDM-994's #111 (`feat/sidebar-drag-feedback`, recorded head
  `cc60762a1b9c559dabd35c840897d8eb90cdea74`) is a Draft/unmerged source handoff,
  not native qualification. Re-resolve refs before integration. Use a distinct
  stacked Draft while parents remain open, never write their stable branches.
  Retarget/rebuild and refresh exact-head evidence after parents land, per
  `docs/DELIVERY.md`. Preserve #111's provisional same-monitor header-drop
  product decision and FDM-995's independent runtime gate.
- FDM-1000/08 is remote but OPTIONAL after 999, not required for v1. A routing
  label is not authorization to start or a reason to make it a core blocker.
- FDM-1001/09 (`execution:local-omarchy`) qualifies the integrated exact-head
  05/06/07 candidate after 999; 08 is included only when explicitly selected.
  Local runtime fixes continue on that handed-off branch/PR, one writer at a
  time, not a second implementation.
- Remote owns repository-accessible native audits, automated/headless tests,
  source review/fixes and fresh exact-head CI. Full-shell/KVM/device-input and
  screenshot acceptance remains mandatory under 1001 when unavailable remotely.
  Report unavailable checks as unrun/blocked, never passed. Remote completion is
  **remote-complete / local-validation-required**, not shipped/native-approved.
- Handoff includes Draft PR, branch, exact base/parent/head SHAs, commands and
  actual results, source-review findings/fixes and outstanding native checks.
  No automatic merge, installation, deployment, production-desktop preview,
  installed-plugin edit, Hyprland-settings change or second dock process.

### Shared design and ownership

Compose existing Qt Quick/QML, Quickshell, qs.Ui/qs.Commons and local model helpers.
Keep one host-owned provider manager, FileView settings writer, Widget popup
session and DockWindowActions; one panel-owned manager remains reachable from
SmartDock's main header even with zero presented cards. Keep WidgetKit 1.0,
provider/settings/popup contracts and filtered-to-configured reorder mapping.
Reflow, clipping, rail, collapse and popup changes never reacquire/resubscribe.
FDM-967 retains lifecycle authority; 972/973/975/983 foundations remain in force.
Only 999 replaces the existing shared-scroll placement; never revive the retired
`min(240, 30%)` compact footer or overflow sentinel. No parallel generic UI,
scrolling, settings or provider framework. New sparkline area fill is deferred.

## FDM-997 / WIDGET-05 — Native card and section chrome

https://linear.app/fdamaso/issue/FDM-997 — presentation only, shared-scroll stays.
Files: DockSidebar, DockWidgetCard, DockSidebarWidgetArea,
DockSidebarPinnedStrip, tst_dockwidgetcard, test_sidebar_widgets, and actual
native-primitive test stubs. No WidgetKit token redesign (998) or scroll split (999).

### Exact native audit

Record targeted Omarchy Git SHA (or installed package/build if no checkout),
Qt and Quickshell versions. The old `4.0.0.alpha` note is historical, not a
primitive-contract proof; the review recorded installed `4.0.3-1`. Inspect
shell/Ui/PanelSectionHeader.qml, Button.qml, relevant Commons tokens and a
matching first-party caller for EACH at the targeted revision. Verify property
names, implicit size/insets, focus/keyboard, tooltip, accessibility, disabled
state and both host contracts. Prefer native components when they match. An
actual documented mismatch permits the existing minimal Commons-based custom
composition, never an invented property or new generic library. Stub presence
is not native qualification. Installed/full-shell version matching remains local.

### Checkpoint 1 — shared idle surface (failing tests, implementation, gate, commit)

- Optional `property var appearance: null` on area/card; forward existing
  DockSidebar.sidebarAppearance through both without breaking omitted callers.
- Idle fill = appearance.monitorFill; null fallback =
  Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035)).
- Transient HEADER hover/focus fill = appearance.workspaceHoverFill; fallback
  must equal the sidebar formula, not a second palette. Preserve focus border.
- Header/body share ONE idle surface. Delete body Rectangle tint 0.025; no
  replacement permanent body/header tint. Divider is 1px alpha(foreground, 0.07).
- Radius = appearance.cardRadius when defined; otherwise min(3, Style.cornerRadius).
- Title = Style.font.body / Font.DemiBold, like DockMonitorLabel; foreground when
  expanded or focused, alpha(foreground, 0.85) when collapsed.
- Test actual appearance propagation, null compatibility, idle surface/no body
  tint, radius and title weight; live theme/appearance changes must propagate.

### Checkpoint 2 — header controls (failing tests, implementation, gate, commit)

- Visual order: icon → title → grip → badge → collapse. Badge anchors to collapse
  and does not move when grip appears. Title always ends at grip's left edge.
- `grip-vertical` icon opacity is 0 idle and 1 on card hover, descendant focus or
  active drag. Keep grip Item enabled/visible/width and pointer target stable;
  it is pointer-only, never a dead Tab stop. Accessible name stays
  `Drag <title> to reorder`.
- Keep gesture controller, press threshold, click suppression, cancellation,
  preventStealing and header double-click/vertical-scroll semantics unchanged.
- Collapse uses `chevron-down`, rotation collapsed ? 0 : 180. Reserve right
  chevrons for window-row open/navigation.
- Test badge/grip ordering and fixed badge x across opacity states; long titles
  at minimum sidebar width and counts 0/1/99+ without overlap; actual focused
  body input, hidden-grip drag/reorder, cancellation, click/double-click and keys.

### Checkpoint 3 — native section composition (failing tests, gate, commit)

- WIDGETS and PINNED use audited Ui.PanelSectionHeader (or documented mismatch).
- Replace section Add/Manage text with quiet Ui.Button { iconText: "" } and a
  plus WidgetIcon, following existing collapse-button composition.
- Tooltip/Accessible.name `Add or manage Widgets`; preserve Enter/Space/pointer
  activation, focus and disabled behavior and existing panel-owned manager.
- Section labels, card icon and body content align to
  `workspaceCardInset + Style.space(4)` on BOTH sidebar edges.
- Test native parity/insets, plus accessibility/tooltip/keys/disabled states and
  main-header manager with zero presented cards. Test no reorder/collapse/remove
  or Add/Manage regression. Native visual elevation/title/radius remains 1001.
- Run node tests/test_sidebar_widgets.mjs, node tests/test_widgetkit_structure.mjs,
  offscreen QML, git diff --check and current AGENTS/DELIVERY gates. Obtain fresh
  exact-head CI. Full local gate and both-edge KVM screenshots are still required
  under 1001; no source/headless assertion implies that acceptance.

## FDM-998 / WIDGET-06 — WidgetKit token alignment (not implemented here)

https://linear.app/fdamaso/issue/FDM-998 . Visual-only public WidgetKit 1.0; no
property/signal/import removal or rename; additive properties allowed, not required.
Files: WidgetText, WidgetFormField, WidgetStat, WidgetTextInput,
WidgetSemanticPalette, DemoWidgetDisplayBody, WIDGET_COMPONENTS.md, structure/QML
and gallery tests; inspect only other usages sharing those token contracts.
WidgetSparkline is unchanged; do not add fillOpacity/area fill.

1. Failing token/radius tests first, then substitutions and focused gate/commit:
   secondary/caption default Color.muted; rectangular stat/input radius
   min(3, Style.cornerRadius) at radii 0/2/8; preserve circular/pill badges,
   radios and progress geometry. WidgetStat has fill alpha(foreground, 0.04),
   no border. danger = Color.urgent. Retain success/warning APIs and theme-derived
   HSL unless the exact inspected native revision supplies suitable tokens;
   record that inventory, never generalize absence across revisions.
2. Measure normal-text contrast on ACTUALLY composited monitor/stat/input
   surfaces in one dark and one light target theme; require 4.5:1. If muted
   fails, compare old 0.62-alpha foreground after compositing and retain ONLY
   if it passes. Otherwise use foreground for that role ONLY if it passes;
   else record theme incompatibility and leave acceptance open. Centralize
   justified exception in existing palette/role, no scattered literals or new
   theme engine. Record colors, ratios, theme/role and native revision in docs.
   Do not automatically count disabled/decorative content as normal text.
3. Neutral demo status semantic info, neutral reference badge; Memory warning
   at >=85% (test 84.9/85/100), a gallery convention, not a global threshold or
   ban on genuine semantic success/error/urgent. Preserve those genuine states.
4. Real gallery plus unchanged external-package fixture through WidgetKit 1.0:
   load/render, input edit/focus, enabled/disabled buttons, live theme changes,
   fonts/signals/property names/import/provider context preserved. Keep design
   assets unchanged and record deferred sparkline fill.

Structure assertion disallows hardcoded 0.62 except measured documented passing
exception. Run widgetkit/sidebar Node tests, full QML, Python sidebar syntax,
git diff --check, current full gates and exact-head CI. Native theme/font/contrast
and package rendering not available remotely stay under 1001, not assumed passed.

## FDM-999 / WIDGET-07 — independent Widget scroll (not implemented here)

https://linear.app/fdamaso/issue/FDM-999 is authoritative for allocation, units,
short-space and interaction policy. Requires accepted 997/998/994 source first.
Files: WidgetModel, Sidebar, Viewport, WidgetArea, WidgetManager, Keyboard boundary
navigation; Card only for focus/presentation wiring. Reuse InteractionModel row
metrics and controller gestures/settings/popup owner. Extend sidebar/widget/card
QML/runtime tests; add test_sidebar_split_layout.mjs and tst_sidebarsplitscroll.qml.

### Checkpoint 1 — pure allocator and stable demand

Internal interfaces: sidebarSplitLayout(input) -> hierarchyHeight/widgetHeight/
blankHeight; Viewport.naturalContentHeight; WidgetArea.presentedWidgetCount,
naturalWidgetHeaderHeight, naturalWidgetContentHeight, readonly scrollView,
layoutRevision, ensureFocusedItemVisible(item). Sidebar.widgetArea points to a
stable sibling, not viewport.contentTailItem. No public provider/kit API changes.

All dimensions are logical pixels. Available A excludes fixed controls,
PINNED/Applications and outer margins exactly once. H is canonical projected row
metrics including spacing, alert/agent/browser expansions and active drag-footer
rows, never ListView's delegate-estimated contentHeight, contentY or allocation.
Wh includes section header and fixed spacing; W includes natural card column,
gaps and bottom padding once. Measure independently of allocated visibility;
finite natural body heights, no unloading to measure. Count is filtered
presentationWidgetIds.length; hidden Herdr-only fallback reserves zero space
without releasing lease. Hmin = monitor heading + two ordinary rows; Wmin =
header + collapsed card. Both minimums are demand-limited. requestedSplitPx is
null automatic or a finite pixel request; no splitter/setting in this slice.

Use the production module's existing finite(value,fallback) and this R1 algorithm:

```javascript
function sidebarSplitLayout(input) {
  input = input || {}
  var A = Math.max(0, finite(input.availableHeight, 0))
  var H = Math.max(0, finite(input.hierarchyContentHeight, 0))
  var Wh = Math.max(0, finite(input.widgetHeaderHeight, 0))
  var W = Math.max(0, finite(input.widgetContentHeight, 0))
  var count = Math.max(0, Math.floor(finite(input.presentedWidgetCount, 0)))
  var h = 0, w = 0
  if (input.rail === true || count === 0 || A < Wh) {
    h = Math.min(H, A)
  } else {
    var wanted = Math.min(Number.MAX_VALUE, Wh + W)
    var hmin = Math.min(H, Math.max(0, finite(input.minHierarchyHeight, 0)))
    var wmin = Math.min(wanted, Math.max(Wh, finite(input.minWidgetHeight, Wh)))
    if (A < hmin + wmin) {
      h = Math.min(hmin, Math.max(0, A - Wh))
    } else {
      var request = finite(input.requestedSplitPx, 0.55 * A)
      var cap = Math.max(hmin, Math.min(A - wmin, request))
      h = Math.min(H, Math.max(cap, A - wanted))
    }
    w = Math.min(wanted, Math.max(0, A - h))
  }
  return {hierarchyHeight:h, widgetHeight:w, blankHeight:Math.max(0, A-h-w)}
}
```

Do not round outputs separately; blank is residual, epsilon 1e-7. When A<Wh omit
section, main-header manager still works. A==Wh can be header-only. If both
minimums cannot fit, reserve whole header, then hierarchy up to minimum, then
remaining body space. No impossible promise to show every hierarchy row.

Failing-first loadModel table uses A800/H1000/Wh32/W1000/count4/Hmin120/Wmin66:
auto →440/360/0; H100→100/700/0; W34→734/66/0; H100+W34→100/66/634;
count0 or rail→800/0/0; A186→120/66/0;185→120/65/0;100→68/32/0;
32→0/32/0;31→31/0/0;0→0/0/0; request560→560/240/0;
request-100→120/680/0;900→734/66/0;null→440/360/0.
Add seeded fractional/nonfinite/missing/negative/count/request cases; finite,
nonnegative outputs sum to sanitized A, bound demand, preserve header when it
fits and demand-limited minimums when sum fits. Compare every real row variant
with canonical metrics; pure scrolling must not change demand/allocation.
Planning-only generated cases do not count as production test evidence.

### Checkpoint 2 — sibling layout and stable anchors

Bounded middle Item: hierarchy y0/h; Widgets yh/w; blank y(h+w)/residual. Remove
conflicting bottom anchors and migrate all contentTail/footer-loader APIs,
callbacks/destructors/tests, but preserve hierarchy drag timers and non-footer
anchor restoration including FDM-994's queued confirmation. Keep one stable
Widget area per panel and existing fullReorderSlot mapping/leases.
Fixed Widget header above body Flickable, vertical/clip/StopAtBounds; scrollbar
uses hierarchy gutter/outset via separate unclipped parent. Passive bottom fade
min(28, body height) only when more content below, no input interception/tint.
Per-panel first-visible stable ID + offset + old order, never saved to dock.json.
On reflow restore after layout, fallback next surviving old neighbor then previous
then origin, clamp. Capture before mutation/automatic clamp; rail/zero-height
must not erase expanded anchor. Do not fight active input; defer restoration
until settled. Explicit focus reveal wins after queued restore. Mirrors retain
their own focus/scroll. Test 0→1→0, hidden Herdr counters, mirrors, width/font
reflow, collapse above viewport, removed anchors and scrolling stability.

### Checkpoint 3 — input, popups and presentation

- Card presentation clip is Widget BODY, true rectangle intersection; stop
  hidden body animation, not providers. Coalesced layoutRevision covers pane
  x/y/w/h, clip, contentY, card geometry, panel edge/screen/visibility. Forward
  revision, not just contentY. Follow popup after split change without scrolling;
  close destroyed/hidden/fully clipped/collapsed/removed anchors/teardown.
  Check ancestor visibility. Manager handles fixed section/main-header anchors;
  close section-owned manager if header disappears; main header works with zero.
- Real vertical wheel/touchpad: hierarchy only over hierarchy, Widgets only over
  card/body (including bounds); neither pane over fixed header/blank. Nested
  scrollable controls get first refusal and contain at bounds; ordinary content
  scrolls Widget pane; preserve deliberate control wheel actions. StopAtBounds
  alone is not containment; prove minimal native acceptance wiring on target Qt,
  no unconditional overlay intercepting children. Document external expectation
  without new required API.
- Title double-click remains stealable for vertical scrolling. Only explicit grip
  reorders. One controller gesture/settings transaction. Reorder edge-scroll
  only inside BODY x bounds/edge bands, remap retained scene point each tick,
  clamp/recompute target; stop cancel/outside. Release outside body (hierarchy,
  header, PINNED, apps, blank, panel exterior) cancels with ZERO write. Preserve
  hidden configured ID order. Cancel missing source/external reorder/surface
  invalidation/hide/Escape/controller; reflow alone is not external reorder.
- Blank DockPositionDragSurface covers residual only, never controls/scrollbars/
  resize handles. Migrate active-mode-drag selection/cancel/preview selectors;
  rail/no-widget uses genuine blank space when available.
- Tab/Backtab: existing hierarchy including inline controls → optional splitter
  (only 08) → section plus → card header/collapse/enabled body controls → PINNED
  → Applications/Trash. Grip never a dead stop. Skip hidden/disabled/collapsed/
  zero-body controls, not revealable offscreen controls. Preserve header and
  Keyboard arrow/Home/End semantics, no focus stealing on hover/update/reflow.
- ensureFocusedItemVisible maps the ACTUAL descendant into card-column space,
  reveals minimally within bounds after pending restore; oversized control
  aligns leading edge. Do not scroll to only oversized card header; nested
  editors keep caret scrolling. Focused-card removal: next then previous then
  visible section plus then main plus, only if this panel owns focus. Collapsing
  focused body returns to card collapse/header. Escape cancels drag first.
- Actual-event regressions: wheel at both bounds, keyboard oversized body input,
  popups when hierarchy changes without Widget scrolling, hidden-grip reorder,
  every invalid drop region, cancellations/external ID changes and zero writes.
  Re-run FDM-994 whole-group/monitor/new-workspace/auto-scroll and pending/
  confirmed/unconfirmed regressions in reduced hierarchy; queued restore before
  origin-only containment, no mirror/Widget offset change, no late success or
  rollback. Provider/popup counters unchanged throughout reflow.

### Checkpoint 4 — source handoff

Update current shared-scroll contract in SIDEBAR_WIDGETS, SIDEBAR,
SIDEBAR_INTERACTIONS, WIDGET_COMPONENTS, README, applicable AGENTS guidance and
obsolete assertions, explicitly not retired footer. Run split-layout/sidebar
widgets/drag/geometry/widgetkit Node, affected Python and full QML plus current
AGENTS/DELIVERY/git diff --check and exact-head CI. Handoff source review/results,
base/parent/head/PRs, actual screenshots and pending native cases to 1001; Draft
is not native approval. Each checkpoint is failing tests → code → gate → commit.

## FDM-1000 / WIDGET-08 — optional adjustable split (not implemented here)

https://linear.app/fdamaso/issue/FDM-1000 . Start only after 999 source acceptance.
Elastic cap, never rigid partition. Use 999's allocator/ownership, no new framework.
Files include Sidebar/WidgetArea/Controller/Model, host intent routing only as
needed, defaults/schema/CLI/inventory, resize/config/CLI/README docs and tests.

1. sidebarWidgetSplit default 0; explicit writes allow EXACTLY numeric 0 or
   0.20–0.80 in 0.01 steps (tolerance1e-9). Reject strings/bools/null/nonfinite,
   0.01/0.19/0.81/0.555/negatives; imported invalid effective fallback auto does
   not rewrite raw settings. Preserve unknown keys. Do not integer-round ratio;
   schema, CLI and authoritative host validation/readback agree on disjoint
   sentinel/range. Test default/reset/0/.20/.55/.70/.80 and invalid cases.
   Convert once: requestedSplitPx = setting===0 ? null : setting*availableHeight.
   At base A800 auto440/360; .70→560/240 (1e-7). Resize reuses ratio, no write.
2. Optional handle within fixed header allocation, never overlapping other input:
   28×3 visual hover/focus/drag bar, >=24 high hit region, Qt.SplitVCursor,
   accessible name Resize Widgets area, automatic/percentage/keyboard tooltip.
   Hide/skip rail/zero-presented/hidden section; disable immovable/clamped ranges.
   Tab after hierarchy before section plus. Up decreases and Down increases .01;
   Enter/double-click reset 0; Escape cancels. From auto use effective h/A clamped
   to allowed ratios, never divide zero. Capture panel/generation, value/revision,
   A and starting boundary. Preview through same allocator; deltaY/capturedA,
   quantize hundredths/clamp; no movement writes.
   Arbitrate with width/row/widget/mode gestures, existing transient owners,
   origin-only preview/cancellation. Release exactly one CHANGED host intent;
   no-op zero. Coalesce keyboard repeat into one write on key release; reset at
   most one changed write, double-click must not commit incidental drag first.
   Escape/pointer cancel/focus-loss/topology/A/external-setting changes/hidden or
   removed section/teardown → zero writes. Check captured value/revision/source
   at commit; stale/busy rejection has no retry/overwrite. Existing saving/error
   feedback; failed request not saved. Runtime clamping never persists.
   Test actual pointer/keys/repeat/reset/cancel/stale edit/mirror/absent section,
   writer counts, geometry/focus, then gate/commit.
3. Document requested vs effective elastic boundary, short-height clamping,
   reset/keys/no-op/nonpersisted corrections and verified real CLI examples.
   Full current gate/diff/exact-head CI plus isolated native checks. If included
   in v1, add 1000→1001 blocking relation and include exact head in qualification;
   otherwise NOT INCLUDED / NOT REQUIRED, no core blocker. Later execution needs
   its own fresh native gate, not reuse an earlier 1001 result.

## FDM-1001 / WIDGET-09 — integrated native qualification (not run remotely)

https://linear.app/fdamaso/issue/FDM-1001 . Enter after 999 with accepted 05/06/994
source, actual base/parent/head/PRs, fresh CI and review. 08 only when selected.
Fresh named KVM per DEV_SESSIONS, sync exact worktree, restart guest dock, capture
and stop guest. Autonomous default standalone. Stripped plugin guest is not full
Omarchy; qualify both appropriate isolated hosts. Physical preview only on explicit
request via smartdock dev use/reset, no second production dock/deploy/main change.
Record Omarchy SHA/build, Qt/Quickshell/Hyprland, outputs/scales/logical A,
themes/fonts, host mode and exact candidate. Compare original Current/Proposed/
Split relationships, not sampled-pixel equality. Matrix:

1. Both edges; min/default/wide widths; dark/light; default/large font; animations
   on/off. Idle surface/title/radius/native labels/insets/plus/focus visible;
   circular controls preserved. Hover header/body, descendant focus and drag
   reveal grip; 0/1/99+ stable badges/long titles; hidden drag, collapse/remove/
   manager. Actual composited contrast for 998 roles, measured passing exception,
   exact native audit/mismatch (never assumed historical alpha).
2. 0/1/4 presented Widgets; short/overflowing hierarchy; tiny/collapsed/tall bodies;
   1080/768 and fractional scaling/large text. Exclude fixed demand once, test
   minimum-sum just above/equal/below, A==Wh/A<Wh/zero, no negative/overlap/clipped
   header/binding warnings. Elastic borrowing and independent overflow; PINNED/
   apps fixed. Hidden Herdr-only zero demand/retained lease, fallback transitions,
   0→1→0, rail and two mirrors. Scrolling cannot move boundary.
3. Actual mouse wheel/touchpad where available: correct pane at both bounds,
   header/blank neither, nested editors contain bounds. Exact Tab/Backtab/skip
   chain, no focus stealing; reveal final focused input on oversized card,
   caret/collapse/focused-removal/lost-section behavior. Differently scrolled
   panes/mirrors retain stable ID offsets through width/font/A/collapse/reorder/
   removal/rail; queued restore yields to gestures and focus reveal.
4. Distinguish title double-click/scroll drag/grip. Widget-only edge-scroll,
   invalid-region release zero write, Escape/external changes/source removal/
   teardown clears feedback/timers. Hidden configured IDs stable. Popup follows
   or closes on geometry change WITHOUT contentY change; width/font/collapse/
   removal/rail/edge/screen too. One popup/no restarted leases. Both manager
   anchors; section closes when gone, main works empty. Genuine blank mode-drag
   preview/cancel/one intent, never from controls/scrollbars/resize handles.
5. Integrated FDM-994 with overflowing Widgets: workspace/monitor-header/new-slot
   targets, hierarchy-edge auto-scroll, clipped ghosts and rejected/cancelled/
   pending/confirmed/unconfirmed feedback. Queued restore then origin-only
   confirmed containment; mirror/Widget offsets unchanged, no late success or
   rollback. Preserve FDM-995 independent gate and provisional product decision.
   Shared evidence counts only when exact candidate and both actual checklists
   covered. Provider acquire/release/activation/subscription counters unchanged
   by presentation, with normal disable/remove semantics preserved.
6. Optional08 only if selected: pointer/key repeat/reset/Escape/no-op/stale,
   two-height runtime clamping/mirrors/restart persistence and one-write/zero-
   cancel;0auto/.70*A units. Otherwise NOT INCLUDED / NOT REQUIRED FOR V1.

Narrow demonstrated fixes on candidate only, regression tests, full source gate,
fresh exact-head CI, resync/restart/recapture after EVERY code change. Record each
case PASS/FAIL/BLOCKED/NOT INCLUDED with SHA, actual input/expected/actual, logs/
images/recordings. Missing device/full-shell checks are blocked, not inferred.
Complete only when required integrated checks pass on ONE final candidate;
source completion never auto-approves native work, merges, deploys or closes 995.

---

## Historical appendix — recovered pre-R1 proposal (superseded, not executable)

The following 262-line original is retained for provenance, including obsolete
formulas, colors and suggestions. Where it disagrees with R1 above, DO NOT use it.

# Sidebar Widget Polish and Split Scroll Implementation Plan

> **For agentic workers:** Execute one slice at a time under its owning issue,
> with tests and exact-SHA evidence per `docs/DELIVERY.md`. The visual reference
> is the "Sidebar Widgets Redesign" design canvas (boards *Current*, *Proposed*
> and *Proposed · split scroll*); the canvas is a mockup, not a pixel contract.

**Visual reference (HTML/CSS, in repo):**
[`docs/widget-gallery/reference/sidebar-redesign-2026-09-23/`](../widget-gallery/reference/sidebar-redesign-2026-09-23/README.md)

- `index.html`: all three boards side by side, plus the design notes (open in a browser).
- `Current.html`, `Main.html` (Proposed), `Split.html` (Proposed · split scroll):
  static renders of each board's default state.
- `source/*.dc.html` and `source/canvas.json`: the exact canvas sources, with the
  interactive behavior (collapse, hover grip, draggable split, Tweaks).

Board to slice mapping: *Proposed* is the target for Slices A and B, and
*Proposed · split scroll* is the target for Slices C and D (its drag handle is
the Slice D interaction). Its hex values are sampled Tokyo Night colors. Map
them to the tokens named in each slice, never copy them into QML.

**Linear:** plan FDM-996. Slices: A = FDM-997 (WIDGET-05), B = FDM-998
(WIDGET-06), C = FDM-999 (WIDGET-07), D = FDM-1000 (WIDGET-08, optional),
local qualification = FDM-1001 (WIDGET-09).

**Goal:** Make Widget cards read as native parts of the sidebar, and give the
Widget area its own scroll so the Monitor/Workspace/Window hierarchy never
scrolls out of view because of Widgets.

**Architecture:** The hierarchy `ListView` in `DockSidebarViewport` stops
hosting Widgets as its `footer`/`contentTail`. `DockSidebar` lays out three
siblings between the header and the pinned shelf: hierarchy viewport, Widget
section header, and a Widget `Flickable`. One small pure JS function computes
the vertical split. The card and kit changes are token/layout changes only; no
provider, lifecycle, settings-writer or popup ownership changes.

**Contract change:** This supersedes the FDM-973 "Shared-scroll layout" section
of `docs/SIDEBAR_WIDGETS.md`. It does not return to the FDM-967 footer: that
footer capped *Widgets* at `min(240, 0.30 * A, A - 2R)` with compact/overflow
modes and starved them. Here the *hierarchy* is capped and Widgets take the
remaining height, with no compact or overflow mode.

**Omarchy revision inspected:** `/usr/share/omarchy` 4.0.0.alpha (not a git
checkout, so no SHA). Primitives reviewed: `Ui/Button.qml` (`iconText`,
`tooltipText`, `focusable`), `Ui/PanelSectionHeader.qml` (caption, bold,
`Qt.darker(foreground, 1.4)`), `Ui/BorderSurface.qml`; tokens in
`Commons/Color.qml` (`foreground`, `background`, `accent`, `urgent`, `muted`;
no success/warning).

## Global constraints

- Keep `DockWindowActions`, the Widget provider manager, the single FileView
  writer and the single host-owned Widget popup exactly where they are.
- Rail mode still gives Widgets zero height. With zero enabled Widgets the
  Widget section has zero height, and Add/Manage stays reachable from the
  SmartDock header (the existing `openWidgetManager` test must keep passing).
- `SmartDock.WidgetKit 1.0` is public. Kit changes in slice B are visual only:
  no property removals or renames.
- A new setting must go through `config/dock.json`, `config/settings-schema.json`,
  `DockModel.js` normalization, `docs/CONFIGURATION.md`, README and the tested
  configuration inventory.
- Validate each visual slice with screenshots in a KVM guest
  (`docs/DEV_SESSIONS.md`) before claiming it matches the canvas.

## Slice A: Widget card and section chrome

Files: `components/DockWidgetCard.qml`, `components/DockSidebarWidgetArea.qml`,
`components/DockSidebarPinnedStrip.qml`, `tests/tst_dockwidgetcard.qml`,
`tests/test_sidebar_widgets.mjs`.

- [ ] **Surface parity.** Pass the sidebar `appearance` into the card. The card
  fill becomes `appearance.monitorFill`, and header hover/focus becomes
  `appearance.workspaceHoverFill`. Delete the separate body `Rectangle`
  (`tint 0.025`) so header and body share one surface. Keep the 1px divider
  at `Util.alpha(Color.foreground, 0.07)`.
- [ ] **Radius.** Replace `Math.min(4, Style.cornerRadius)` with
  `appearance.cardRadius`.
- [ ] **Title weight.** `font.weight: Font.DemiBold` and
  `font.pixelSize: Style.font.body`, matching `DockMonitorLabel`.
  Title color is `Color.foreground` when expanded or focused, and
  `Util.alpha(Color.foreground, 0.85)` when collapsed.
- [ ] **Header order (per canvas comment).** Icon, title, drag grip, badge,
  collapse. The badge anchors to `collapseButton.left`; the grip sits left of
  the badge. The badge stays in place when the grip appears.
- [ ] **Drag grip.** Change the icon to `grip-vertical`. Opacity is 0 unless the
  card is hovered, has active focus, or a drag is active. It keeps its hit
  area, so dragging still works when it is invisible. Keep
  `Accessible.name`.
- [ ] **Collapse glyph.** Change to `chevron-down` with `rotation: collapsed ? 0 : 180`,
  so `chevron-right` in window rows keeps meaning "open".
- [ ] **Section header.** Replace the custom "Widgets" `Text` with
  `Ui.PanelSectionHeader { text: "WIDGETS" }`. Replace the "Add/Manage" text
  button with `Ui.Button { iconText: "" }` containing a `plus` `WidgetIcon`,
  the same pattern as the card's collapse button. Keep
  `tooltipText`/`Accessible.name` "Add or manage Widgets".
- [ ] **PINNED parity.** Switch the PINNED label to `Ui.PanelSectionHeader` too,
  so both section labels come from one native primitive.
- [ ] **Inset.** Section labels, card icon and body content share one left inset,
  `workspaceCardInset + Style.space(4)`.
- [ ] Tests: card fill equals `appearance.monitorFill`; badge x is greater than
  grip x; grip opacity is 0 when idle and 1 on focus; the collapse button
  rotation; the section header is a `PanelSectionHeader`; Add/Manage keeps
  its accessible name.

## Slice B: WidgetKit token alignment

Files: `components/widgets/WidgetText.qml`, `WidgetFormField.qml`,
`WidgetStat.qml`, `WidgetTextInput.qml`, `WidgetSemanticPalette.qml`,
`WidgetSparkline.qml`, `DemoWidgetDisplayBody.qml`,
`docs/WIDGET_COMPONENTS.md`, the gallery.

- [ ] Muted text: `Util.alpha(Color.foreground, 0.62)` becomes `Color.muted`
  everywhere in the kit. Verify contrast of `Color.muted` on `monitorFill`
  across at least two themes. If it fails 4.5:1, keep the alpha and document
  why.
- [ ] Radii: `WidgetStat` and `WidgetTextInput` use
  `Math.min(3, Style.cornerRadius)`, never more than the card radius.
- [ ] `WidgetStat`: fill only (`Util.alpha(Color.foreground, 0.04)`), no border.
- [ ] `WidgetSemanticPalette.danger` maps to `Color.urgent`. Success and warning
  stay custom because Omarchy has no such tokens; document that.
- [ ] `WidgetSparkline`: optional `fillOpacity` (default 0.10) area under the line.
  This adds a property and removes nothing.
- [ ] Demo Display body: status `semantic: "info"`, reference badge neutral, and
  the Memory meter turns warning only at 85% or more. This shows the rule
  "hue only when it needs attention" in the gallery.
- [ ] `docs/WIDGET_COMPONENTS.md`: add the semantic-color rule and the note that
  the kit follows sidebar surface tokens.
- [ ] Tests: `tests/test_widgetkit_structure.mjs` and the gallery keep passing;
  add an assertion that no kit file hardcodes `0.62` muted alpha.

## Slice C: Split-scroll layout

Files: `components/DockSidebar.qml`, `components/DockSidebarViewport.qml`,
`components/DockSidebarWidgetArea.qml`, `components/DockSidebarWidgetModel.js`,
`components/DockSidebarKeyboard.qml`, `docs/SIDEBAR_WIDGETS.md`,
`docs/SIDEBAR.md`, tests.

### C1. Pure split function

Add `sidebarSplitLayout(input)` to `DockSidebarWidgetModel.js`:

```text
input:  available A, hierarchyContent H, widgetHeader Wh, widgetContent W,
        widgetCount, minHierarchy Hmin, minWidgets Wmin, capRatio r,
        requestedSplit s (null = automatic)
output: { hierarchyHeight, widgetHeight, blankHeight }

if widgetCount == 0 or rail:  hierarchy = min(H, A); widgets = 0
wanted  = Wh + W
cap     = s ?? r * A
cap     = clamp(cap, Hmin, A - Wmin)
hier    = min(H, max(cap, A - wanted))      // unused widget space flows back
widgets = min(wanted, A - hier)
blank   = A - hier - widgets                // background drag surface
```

Defaults: `r = 0.55`, `Hmin` = monitor header + 2 rows, `Wmin` = `Wh` + one
collapsed card. When `A < Hmin + Wmin`, the hierarchy keeps `Hmin` and Widgets
get the rest; the header is always visible.

- [ ] Node table tests: no widgets; short hierarchy (widgets get most); tall
  hierarchy (capped, scrolls); tiny widgets (hierarchy reclaims space); tiny
  screen below both minimums; requested split clamped at both ends.

### C2. Detach Widgets from the hierarchy ListView

- [ ] Remove `contentTail`, `contentTailItem`, `contentTailDragPoint`,
  `contentTailAutoScrolled` and the `footer:` host from `DockSidebarViewport`,
  plus their restore/anchor hooks (`onHeightChanged` restore requests).
- [ ] `DockSidebar` places, between `controls` and `pinnedStrip`: the
  `sidebarViewport` (height = `hierarchyHeight`), then `DockSidebarWidgetArea`
  (height = `widgetHeight`), then the blank region. The viewport's own
  `blankRegion` stays valid inside its allocated height.
- [ ] Feed `H` from `listView.contentHeight` and `W` from the card column's
  `implicitHeight`. Guard against a binding loop: heights derive from content
  sizes only, never from each other's allocated height.

### C3. Widget area owns its scroll

- [ ] `DockSidebarWidgetArea`: the section header sits outside, followed by a
  `Flickable` (`clip`, `boundsBehavior: StopAtBounds`, vertical only)
  containing the card column. Use the same scrollbar geometry as the viewport
  (`scrollGutter`, `scrollBarOutset`).
- [ ] Add a bottom fade (`Util.alpha(Color.background, 0)` →
  `Color.background`, about 28px, no input), shown only when
  `contentY < contentHeight - height`.
- [ ] Rebind `itemIntersectsViewport`, `presentationClipItem` and
  `presentationRevision` from `viewport.listView.contentY` to the new
  Flickable.
- [ ] Reorder drag: move the edge auto-scroll that used `contentTailDragPoint`
  into the Widget area, scrolling its own Flickable. Insertion boundaries stay
  among Widget cards only.
- [ ] Popup anchors: the "scrolled-out anchor closes" rule now tests the Widget
  Flickable's viewport.

### C4. Input and focus

- [ ] Wheel: the two scroll areas are siblings, not nested, so neither passes
  scrolling to the other. Check that in-widget scroll areas (WidgetList and
  similar) still stop at their bounds, and record the behavior at bounds.
- [ ] Keyboard: from the last hierarchy row, Tab moves to the first Widget card
  (and Backtab back); document it in `docs/SIDEBAR_INTERACTIONS.md`. A card
  that gains focus scrolls into view in the Widget Flickable.
- [ ] Header double-click: `preventStealing: false` still lets the Widget
  Flickable take vertical drags.
- [ ] Blank region: the `DockPositionDragSurface` covers `blankHeight` below the
  Widget area when the layout leaves one. Otherwise only the hierarchy's own
  blank tail qualifies, as today.

### C5. Contract docs and tests

- [ ] Rewrite `docs/SIDEBAR_WIDGETS.md` "Shared-scroll layout" as "Split-scroll
  layout", including the C1 formula and the reasons it differs from the
  FDM-967 footer.
- [ ] Update `docs/SIDEBAR.md` viewport ownership.
- [ ] `tests/runtime/sidebar.qml`: revive "widget scrolling moved windows" against
  the new Flickable, and add the reverse (hierarchy scroll does not move
  Widgets).
- [ ] `tests/test_sidebar_widgets.mjs`: replace shared-scroll source assertions,
  and assert the viewport no longer declares `contentTail`.
- [ ] `tests/tst_sidebarwidgets.qml`: lifecycle counts do not change across
  split/resize reflows (no extra acquire/release).

## Slice D (optional): Adjustable split

- [ ] A drag handle on the top edge of the Widget section header (a 28×3 bar that
  shows on hover, `row-resize` cursor, `Accessible.name` "Resize Widgets
  area"). Double-click resets to automatic.
- [ ] New setting `sidebarWidgetSplit`: `0` = automatic, otherwise a ratio from
  `0.2` to `0.8` of available height. Wire it through `dock.json`, the schema,
  `DockModel.js` normalization (stepped number, like `sidebarExpandedWidth`),
  `CONFIGURATION.md`, README, the inventory tests and `test_sidebar_widget_config.py`.
- [ ] Persistence copies `docs/SIDEBAR_RESIZE.md`: live drag is temporary
  geometry, and one release submits one setting through the host intent.
  Runtime clamping never overwrites the stored preference.
- [ ] Keyboard: with the handle focused, Up and Down move the split in steps, and
  Enter resets it.

## Validation (every slice)

Run the full local gate from `AGENTS.md`: `./scripts/run` smoke, `bash -n`,
`qmltestrunner`, `omarchy plugin validate .`, `qmllint`, `git diff --check`, plus
the node/python suites listed in `docs/SIDEBAR_WIDGETS.md`. Then take KVM guest
screenshots at two monitor heights (for example 1080 and 768) with 0, 1 and 4
Widgets, with the hierarchy short and long, on both sidebar edges. Compare them
with the canvas boards.

## Delivery

Three PRs, stacked per `docs/DELIVERY.md`: **A+B** (visual polish, low risk),
then **C** (layout contract change), then optionally **D**. A+B can ship even if
C needs more iteration.

## Decisions (defaults used above; change before starting C)

1. Hierarchy cap `r = 0.55` of available height.
2. Minimums: hierarchy = monitor header + 2 rows; Widgets = header + 1 collapsed card.
3. Slice D (adjustable split) is a follow-up, not v1.
4. PINNED also moves to `Ui.PanelSectionHeader`, whose color may be slightly
   different from today's `Color.muted`.
5. Warning hue for meters starts at 85% in the demo; this is a gallery
   convention, not a kit rule.
