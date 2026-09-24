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
