# Dock Visual Hierarchy Design

**Status:** Approved visual direction

**Implementation base:** `main` at `23074e816d617c22b8f7a5fa5c93c24460c0fe44`

## Purpose

Make the dock read as four intentional groups—Controls, Applications, Trash, and Workspaces—while reducing badge clutter and making the focused application and active workspace obvious at a glance.

The redesign is visual only. It must preserve all existing launch, focus, grouping, drag, preview, urgency, trash, workspace, auto-hide, and full-length behavior.

## Repository Integration

The feature starts from current `main`, not from one of the still-open feature pull requests. Current `main` already contains the relevant application-badge, launcher-count, focus-indicator, preview, and urgent-motion implementations represented by the open PR branches.

The implementation must preserve these existing ownership boundaries:

- `DockHost.qml` remains the owner of the shared window-action and badge controllers.
- `DockBadgeTracker` remains the single source of attention and urgency state.
- `DockItem.qml` remains responsible for one application's visual presentation.
- `DockWorkspaceStrip.qml` remains responsible for workspace presentation and switching.
- `DockModel.js` remains the home of pure geometry helpers.

Closing or retargeting old pull requests is separate repository housekeeping and is not part of this feature.

## Visual Contract

### 1. Semantic Groups

The compact dock uses this order:

```text
Controls | Applications | Trash | Workspaces
```

There are exactly three semantic separators. Each separator uses:

- Main-axis extent: `12px`
- Line thickness: `1px`
- Cross-axis length: `max(18, round(iconSize * 0.56))`
- Color: `Util.alpha(Color.menu.border, 0.28)`

The line stays centered in its separator slot. Top, bottom, left, and right docks use the same proportions, rotated with the dock orientation.

### 2. Stable Item Slots

Controls, application items, and Trash continue using the same dynamic slot size:

```qml
itemSize: iconSize + 14
```

The `36×36` slot in the concept image is a visual shorthand, not a new fixed size. SmartDock's existing configurable `iconSize` range must continue to work. Magnification scales icon artwork inside the slot; it must not change the base layout or shift neighboring groups.

### 3. Segmented Workspace Control

`DockWorkspaceStrip.qml` becomes one rounded capsule containing equal workspace segments.

Geometry:

- Segment size: `30×30px`
- Segment spacing: `2px`
- Capsule padding: `4px`
- Capsule radius: half of the shortest capsule dimension
- Capsule background: `Util.alpha(Color.foreground, 0.05)`
- Capsule border: `1px`, `Util.alpha(Color.menu.border, 0.42)`

State presentation:

- Focused workspace: subtle fill `Util.alpha(Color.accent, 0.16)`, full-opacity label, and a `5px` accent dot immediately before the workspace number.
- Occupied inactive workspace: `0.82` opacity.
- Empty inactive workspace: `0.50` opacity.
- Workspace `10` continues to render as `0`.
- Existing window-count tooltip text and workspace-dispatch behavior remain unchanged.

The control lays out horizontally on top/bottom docks and vertically on left/right docks.

### 4. Corner Badge Hierarchy

Every application icon may render at most one badge in its top-right corner.

Precedence:

1. Existing application attention/urgency/launcher-count badge, when visible.
2. Grouped running-window count, only when `runningCount > 1`.
3. No badge.

Consequences:

- A single running window never shows a `1`.
- Application badges are no longer pushed down when a grouped-window count exists.
- A grouped-window count is suppressed while an application badge is visible; the tooltip still exposes the window count.
- Grouped-window count uses `Color.accent`, not `Color.urgent`.
- Existing urgent application badges continue using `Color.urgent`.
- Existing `99+` truncation remains unchanged.
- Minimized-window and workspace badges keep their current corners and semantics.

Both numeric badge types use the same height supplied by `DockItem.qml`:

```qml
cornerBadgeHeight: max(14, min(16, round(iconSize * 0.38)))
```

### 5. Focused Application Indicator

The running/focused marker remains anchored to the stable icon slot and remains outside urgent-window motion.

`DockModel.applicationStateIndicatorGeometry()` uses:

```js
thickness = max(2, min(3, round(minimumDimension * 0.04)))
focusedLength = max(14, min(32, round(minimumDimension * 0.56)))
runningLength = thickness + 2
gap = 3
```

Presentation:

- Running but not focused: compact dot/capsule in `runningColor` at `0.72` opacity.
- Focused: longer accent line at full opacity.
- Focused glow: accent color, `0.18` opacity, blur `6`, spread `1`, no animation loop.
- Top/bottom docks use a horizontal indicator; left/right docks use a vertical indicator.

## Component Changes

### `components/Dock.qml`

Own shared layout metrics, add the Controls/Applications separator, and update compact/full-length extent calculations. Continue passing existing state into child components.

### `components/DockWorkspaceStrip.qml`

Render the outer capsule and selected segment while retaining the current repeater, tooltip content, count lookup, and `workspaceRequested(int)` signal.

### `components/DockItem.qml`

Choose the single top-right badge, restyle grouped-window counts, and pass a shared numeric height into `DockApplicationBadge.qml`.

### `components/DockApplicationBadge.qml`

Accept `badgeHeight` and use it for numeric badges without changing severity parsing or colors.

### `components/DockApplicationStateIndicator.qml`

Render the refined marker and bounded focused glow from geometry supplied by `DockModel.js`.

### `components/DockSeparator.qml`

Use the shorter, fainter semantic separator treatment.

### `components/DockModel.js`

Update only `applicationStateIndicatorGeometry()`. No dock behavior, badge-state, or workspace-state logic moves into this file.

## Behavior That Must Not Change

- Application launch/focus and configured pointer actions
- Grouped and ungrouped application behavior
- Drag reorder and drop targeting
- Window previews and context menus
- Urgent-window nudge revision, suppression, and cooldown behavior
- Launcher-count and attention-badge ownership
- Minimized-window and workspace badges
- Trash open/empty behavior
- Workspace count lookup and dispatch
- Auto-hide, reserve-space, full-length, fullscreen, and magnification behavior
- Standalone and Omarchy plugin entry points
- Live settings reload

## Testing Strategy

Keep the regression surface small:

1. Update existing focus-indicator model/component tests for the new geometry and glow contract.
2. Add one structural check, `tests/check_dock_visual_hierarchy.sh`, covering the three semantic separators, workspace capsule, and single-corner-badge precedence.
3. Run the existing attention-badge, launcher-count, cross-axis, hover-glow, and focus-indicator checks because this change touches their presentation.
4. Run the repository validation commands from `AGENTS.md`.
5. Perform one horizontal and one vertical visual pass with no badge, grouped-window count, application badge, focused app, active workspace, magnification, and urgent motion.

No provider tests or new configuration tests are required because this feature does not change provider code or user-facing settings.

## Out of Scope

- Contextually hiding Trash
- New configuration toggles or color settings
- New animations beyond the bounded focused glow
- Badge-provider changes
- Workspace renaming or reordering
- Closing, merging, or retargeting existing pull requests
- Broad QML component refactors

## Acceptance Criteria

- The dock clearly reads as Controls, Applications, Trash, and Workspaces.
- The workspace numbers appear inside one capsule, and the active workspace is unmistakable.
- Every application occupies the same stable slot for a given `iconSize`.
- A grouped application shows no window-count badge for one window.
- No application displays two top-right badges simultaneously.
- The focused application uses a thin accent line with a restrained glow.
- Top, bottom, left, and right orientations remain usable without clipping.
- Existing functional and validation checks pass.
