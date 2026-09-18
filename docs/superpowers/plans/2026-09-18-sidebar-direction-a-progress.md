# SmartDock Direction A — progress

## Snapshot identity

- **Base SHA:** `8508e8a77592d48843a59c85b518e0d737ad2992` (`8508e8a`)
- **Base message:** `fix(FDM-968): keep interactionBusy while a widget popup is open`
- **Source (READ ONLY, live):** `/home/admin/Projects/smart-omarchy-dock/.worktrees/fix-fdm-968-sidebar-polish` on `fix/fdm-968-sidebar-polish`
- **Target:** `/home/admin/Projects/smart-omarchy-dock/.worktrees/feat-fdm-968-sidebar-direction-a` on `feat/fdm-968-sidebar-direction-a`
- **Main checkout not used as base.**

## Phase 1 result

Created isolated worktree from source HEAD, transferred combined tracked dirty state via `git diff --binary HEAD | git apply --binary`, copied approved untracked files only. Equivalence verified; source content unchanged during copy. No commits, push, merge, UI work, live switch, or config edits.

## Inherited modified files (tracked dirty vs HEAD)

- DockHost.qml
- README.md
- assets/lucide/ATTRIBUTIONS.md
- components/DockAppPicker.qml
- components/DockBrowserActivityModel.js
- components/DockBrowserProfileService.qml
- components/DockConfigModel.js
- components/DockContextMenu.qml
- components/DockControl.qml
- components/DockIconModel.js
- components/DockModel.js
- components/DockSidebar.qml
- components/DockSidebarController.qml
- components/DockSidebarInteractionModel.js
- components/DockSidebarModel.js
- components/DockSidebarResizeHandle.qml
- components/DockSidebarRow.qml
- components/DockSidebarRowInput.qml
- components/DockSidebarViewport.qml
- components/DockSidebarWidgetArea.qml
- config/dock.json
- config/settings-schema.json
- docs/AGENT_CONFIGURATION.md
- docs/CLI_REFERENCE.md
- docs/CONFIGURATION.md
- docs/SIDEBAR.md
- docs/browser-activity.md
- provider/browser-profiles/browser_profile_provider.py
- provider/browser-profiles/tests/test_browser_profile_provider.py
- tests/check_contextual_actions.sh
- tests/runtime/sidebar.qml
- tests/test_context_menu_regressions.mjs
- tests/test_desktop_model.mjs
- tests/test_sidebar_geometry.mjs
- tests/test_sidebar_host.mjs
- tests/test_sidebar_model.mjs
- tests/tst_sidebarcontroller.qml
- tests/tst_sidebarresize.qml
- tests/tst_sidebarwidgets.qml

## Inherited untracked files (copied into target)

- assets/lucide/earth.svg
- components/DockSidebarPinnedStrip.qml
- docs/browser-tabs.md
- tests/test_browser_tabs_model.mjs
- tests/test_sidebar_entry_metadata.mjs
- tests/test_sidebar_polish_behaviors.mjs

## Source untracked inspected but not copied

- `.playwright-mcp/` (evidence / tooling artifacts)
- `live-evidence/` (runtime screenshots / layer dumps)
- `urllib.request` (spurious artifact)

## Equivalence evidence

- Tracked `git diff --binary HEAD` SHA-256 identical: `19b7a04795553cd3d409b126a840231f8e8823473e54f77d286ce38e63ed8d94`
- Modified porcelain lists match
- Copied untracked file SHA-256 hashes match source
- Source HEAD remained `8508e8a…` and dirty diff hash unchanged during transfer

## Constraints (hard rules for Direction A)

- No Hypruse / computer-use / browser automation / screenshots / GUI / QEMU / KVM
- No live switch / restart / second dock
- No user config edits
- No commits / push / merge
- No edits to source / live worktree
- No other agents
- Preserve all inherited changes
- Coordinator sends one phase at a time — do not invent a full plan here

## Phase 1 checks run in target

- `node tests/test_sidebar_model.mjs` — PASS (`SB-02 …: PASS`, exit 0)
- `git diff --check` — PASS (exit 0)

## Later phases

Phase 1–10 complete (source-only final check). Awaiting user visual/runtime acceptance via handoff.

## Phase 2 result

Dual expanded/rail projections on the controller. `refresh` builds DesktopModel once, projects with `collapsed:false` (canonical `projection`) and `collapsed:true` (`railProjection`) from the same snapshot/registry/folds/settings/browserTabs; empty/disappeared mode clears both. `projectionFor(collapsed)` selects the active view. `indexRowsByKey(expanded, optionalRail)` unions rows+launchers with expanded winning duplicates; one-arg callers remain valid. Viewports expose `viewProjection`/`visibleRows` from `panelCollapsed` and drive list model, scroll helpers, hit geometry, focus lookup, enterNavigation, and keyboard traversal from `visibleRows`; delegates bind `row: modelData`. Actions still validate via union `rowsByKey`. `syncBadges` uses the owning panel's projection and resyncs on collapse. Collapse remaps hidden browser-tab focus to owning window and application-group focus to a represented child window, restoring keyboard focus only when the viewport already owns it (per-panel collapse).

### Phase 2 files touched

- components/DockSidebarModel.js (`indexRowsByKey` union, `unionProjectionRows`, `remapFocusKey`)
- components/DockSidebarController.qml (`railProjection`, `projectionFor`, dual project in `refresh`)
- components/DockSidebarViewport.qml (`viewProjection`/`visibleRows`, focus sync on collapse)
- components/DockSidebarKeyboard.qml (traverse `visibleRows`)
- components/DockSidebar.qml (panel projection badges + collapse resync)
- tests/test_sidebar_model.mjs (rail-despite-fold + union lookup assertions)
- tests/test_sidebar_entry_metadata.mjs (union lookup assertions)
- tests/tst_sidebarkeyboard.qml (`visibleRows` on viewport fixture)

### Phase 2 checks

- `node tests/test_sidebar_model.mjs` — PASS
- `node tests/test_sidebar_entry_metadata.mjs` — PASS
- `node tests/test_browser_tabs_model.mjs` — PASS (exit 0)
- `git diff --check` — PASS

### Phase 2 limitations

- No UI restyling, rail width, card metadata, or scroll-state redesign (later phases).
- Pinned shelf still reads expanded `projection.launchers` (unchanged by design this phase).
- No GUI / live dock / Hypruse verification; user will visually test.
- Shared `focusedRowKey` / `scrollAnchor` remain controller-global; remapping is pane-local via each viewport's `panelCollapsed` + `visibleRows`.

## Phase 3 result

Explicit section/tree metadata on the final visible row list, plus one shared row-height helper. Flat ListView and action keys unchanged; no card painting or appearance rewrite.

### Helper signature

`InteractionModel.sidebarRowMetrics(row, collapsed, rowHeight, space, hasAlert=false)`
→ `{ contentHeight, gapBefore, gapAfter, height, contentY }`

`estimatedSidebarRowHeight(...)` returns `sidebarRowMetrics(...).height`.

`InteractionModel.isNumericBadgeToken(severity)` — true for `count:<n>[:…]` with n>0.

`InteractionModel.sidebarRowHasNumericAlert(collapsed, badgeSeverity)` — `collapsed && isNumericBadgeToken(…)`.

Row and Viewport both pass `sidebarRowHasNumericAlert(collapsed, controller.badgeForRow(row))` into metrics so rail 58px stays consistent for offscreen prefixes/scroll.

**Content baselines** (then `space()`): monitor 48 expanded / 32 rail; workspace 30 both; app/window/tab/launcher 28 expanded; rail window 36 or 58 when `hasAlert`; section 22.

**Font contract:** `fontFloor = max(0, rowHeight - space(12))`, then `contentHeight = max(baseline, fontFloor)`. Default viewport `rowHeight≈34` → floor 22, so expanded 28 is **not** forced back to 34. Larger configured fonts can grow content.

**Gaps:** tokens on rows from `annotateTreeAndSpans`: `layoutGapBefore` `"monitor"`→8 (between monitors, not before first), `"workspace"`→4 (between workspaces), `"children"`→4 (workspace header→first depth-1 child). End padding via `layoutPadWorkspaceEnd` / `layoutPadMonitorEnd` (+5 each into `gapAfter`). Same row may carry both end pads (10) when it closes the last workspace of a monitor.

### Row tree metadata (per visible row)

| Field | Meaning |
| --- | --- |
| `monitorKey` | Owning monitor row key (empty under unassigned) |
| `workspaceKey` | Owning workspace row key |
| `parentKey` | Actual visible parent key (workspace / app / window / section) |
| `treeDepth` | 0 headers; apps/sole/rail windows 1 under workspace; grouped windows 2; tabs `parent.treeDepth+1` |
| `isLastSibling` | Last among **visible** siblings sharing `parentKey` |
| `ancestorContinues` | `boolean[]` outer→inner: whether each depth≥1 ancestor stem continues past this row |

### `sectionSpans[]` records

`{ kind: 'monitor'|'workspace', key, firstKey, lastKey, focused, endPadding }`

- Workspace span: header through visible descendants (incl. browser tabs); empty workspace still spans header-only.
- Monitor span: heading through last workspace/descendant; `endPadding: 5` owned inside the span.
- Inter-section gaps (monitor 8 / workspace 4) live on the **next** row’s `layoutGapBefore` and are **excluded** from span geometry.
- Unassigned keeps `section:unassigned`; no invented monitor span.

### Exact span Y for painters (phase 4)

Let `rowY(key)` be the ListView y of that row (continuous heights; no guessed offsets). Metrics fields from `sidebarRowMetrics` on that row:

- **spanTop** (monitor or workspace): `rowY(first) + first.contentY`  
  (excludes the first row’s own `gapBefore` / inter-section gap)
- **workspaceBottom**: `rowY(last) + last.contentY + last.contentHeight + space(5)`  
  (workspace `endPadding` only — do **not** add monitor’s +5 when the same last row also has `layoutPadMonitorEnd`)
- **monitorBottom**: `rowY(last) + last.contentY + last.contentHeight + last.gapAfter`  
  (`gapAfter` already includes workspace5 + monitor5 when both flags are set on that last row)

Following row’s inter-section `gapBefore` is never part of either span.

### Phase 3 files touched

- `components/DockSidebarModel.js` (`emptyProjection.sectionSpans`, `annotateTreeAndSpans`)
- `components/DockSidebarInteractionModel.js` (`sidebarRowMetrics`, `sidebarRowHasNumericAlert`, gap token helpers, `estimatedSidebarRowHeight`)
- `components/DockSidebarRow.qml` (delegate consumes shared metrics / `contentY`)
- `components/DockSidebarViewport.qml` (estimator uses same alert helper + `badgeForRow`; still `visibleRows` from phase 2)
- `tests/test_sidebar_model.mjs`
- `tests/test_sidebar_polish_behaviors.mjs`

### Phase 3 checks

- `node tests/test_sidebar_model.mjs` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `git diff --check` — PASS

### Phase 3 limitations

- No guide/card drawing (phase 4+).
- No GUI / live dock / Hypruse; user will visually test.

## Phase 4 result

Grouped card surfaces + monitor headings on the flat ListView. Omarchy `omarchy 4.0.3-1` (no Git revision) inspected: `Ui/{BorderSurface,Button,PanelActionButton}.qml`, `Commons/{Color,Style,Border,Util}`, first-party `BorderSurface` usage in `plugins/panels/tailscale`. Outer panel material/blur unchanged. Flat list + actions preserved.

### Appearance object (`DockSidebar.sidebarAppearance`)

Theme-reactive `QtObject` passed `viewport.appearance` → `row.appearance`:

| Token | Value |
| --- | --- |
| `monitorFill` | `Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035))` |
| `workspaceFill` | `Qt.darker(Color.background, 1.04)` |
| `workspaceHoverFill` | `Qt.tint(workspaceFill, Util.alpha(Color.foreground, 0.09))` |
| `activeMonitorBorder` | `Util.alpha(Color.accent, 0.22)` |
| `activeWorkspaceBorder` | `Util.alpha(Color.accent, 0.50)` (reserved; no workspace perimeter border this phase) |
| `cardRadius` | `Math.min(3, Style.cornerRadius)` |

### Section chrome (viewport)

- `sectionSpans` from `viewProjection`; painters use phase-3 Y contract via `sectionSpanRect` / `contentRowY` (live `item.y` else `originY` + shared-metrics prefix, including numeric-rail alert heights).
- Cards parented to `list.contentItem` so they scroll; monitor z below workspace z below rows; `enabled: false`; expanded only; no nested ListViews.
- Workspace cards inset `Style.space(5)` horizontally inside the monitor card.
- Focused monitor only: 1px `activeMonitorBorder`. Workspace: no active perimeter; faint 1px bottom separator at card end.
- `hoveredWorkspaceKey: ""` exposed; chrome reads it for `workspaceHoverFill` but no hover input yet.
- Empty workspace/monitor spans and unassigned (no invented monitor span) handled by existing span metadata.

### Monitor heading

- Nerd glyph replaced with vendored Lucide `assets/lucide/monitor.svg` + ATTRIBUTIONS; `DockLucideIcon` 24px expanded.
- Name `Style.font.title`; connector `Style.font.caption` muted; real names preserve connector; heading still 48px metrics.
- Inter-monitor hairline removed (card gap owns separation).
- Expanded connected-display strip from `projection.monitorSections` order; highlights **this** `sectionIndex` only; ≤4 tiny rects else ordinal `N/M`; full name+connector tooltip; no strip in rail.

### Phase 4 files touched

- `components/DockSidebar.qml` (appearance object + pass-through)
- `components/DockSidebarViewport.qml` (section chrome, span geometry, `hoveredWorkspaceKey`)
- `components/DockSidebarRow.qml` (Lucide monitor, typography, display strip; hairline removed)
- `assets/lucide/monitor.svg` (new)
- `assets/lucide/ATTRIBUTIONS.md`
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 4 checks

- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `node tests/test_sidebar_model.mjs` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `git diff --check` — PASS

### Phase 4 limitations

- No row guides, alerts, footer, or rail-width changes (later phases).
- Workspace hover fill binding is ready; hover input not wired (`hoveredWorkspaceKey` stays `""`).
- No GUI / live dock / Hypruse / `./scripts/run`; user will visually test.

## Phase 5 result

Workspace badge-only identity, whole-card hover, grab cursors, continuous tree guides, and selection/icon polish. No alerts/state/footer/rail-width changes. Flat list + actions preserved.

### Workspace badge

- `InteractionModel.workspaceBadgeLabel(identity)`: explicit `id:` / `name:` prefixes only (`id:3`→`3`, `name:Work`→`Work`, `id:10`→`10`). No first-digits regex / `slice(0,2)`.
- Expanded: badge is the only workspace identity (no `workspaceTitle` text, no active dots, no workspace chevron).
- Min width `max(24, text+padding)`; long names elide to available width; full label via tooltip/`accessibleLabel`.
- Active: opaque `Color.accent` text + 1px `Util.alpha(Color.accent, 0.50)` border. Workspace card still has no active perimeter (phase 4).

### Whole-card hover + grab cursor

- Workspace header `DockSidebarRowInput` sets `viewport.hoveredWorkspaceKey` (phase-4 chrome already reads it).
- Clears on leave, destruction, reassignment, cancel, `cancelInputs`, and panel collapse/mode change.
- `Qt.OpenHandCursor` on heading; `Qt.ClosedHandCursor` when pressed/`dragOwned`. Reuses existing drag controller.
- Input covers content only (excludes gapBefore/gapAfter) with workspace-card inset margins; no parent MouseArea.

### Tree guides

- Pure helpers: `sidebarTreeGuideLayout` / `sidebarTreeStemX` / `sidebarTreeIconX`.
- Geometry: workspace left = `viewport.workspaceCardInset`; badge at +8; guide0 at +20; depth-1 icon at guide0+12; +24 per deeper depth.
- Uses `treeDepth` / `isLastSibling` / `ancestorContinues`. Ancestor stems only when continues; own stem stops at mid if last sibling; horizontal branch ends before art.
- Guides parented outside the fill layer; span first-child `children` 4px gap; hidden in rail; not drawn through inter-workspace/monitor gaps.

### Icons / fills / chevrons

- Expanded app/window icons 18px; tabs 14px; titles `Style.font.bodySmall` vertically centered.
- Focused window: accent fill 0.18 + 2px rail. Active browser tab: weaker fill 0.10, no rail. Hover/press composition preserved via `composeRowFill`.
- Row fills inset to workspace card; do not cover monitor outline.
- Chevron rightmost only when `expandable === true` (apps) or `tabsExpandable` (windows). Fold behavior unchanged.

### Phase 5 files touched

- `components/DockSidebarInteractionModel.js` (badge + guide helpers)
- `components/DockSidebarRow.qml`
- `components/DockSidebarRowInput.qml`
- `components/DockSidebarViewport.qml` (hover clear on cancel/collapse)
- `tests/test_sidebar_polish_behaviors.mjs`
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 5 checks

- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `git diff --check` — PASS

### Phase 5 review corrections

1. **Duplicate handler:** consolidated the two `onPanelCollapsedChanged` handlers in `DockSidebarViewport.qml` into one (clear hover + `syncFocusForProjection` + `bumpSectionChrome`). No other duplicate same-object handlers in touched QML.
2. **Hover clear:** `DockSidebarRowInput` keeps `lastPublishedWorkspaceKey`; clear uses that key and only blanks viewport if it still owns it. Works when `workspaceHeader` is already false or `rowKey` changed. Cancel/reassign/destroy clear without reasserting; later hover-enter republishes.
3. **Empty workspace stem:** header guide stem only when `row.target.applications.length > 0` (`workspaceHasChildren`); no fake branch on empty cards.

### Phase 5 post-correction checks

- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `git diff --check` — PASS
- `qmllint` on Viewport/Row/RowInput — exit 0; **no semantic Errors**. Remaining Warnings are import-environment (`qs.Commons` / `qs.Ui` unresolved → cascade unqualified/missing-type), not duplicate-handler or logic defects.

### Phase 5 limitations

- No alerts, footer, rail-width, or state strip (later phases).
- No GUI / live dock / Hypruse / `./scripts/run`; user will visually test.

## Phase 6 result

Window state indicators + sidebar alerts via existing providers/settings/actions (no new provider, no Herdr live-agent integration). Footer/rail-width untouched.

### Helper contracts

`controller.attentionForRow(row)` → `{ count, countVisible, text, severity, serviceId, serviceLabel, muted }`
- Empty default: `count:0`, `countVisible:false`, `severity:"none"`, empty service fields, `muted:false`.
- `text` is `count>99 ? "99+" : String(count)` (QML wraps with parentheses).
- Respects `attentionBadgesEnabled` + `launcherBadgeMode` via `BadgeModel.applicationBadgePresentation`.
- Browser **window** / folded app: `ActivityModel.rawRowsForAddresses` + `tracker.browserCountFor` (address-scoped; not launcher aggregate when browser authoritative).
- Browser **tab**: `ActivityModel.activityForTarget(activities, targetId, windowAddress)` on RAW `service.activities` (not `activityRowsForAddresses` / dedup winners). Own count remains when service is muted.
- Expanded application groups return empty (children own alerts).
- Non-browser: `BadgeModel.attentionFromBadgeToken(badgeForRow(row))` preserves classic ownership/severity.

`controller.windowStateForRow(row)` → `{ fullscreen, pinned, minimized }` (window rows only)
- Fullscreen: `WindowModel.handleForToplevel` + `FullscreenModel.isManagedFullscreen(lastIpcObject)`.
- Pinned: normalized `settings.pinned` membership (not compositor sticky).
- Minimized: `row.minimized`.

`ActivityModel.activityForTarget` / `rawRowsForAddresses`; `BadgeModel.decodeApplicationBadgeToken` / `emptyAttention` / `attentionFromPresentation` / `attentionFromBadgeToken`.

`InteractionModel.sidebarRowHasNumericAlert(collapsed, countVisible|legacyToken)` — row + viewport both pass `attentionForRow(...).countVisible`.

### UI

- Expanded order: title → fullscreen/pin/minus → `(count)` / severity dot → eye (tabs) → chevron last.
- Rail: state icons hidden (meanings in tooltip/a11y); hierarchy numeric icon-overlay badge removed (classic dock + pin strip keep `DockApplicationBadge`).
- Tab eye: Lucide eye / eye-off; service-wide mute via `host.toggleBrowserActivityMute`; hover/keyboard focus; stays visible when muted; rejected writes → `mutationFeedback`.
- Keyboard: Tab reaches eye (`alertControlKey`); Enter/Space mute before row activate; Shift+Tab leaves eye.
- Motion: `Translate` on `fillLayer` + `content` only (guides fixed); 3px right, 700ms/cycle, 2 loops; positive `attentionDisplayCount` increase after prime; reset on row reassignment; disabled when `interfaceAnimationsEnabled=false` or during row drag.
- `InteractionModel.attentionMotionShouldHalt(animationsEnabled, rowDragActive)` — in-flight halt gate. `haltAttentionMotion()` stops animation and zeroes `attentionNudgeX` without clearing primed/lastCount (no false replay on resume).

### Phase 6 files touched

- `components/DockBadgeModel.js`
- `components/DockBrowserActivityModel.js`
- `components/DockApplicationBadge.qml`
- `components/DockSidebarController.qml`
- `components/DockSidebarRow.qml`
- `components/DockSidebarKeyboard.qml`
- `components/DockSidebarViewport.qml`
- `components/DockSidebarInteractionModel.js`
- `tests/test_sidebar_polish_behaviors.mjs`
- `tests/test_browser_tabs_model.mjs`
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 6 checks

- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `node tests/test_browser_tabs_model.mjs` — PASS
- `node tests/test_sidebar_entry_metadata.mjs` — PASS
- `python3 -m unittest discover -s tests -p test_sidebar_qml_syntax.py` — PASS
- `git diff --check` — PASS
- Duplicate same-object property/handler scan on touched QML: no new same-object duplicates (`onClicked`×2 are fold vs tabsFold; viewport `geom`×2 pre-existing)

### Phase 6 review correction

In-flight `attentionMotion` now stops immediately when animations disable or row drag starts (`haltAttentionMotion` + `attentionMotionShouldHalt`); count history preserved so resume cannot false-replay.

### Phase 6 post-correction checks

- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `git diff --check` — PASS

### Phase 6 limitations

- No footer restyle, rail-width change, blur/right-click config, or Herdr live-agent alerts (deferred).
- No GUI / live dock / Hypruse / `./scripts/run`; user will visually test.
- Hierarchy rail no longer paints icon-overlay badges; taller 58px rail height still follows `countVisible`.

## Phase 7 result

Direction A collapsed rail chrome on existing `railProjection` / `visibleRows` (no second model). Flat list + actions preserved.

### Geometry

`SidebarModel.geometry`: preferred rail **72**, `railWidth = min(72, W)`; expanded envelope floor also **72** (`maximum = min(W, max(72, min(480, floor(0.40×W))))`). Expanded width preference and clamp-to-screen behavior unchanged. Docs `SIDEBAR.md` / `SIDEBAR_RESIZE.md` and geometry/host/runtime expectations updated from 56→72.

### Section cards in rail

`sectionChromeHost.visible: true` always (was expanded-only). Same `sectionSpans`, appearance fills/borders, workspace inset, and shared row metrics.

### Rail row chrome (`DockSidebarRow`)

- Monitor: centered 16px Lucide `monitor` + ordinal `sectionIndex+1`; full name/connector via tooltip/`accessibleLabel`; no display strip.
- Workspace: centered canonical `workspaceBadgeLabel` (elides when clamped; “Work” when it fits); active accent border 50% opacity; whole-card hover + Open/ClosedHand unchanged.
- Window: 22px app icon; column top pad 10 / gap 5 / alert `(count)` 16px line + metrics bottom 5 when `attention.countVisible`; heights 36 / 58 via `sidebarRowMetrics` + `attentionForRow().countVisible`. Focused fill + 2px accent rail also in rail. Urgency-only stays non-numeric (a11y/tooltip).
- Titles, tabs, folds, state icons hidden in rail; activation / menus / keyboard / drag unchanged.
- Row fills inset to workspace cards in rail too (`insideWorkspaceCard` no longer gated on expanded).

### Pinned strip

Hidden in rail with `implicitHeight`/`height` 0, `visible`/`enabled` false; panel `bottomMargin` 0 so no blank pin gap. Applications remains centered; Trash/widgets unchanged. Header/footer redesign deferred.

### Phase 7 files touched

- `components/DockSidebarModel.js` (rail 72 geometry)
- `components/DockSidebarRow.qml`
- `components/DockSidebarViewport.qml` (section chrome in rail)
- `components/DockSidebar.qml` (pin gap collapse)
- `components/DockSidebarPinnedStrip.qml`
- `tests/test_sidebar_geometry.mjs`
- `tests/test_sidebar_model.mjs`
- `tests/test_sidebar_host.mjs`
- `tests/runtime/sidebar.qml`
- `docs/SIDEBAR.md`
- `docs/SIDEBAR_RESIZE.md`
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 7 checks

- `node tests/test_sidebar_geometry.mjs` — PASS
- `node tests/test_sidebar_model.mjs` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `node tests/test_sidebar_host.mjs` — PASS
- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `git diff --check` — PASS

### Phase 7 limitations

- No header/footer redesign (next phase).
- No GUI / live dock / Hypruse / `./scripts/run` / full validation gate; user will visually test.
- `compactMonitorRailLabel` helper retained for tests but unused by rail UI.

## Phase 8 result

Direction A header + footer/pinned composition. Hierarchy/model/actions unchanged. Rail pin shelf still zero-height (phase 7).

### Header (44px)

- Brand: “Smart” `Color.foreground` + “Dock” `Color.accent`, `Style.font.title`, no subtitle.
- Collapse `Ui.Button` 30×30; expanded right-aligned; rail centered with widget overflow when present.
- Preference/error status text retained under the header when expanded.
- Collapse tooltip, a11y name, and `requestCollapse` preserved.

### Footer / pinned (appearance reuse)

- `sidebarAppearance.workspaceFill` / `workspaceHoverFill` / `cardRadius` (≤3) drive pin shelf + Applications blocks — no second palette.
- Pinned shelf expanded only: 28px heading (“Pinned” + plus); plus moved out of icon `Flow` into heading; `addPinButton` / `objectName: sidebar-pin-strip-add` / `pinStripOwned` / picker lifecycle unchanged. Empty list still shows heading + plus.
- Pin cells 36px, icons 26px, Flow gap 6px; individual outlined tiles removed; shelf is the single `BorderSurface` block. Artwork, overrides, profile badges, context menu, keyboard/a11y, focus-or-launch, and strip-owned menus preserved.
- Applications: 36px, same fill/radius; Lucide `layout-grid` 21px + chevron expanded; rail centers icon and hides label/chevron. Left launches `controlCommand`; right-click opens pin picker only (never desktop launcher). No footer Add-pin control.
- Trash, widgets, resize handle, popup anchors preserved.

### Phase 8 files touched

- `components/DockSidebar.qml`
- `components/DockSidebarPinnedStrip.qml`
- `tests/test_sidebar_qml_syntax.py` (add `DockSidebarPinnedStrip.qml` to current-surface inventory)
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 8 checks

- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `qmlformat` on `DockSidebar.qml` + `DockSidebarPinnedStrip.qml` — PASS
- `git diff --check` — PASS

### Phase 8 limitations

- No GUI / live dock / Hypruse / `./scripts/run` / full validation gate; user will visually test.
- Applications uses `BorderSurface` + handlers (not `Ui.Button`) so idle/hover can bind appearance fills; Trash remains `Ui.Button`.
- Stop after phase 8; no further phases in this worker.

## Phase 9 result

Independent scroll session-memory + thin native vertical scrollbar. Flat ListView hierarchy unchanged. No model/actions/design rewrite; no filesystem/config persistence; no new user setting.

### Scroll state shape

Controller `scrollStates: ({})` keyed by `JSON.stringify([panelConnector, collapsed ? "rail" : "expanded"])`.

Each entry: `{ anchor: { key, offset }, keys: [previous visible keys] }`.

Pure helpers in `DockSidebarModel.js`: `scrollMemoryKey`, `emptyScrollState`, `readScrollState`, `writeScrollState`. Controller wrappers: `readScrollState` / `writeScrollState`. Removed obsolete single `scrollAnchor` property and its refresh recovery line.

### Callers migrated

| Site | Behavior |
| --- | --- |
| `captureAnchor` | Writes current connector×mode only when `scrollModeCollapsed === panelCollapsed` and not restoring/`pendingRestore` |
| `restoreAnchor` | Reads that mode’s entry; `recoverAnchor` + originY-aware clamps; writes recovered keys back |
| `onAboutToRefresh` / `onRefreshed` | Capture then `requestRestore` (mode’s own keys) |
| `onPanelCollapsedChanged` | Does **not** capture (rows already flipped); loads incoming mode keys; restores that mode |
| `onRowHeightChanged` / `onHeightChanged` / `onContentHeightChanged` / `Component.onCompleted` / destruction | Same restore/capture flow as before, via scrollStates; contentHeight arms `pendingRestore` before restore |
| Controller `refresh` | Focus still recovered against union rows; scroll no longer shared |

`scrollModeCollapsed` is the explicit previous/display mode gate so collapse never writes old coordinates into the new mode key (or new coords into the old key). Expanded vs rail stay independent per `panelConnector`.

### Scrollbar

`import QtQuick.Controls as Controls` on the single hierarchy ListView. Vertical `ScrollBar` in a 6px right gutter (`anchors.rightMargin` + reparented bar); horizontal `AlwaysOff`. Policy `AsNeeded` only when `contentHeight > height`. Thin `Color`/`Util.alpha` thumb; hover/press opacity. Panel already insets from the resize edge; gutter does not collide with the handle. Pointer/drag/keyboard/popup paths unchanged.

### Phase 9 files touched

- `components/DockSidebarModel.js` (scroll memory helpers)
- `components/DockSidebarController.qml` (`scrollStates`; remove `scrollAnchor`)
- `components/DockSidebarViewport.qml` (scrollbar + mode-keyed capture/restore)
- `tests/test_sidebar_model.mjs` (mode-key / multi-monitor independence assertion)
- `docs/superpowers/plans/2026-09-18-sidebar-direction-a-progress.md`

### Phase 9 checks

- `node tests/test_sidebar_model.mjs` — PASS
- `node tests/test_sidebar_polish_behaviors.mjs` — PASS
- `python3 -m unittest discover -s tests -p 'test_sidebar_qml_syntax.py'` — PASS
- `git diff --check` — PASS

### Phase 9 limitations

- No GUI / live dock / Hypruse / `./scripts/run` / full validation gate; user will visually test.
- Inactive mode’s stored keys are not re-recovered on every controller refresh; they recover via `recoverAnchor` on next enter of that mode.
- Stop after phase 9; no final check or extra review in this worker.

### Phase 9 review correction

`ListView.onContentHeightChanged` now arms `pendingRestore` then calls `requestRestore()` (still bumps section chrome). Guards: skip when `restoring`/`pendingRestore`; `requestRestore` returns early while `restoring`. Prevents rail alert 36→58 (above-viewport) from shifting the visible anchor without a controller refresh, without capturing drifted `contentY` into the mode key.

- `tests/test_sidebar_polish_behaviors.mjs` — assertion that contentHeight/heightMap growth (`36,36`→`36,58`) triggers `shouldRestoreScroll`
- Re-ran: `test_sidebar_model`, `test_sidebar_polish_behaviors`, `test_sidebar_qml_syntax`, `git diff --check`

## Phase 10 result (final source-only integration check)

Sole Cursor Auto worker; no subagents/reviewers. Source-only; no GUI / Hypruse / browser / KVM / live switch / restart / second dock / user config edits / commits / push / merge / deploy / `scripts/run` / full validation gate.

### Identity

| Field | Value |
| --- | --- |
| **Branch** | `feat/fdm-968-sidebar-direction-a` |
| **Worktree HEAD** | `8508e8a77592d48843a59c85b518e0d737ad2992` (`8508e8a`) |
| **Base HEAD (same)** | `8508e8a` — `fix(FDM-968): keep interactionBusy while a widget popup is open` |
| **Dirty status** | Tracked dirty preserved (all Phase 1 inherited + Phase 2–9 edits). Untracked: `earth.svg`, `monitor.svg`, `DockSidebarPinnedStrip.qml`, `docs/browser-tabs.md`, this progress doc, `test_browser_tabs_model.mjs`, `test_sidebar_entry_metadata.mjs`, `test_sidebar_polish_behaviors.mjs`. No commits. |

### Live `smartdock dev status` (read-only; unchanged)

```
Local source:
fix/fdm-968-sidebar-polish @ 8508e8a (uncommitted edits)
  /home/admin/Projects/smart-omarchy-dock/.worktrees/fix-fdm-968-sidebar-polish
```

Still points at the original fix-fdm live worktree, **not** this feature worktree. Live tree was not modified.

### Integration spot-check (Phases 2–9 contracts)

| Contract | Result |
| --- | --- |
| No obsolete `scrollAnchor` in `.qml`/`.js`/`.mjs` | PASS (only historical mentions in this progress doc) |
| Controller uses `scrollStates` + Model helpers | PASS |
| One hierarchy `ListView` (`DockSidebarViewport` `sidebar-window-list`) | PASS; section chrome is Repeaters on `contentItem`, not nested ListViews |
| Rail preferred width **72** (`SidebarModel.geometry`) | PASS; geometry tests assert 72 |
| `DockSidebarPinnedStrip.qml` in syntax inventory | PASS (`test_sidebar_qml_syntax.py`) |
| Pin strip rail collapse (`visible`/`enabled`/height 0, bottomMargin 0) | PASS |
| Dual `projection` / `railProjection` + `projectionFor` / `visibleRows` | PASS |
| No duplicate same-object signal handlers in touched `DockSidebar*.qml` | PASS (brace-aware scan); intentional separate `onClicked` on distinct controls; `geom`×2 are separate Repeater delegates |

**Bounded fixes this phase:** none — no clear integration defect found against completed Phase 2–9 contracts. No redesign/refactor/feature work.

### Focused checks (exact set)

| Check | Result |
| --- | --- |
| `node tests/test_sidebar_model.mjs` | PASS |
| `node tests/test_sidebar_geometry.mjs` | PASS |
| `node tests/test_sidebar_polish_behaviors.mjs` | PASS |
| `node tests/test_sidebar_entry_metadata.mjs` | PASS |
| `node tests/test_browser_tabs_model.mjs` | PASS |
| `python3 -m unittest discover -s tests -p test_sidebar_qml_syntax.py` | PASS |
| `git diff --check` | PASS |
| `/usr/lib/qt6/bin/qmlformat` → stdout/dev-null on `DockSidebar.qml` + `DockSidebarPinnedStrip.qml` | PASS |

### Material implemented behaviors (Phases 2–9, combined)

- Dual expanded/rail projections; viewport `visibleRows`; collapse focus remap; union `rowsByKey`
- Tree/section metadata + shared `sidebarRowMetrics` (incl. rail alert 36/58)
- Section card chrome + monitor Lucide headings; workspace badge-only identity; whole-card hover/grab; tree guides
- Window state icons + attention/(count) + tab mute eye + attention motion halt gate
- Collapsed rail chrome at width 72; pin strip zero-height in rail
- Direction A header (SmartDock brand + collapse) + footer pin shelf / Applications appearance reuse
- Independent scroll memory per connector×mode (`scrollStates`); thin vertical ScrollBar; contentHeight restore arm

### Intentionally deferred / limitations

- **No runtime/visual acceptance** this phase (explicit). User must switch and visually test.
- No full validation gate / `scripts/run` / qmllint host suite / QML testrunner
- Inactive scroll-mode keys recover on next mode enter (Phase 9)
- Workspace active perimeter border reserved unused; header/footer beyond Direction A scope deferred
- Herdr live-agent alerts / blur / right-click config not in scope
- Live dock remains on polish worktree until user runs handoff

### User handoff (DO NOT execute in this worker)

```bash
smartdock dev use /home/admin/Projects/smart-omarchy-dock/.worktrees/feat-fdm-968-sidebar-direction-a
```

Handoff readiness: **source-only YES** — focused checks green, contracts hold, live untouched. Visual/runtime acceptance is the user’s next step after the command above.
