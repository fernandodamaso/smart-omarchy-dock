# Dock Visual Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved dock mockup with semantic groups, a segmented workspace control, one top-right badge per application, stable item slots, and a thin focused-application indicator.

**Architecture:** Keep all existing controllers and behavior intact. `Dock.qml` owns shared layout metrics and group placement, `DockWorkspaceStrip.qml` owns the workspace capsule, `DockItem.qml` resolves badge presentation, and `DockModel.js` supplies pure indicator geometry rendered by `DockApplicationStateIndicator.qml`.

**Tech Stack:** Qt 6, QML/QtQuick, QtQuick.Effects, Quickshell, Omarchy `qs.Commons`/`qs.Ui`, QtTest, Bash structural checks.

**Spec:** `docs/superpowers/specs/2026-09-04-dock-visual-hierarchy-design.md`

## Global Constraints

- Start from `main`; the planning branch was created from `23074e816d617c22b8f7a5fa5c93c24460c0fe44`.
- Do not stack this work on open PR #3, #4, #8, or #10; their badge, focus, launcher-count, and urgent-motion implementations are already present in `main`.
- Preserve application launch/focus, pointer actions, grouping, drag reorder, previews, context menus, urgency motion, trash behavior, workspace dispatch, auto-hide, reserve space, fullscreen, magnification, and live reload.
- Keep `DockHost.qml` as the single owner of shared controllers.
- Keep the existing dynamic application slot contract: `itemSize = iconSize + 14`.
- Render exactly three semantic separators: Controls/Applications, Applications/Trash, and Trash/Workspaces.
- Render at most one top-right badge per application; an application attention/urgency/launcher badge wins over grouped-window count.
- Show grouped-window count only when `runningCount > 1`, using `Color.accent`.
- Preserve urgent application badge color and all existing badge-state ownership rules.
- Support top, bottom, left, and right positions in compact and full-length modes.
- Add no user-facing setting, provider change, or broad refactor.
- Work only in the canonical Git checkout; never edit installed plugin files or user configuration directly.

## File Map

- Modify `components/Dock.qml`: shared metrics, semantic separators, compact/full-length extents.
- Modify `components/DockWorkspaceStrip.qml`: outer capsule and active segment.
- Modify `components/DockSeparator.qml`: shorter and fainter separator line.
- Modify `components/DockItem.qml`: one-corner-badge precedence and window-count styling.
- Modify `components/DockApplicationBadge.qml`: shared numeric badge height.
- Modify `components/DockModel.js`: focused/running indicator geometry only.
- Modify `components/DockApplicationStateIndicator.qml`: thin marker and bounded glow.
- Modify `tests/tst_focusindicator_model.qml`: exact geometry contract.
- Modify `tests/tst_focusindicator_component.qml`: component geometry and glow contract.
- Create `tests/check_dock_visual_hierarchy.sh`: one structural regression check for this redesign.
- Modify `README.md` and `docs/FOCUS_INDICATOR.md`: document the final behavior.

---

### Task 1: Lock the visual contract with focused tests

**Files:**
- Modify: `tests/tst_focusindicator_model.qml`
- Modify: `tests/tst_focusindicator_component.qml`
- Create: `tests/check_dock_visual_hierarchy.sh`

**Interfaces:**
- Consumes: current `DockModel.applicationStateIndicatorGeometry()` and existing dock components.
- Produces: exact indicator geometry expectations and one structural contract for grouping, workspace capsule, badge precedence, and focused glow.

- [ ] **Step 1: Replace the indicator model geometry expectations**

In `tests/tst_focusindicator_model.qml`, replace the current geometry and scaling tests with:

```qml
function test_buildsThinPositionAwareRunningAndFocusedGeometry() {
  var topRunning = DockModel.applicationStateIndicatorGeometry(
    "top", 42, 42, true, false)
  compare(topRunning.visible, true)
  compare(topRunning.x, 19)
  compare(topRunning.y, -5)
  compare(topRunning.width, 4)
  compare(topRunning.height, 2)

  var topFocused = DockModel.applicationStateIndicatorGeometry(
    "top", 42, 42, true, true)
  compare(topFocused.x, 9)
  compare(topFocused.y, -5)
  compare(topFocused.width, 24)
  compare(topFocused.height, 2)

  var bottomFocused = DockModel.applicationStateIndicatorGeometry(
    "bottom", 42, 42, true, true)
  compare(bottomFocused.x, 9)
  compare(bottomFocused.y, 45)
  compare(bottomFocused.width, 24)
  compare(bottomFocused.height, 2)

  var leftFocused = DockModel.applicationStateIndicatorGeometry(
    "left", 42, 42, true, true)
  compare(leftFocused.x, 45)
  compare(leftFocused.y, 9)
  compare(leftFocused.width, 2)
  compare(leftFocused.height, 24)

  var rightFocused = DockModel.applicationStateIndicatorGeometry(
    "right", 42, 42, true, true)
  compare(rightFocused.x, -5)
  compare(rightFocused.y, 9)
  compare(rightFocused.width, 2)
  compare(rightFocused.height, 24)
}

function test_hidesMarkerWhenApplicationIsNotRunning() {
  var geometry = DockModel.applicationStateIndicatorGeometry(
    "bottom", 42, 42, false, false)
  compare(geometry.visible, false)
  compare(geometry.width, 4)
  compare(geometry.height, 2)
}

function test_scalesFocusedMarkerWithinBoundedIconAwareRange() {
  var small = DockModel.applicationStateIndicatorGeometry(
    "bottom", 24, 24, true, true)
  compare(small.width, 14)
  compare(small.height, 2)

  var large = DockModel.applicationStateIndicatorGeometry(
    "bottom", 96, 96, true, true)
  compare(large.width, 32)
  compare(large.height, 3)
}
```

Keep the existing active-member identity test unchanged.

- [ ] **Step 2: Update the indicator component expectations**

In `tests/tst_focusindicator_component.qml`, update the three visual-state tests to assert:

```qml
function test_runningUsesCompactMarkerWithoutGlow() {
  var indicator = createTemporaryObject(indicatorComponent, this, {
    running: true,
    focused: false
  })
  verify(indicator)
  compare(indicator.indicatorGeometry.visible, true)
  compare(indicator.width, 4)
  compare(indicator.height, 2)
  compare(indicator.markerColor, indicator.runningColor)
  compare(indicator.focusedGlowOpacity, 0)
}

function test_focusedUsesLongMarkerWithBoundedGlow() {
  var indicator = createTemporaryObject(indicatorComponent, this, {
    running: true,
    focused: true
  })
  verify(indicator)
  compare(indicator.indicatorGeometry.visible, true)
  compare(indicator.width, 24)
  compare(indicator.height, 2)
  compare(indicator.markerColor, indicator.focusedColor)
  compare(indicator.focusedGlowOpacity, 0.18)
}

function test_positionChangeReorientsFocusedMarker() {
  var indicator = createTemporaryObject(indicatorComponent, this, {
    running: true,
    focused: true,
    position: "left"
  })
  verify(indicator)
  compare(indicator.x, 45)
  compare(indicator.y, 9)
  compare(indicator.width, 2)
  compare(indicator.height, 24)

  indicator.position = "right"
  compare(indicator.x, -5)
  compare(indicator.y, 9)
  compare(indicator.width, 2)
  compare(indicator.height, 24)
}
```

Keep `test_notRunningHidesMarker()` unchanged.

- [ ] **Step 3: Add the single structural redesign check**

Create `tests/check_dock_visual_hierarchy.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

separator_count="$(grep -c \
  '^[[:space:]]*DockSeparator[[:space:]]*{' components/Dock.qml)"
test "$separator_count" -eq 3

grep -q 'id: controlAppsSeparator' components/Dock.qml
grep -q 'id: appTrashSeparator' components/Dock.qml
grep -q 'id: trashWorkspaceSeparator' components/Dock.qml
grep -q 'Util.alpha(Color.menu.border, 0.28)' components/DockSeparator.qml

grep -q 'id: workspaceCapsule' components/DockWorkspaceStrip.qml
grep -q 'id: activeSegment' components/DockWorkspaceStrip.qml
grep -q 'Util.alpha(Color.accent, 0.16)' components/DockWorkspaceStrip.qml

window_badge_block="$(
  sed -n '/id: windowCountBadge/,/id: windowCountText/p' \
    components/DockItem.qml
)"
grep -q \
  'visible: root.runningCount > 1 && !applicationBadge.visible' \
  <<<"$window_badge_block"
grep -q 'color: Color.accent' <<<"$window_badge_block"

grep -q 'id: applicationBadge' components/DockItem.qml
grep -q 'badgeHeight: root.cornerBadgeHeight' components/DockItem.qml
grep -q 'readonly property real focusedGlowOpacity' \
  components/DockApplicationStateIndicator.qml
```

Make it executable:

```bash
chmod +x tests/check_dock_visual_hierarchy.sh
```

- [ ] **Step 4: Run the focused checks and confirm RED**

```bash
qmltestrunner -input tests -import components
bash tests/check_dock_visual_hierarchy.sh
```

Expected before production changes:

- QtTest fails on the new `2px`/`24px` geometry and missing `focusedGlowOpacity`.
- The structural script fails because the Controls/Applications separator, workspace capsule, and one-badge precedence do not exist yet.

- [ ] **Step 5: Commit the contract tests**

```bash
git add tests/tst_focusindicator_model.qml \
  tests/tst_focusindicator_component.qml \
  tests/check_dock_visual_hierarchy.sh
git commit -m "test: define dock visual hierarchy contract"
```

---

### Task 2: Build semantic groups and the segmented workspace control

**Files:**
- Modify: `components/Dock.qml`
- Modify: `components/DockWorkspaceStrip.qml`
- Modify: `components/DockSeparator.qml`
- Test: `tests/check_dock_visual_hierarchy.sh`

**Interfaces:**
- Consumes: existing `visibleWorkspaceIds`, workspace count inputs, and `workspaceRequested(int)` behavior.
- Produces: `DockWorkspaceStrip.segmentSize`, `segmentSpacing`, and `capsulePadding` inputs; three semantic layout groups separated by fixed `12px` slots.

- [ ] **Step 1: Centralize the layout metrics in `Dock.qml`**

Replace the current workspace/trailing extent constants with:

```qml
readonly property int itemSize: iconSize + 14
readonly property int separatorMainExtent: 12
readonly property int workspaceSegmentSize: 30
readonly property int workspaceSegmentSpacing: 2
readonly property int workspaceCapsulePadding: 4
readonly property int workspaceCount: visibleWorkspaceIds.length
readonly property int workspaceMainExtent:
  workspaceCount * workspaceSegmentSize
    + Math.max(0, workspaceCount - 1) * workspaceSegmentSpacing
    + workspaceCapsulePadding * 2
readonly property int leadingMainExtent: itemSize + separatorMainExtent
readonly property int trailingMainExtent:
  separatorMainExtent + itemSize + separatorMainExtent + workspaceMainExtent
readonly property int compactMainExtent:
  mainPadding * 2 + leadingMainExtent + appMainExtent + trailingMainExtent
```

Inside `dockLayout`, change the leading boundary to:

```qml
readonly property real leadingEnd: root.mainPadding + root.leadingMainExtent
```

Leave the existing centered-app clamp intact so full-length docks still center applications between the leading and trailing groups.

- [ ] **Step 2: Add the Controls/Applications separator**

Insert this component immediately after `DockControlItem` and before `appGrid`:

```qml
DockSeparator {
  id: controlAppsSeparator

  x: root.vertical
    ? (parent.width - width) / 2
    : root.mainPadding + controlItem.width
  y: root.vertical
    ? root.mainPadding + controlItem.height
    : (parent.height - height) / 2
  vertical: root.vertical
  slotSize: root.itemSize
  iconSize: root.iconSize
}
```

The existing `appGrid` continues using `parent.appStart`; the updated `leadingEnd` places it after the new separator in compact mode.

- [ ] **Step 3: Make separators shorter and fainter**

In `components/DockSeparator.qml`, replace the inner rectangle geometry and color with:

```qml
Rectangle {
  anchors.centerIn: parent
  width: root.vertical ? Math.max(18, Math.round(root.iconSize * 0.56)) : 1
  height: root.vertical ? 1 : Math.max(18, Math.round(root.iconSize * 0.56))
  color: Util.alpha(Color.menu.border, 0.28)
}
```

Keep the component's existing `12px` main-axis extent.

- [ ] **Step 4: Render the workspace capsule and active segment**

In `components/DockWorkspaceStrip.qml`, add these required properties:

```qml
required property int segmentSize
required property int segmentSpacing
required property int capsulePadding
```

Replace its root dimensions with:

```qml
width: vertical
  ? segmentSize + capsulePadding * 2
  : workspaceGrid.implicitWidth + capsulePadding * 2
height: vertical
  ? workspaceGrid.implicitHeight + capsulePadding * 2
  : segmentSize + capsulePadding * 2
```

Add the capsule before `workspaceGrid`:

```qml
Rectangle {
  id: workspaceCapsule

  anchors.fill: parent
  radius: Math.min(width, height) / 2
  color: Util.alpha(Color.foreground, 0.05)
  border.width: 1
  border.color: Util.alpha(Color.menu.border, 0.42)
}
```

Keep `workspaceGridOrigin`, set `workspaceGrid.spacing` to `root.segmentSpacing`, and change each workspace cell to:

```qml
width: root.segmentSize
height: root.segmentSize
opacity: focused ? 1 : occupied ? 0.82 : 0.50

Rectangle {
  id: activeSegment

  anchors.fill: parent
  visible: workspaceCell.focused
  radius: Math.max(6, Math.min(width, height) * 0.28)
  color: Util.alpha(Color.accent, 0.16)
}

Button {
  anchors.fill: parent
  text: ""
  tooltipText: "Workspace " + workspaceCell.modelData
    + (workspaceCell.count === 0
      ? " — empty"
      : " — " + workspaceCell.count
        + (workspaceCell.count === 1 ? " window" : " windows"))
  selected: false
  bordered: false
  foreground: Color.menu.text
  background: "transparent"
  accent: Color.accent
  horizontalPadding: 4
  verticalPadding: 3
  onClicked: root.workspaceRequested(workspaceCell.modelData)
}

Row {
  anchors.centerIn: parent
  spacing: 4

  Rectangle {
    visible: workspaceCell.focused
    anchors.verticalCenter: parent.verticalCenter
    width: 5
    height: 5
    radius: 2.5
    color: Color.accent
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: workspaceCell.modelData === 10
      ? "0" : String(workspaceCell.modelData)
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: workspaceCell.focused
  }
}
```

Remove the old standalone bottom dot because the dot now belongs inside the selected segment.

- [ ] **Step 5: Pass the shared workspace metrics from `Dock.qml`**

Add these bindings to the existing `DockWorkspaceStrip` instance:

```qml
segmentSize: root.workspaceSegmentSize
segmentSpacing: root.workspaceSegmentSpacing
capsulePadding: root.workspaceCapsulePadding
```

- [ ] **Step 6: Run the layout check and launch smoke test**

```bash
bash tests/check_dock_visual_hierarchy.sh || true
timeout 6s ./scripts/run --no-color
```

At this point the group and workspace assertions must pass. The full script may still fail on badge precedence and focused glow, which are implemented in Tasks 3 and 4. The smoke run must show no QML binding loop, required-property error, or component load failure.

- [ ] **Step 7: Commit the grouped layout**

```bash
git add components/Dock.qml components/DockWorkspaceStrip.qml \
  components/DockSeparator.qml
git commit -m "feat: group dock controls and segment workspaces"
```

---

### Task 3: Enforce one clean top-right application badge

**Files:**
- Modify: `components/DockItem.qml`
- Modify: `components/DockApplicationBadge.qml`
- Test: `tests/check_dock_visual_hierarchy.sh`
- Test: `tests/check_attention_badges.sh`
- Test: `tests/check_launcher_badge_counts.sh`

**Interfaces:**
- Consumes: existing `attentionBadge` severity tokens and `DockApplicationBadge.visible` parsing.
- Produces: `DockApplicationBadge.badgeHeight`; a single-corner precedence rule where application badge visibility suppresses grouped-window count.

- [ ] **Step 1: Add a configurable numeric height to `DockApplicationBadge.qml`**

Add:

```qml
property int badgeHeight: 16
readonly property int numericHeight: Math.max(14, badgeHeight)
```

Change numeric sizing to:

```qml
width: numeric ? Math.max(numericHeight, countText.implicitWidth + 8) : 10
height: numeric ? numericHeight : 10
```

Leave token parsing, urgency color, attention color, border, text, and `99+` handling unchanged.

- [ ] **Step 2: Define one shared corner height in `DockItem.qml`**

Add beside the existing icon/layout properties:

```qml
readonly property int cornerBadgeHeight: Math.max(
  14, Math.min(16, Math.round(iconSize * 0.38)))
```

- [ ] **Step 3: Restyle and gate the grouped-window count**

Replace the existing `windowCountBadge` presentation with:

```qml
Rectangle {
  id: windowCountBadge

  visible: root.runningCount > 1 && !applicationBadge.visible
  width: Math.max(root.cornerBadgeHeight,
    windowCountText.implicitWidth + 8)
  height: root.cornerBadgeHeight
  radius: height / 2
  x: iconContainer.width - width + 3
  y: -3
  color: Color.accent
  border.width: Style.normalBorderWidth
  border.color: Color.background
  z: 3

  Text {
    id: windowCountText

    anchors.centerIn: parent
    text: root.runningCount > 99 ? "99+" : String(root.runningCount)
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
```

This intentionally removes urgent red from a non-urgent window-count concept.

- [ ] **Step 4: Put the application badge in the same corner**

Replace the current `DockApplicationBadge` instance with:

```qml
DockApplicationBadge {
  id: applicationBadge

  severity: root.attentionBadge
  badgeHeight: root.cornerBadgeHeight
  x: iconContainer.width - width + 3
  y: -3
}
```

Do not offset it downward when a grouped-window count exists. `applicationBadge.visible` is the precedence source for the window-count binding.

- [ ] **Step 5: Run the badge-focused checks**

```bash
bash tests/check_dock_visual_hierarchy.sh || true
bash tests/check_attention_badges.sh
bash tests/check_launcher_badge_counts.sh
qmltestrunner -input tests -import components
```

Expected:

- Attention/launcher severity parsing and ownership tests remain green.
- The structural badge assertions pass.
- Focus-indicator tests remain red until Task 4.

- [ ] **Step 6: Commit the badge hierarchy**

```bash
git add components/DockItem.qml components/DockApplicationBadge.qml
git commit -m "feat: simplify dock corner badges"
```

---

### Task 4: Refine the focused-application indicator

**Files:**
- Modify: `components/DockModel.js`
- Modify: `components/DockApplicationStateIndicator.qml`
- Test: `tests/tst_focusindicator_model.qml`
- Test: `tests/tst_focusindicator_component.qml`
- Test: `tests/check_focus_indicator.sh`
- Test: `tests/check_dock_visual_hierarchy.sh`

**Interfaces:**
- Consumes: `position`, icon dimensions, `running`, `focused`, `runningColor`, and `focusedColor`.
- Produces: the existing `indicatorGeometry` shape plus `focusedGlowOpacity: real` for a bounded visual glow.

- [ ] **Step 1: Replace the indicator geometry helper**

In `components/DockModel.js`, replace `applicationStateIndicatorGeometry()` with:

```js
function applicationStateIndicatorGeometry(position, iconWidth, iconHeight,
                                           running, focused) {
  var edge = ["top", "bottom", "left", "right"].indexOf(position) >= 0
    ? position : "bottom"
  var width = Math.max(0, Number(iconWidth) || 0)
  var height = Math.max(0, Number(iconHeight) || 0)
  var minimumDimension = Math.max(1, Math.min(width || 1, height || 1))
  var thickness = Math.max(2,
    Math.min(3, Math.round(minimumDimension * 0.04)))
  var focusedLength = Math.max(14,
    Math.min(32, Math.round(minimumDimension * 0.56)))
  var runningLength = thickness + 2
  var markerLength = focused ? focusedLength : runningLength
  var vertical = edge === "left" || edge === "right"
  var markerWidth = vertical ? thickness : markerLength
  var markerHeight = vertical ? markerLength : thickness
  var gap = 3
  var x = Math.round((width - markerWidth) / 2)
  var y = Math.round((height - markerHeight) / 2)

  if (edge === "top")
    y = -(markerHeight + gap)
  else if (edge === "bottom")
    y = height + gap
  else if (edge === "left")
    x = width + gap
  else if (edge === "right")
    x = -(markerWidth + gap)

  return {
    visible: Boolean(running),
    x: x,
    y: y,
    width: markerWidth,
    height: markerHeight,
    radius: thickness / 2
  }
}
```

Do not modify any other model helper.

- [ ] **Step 2: Render the restrained focused glow**

Add this import to `components/DockApplicationStateIndicator.qml`:

```qml
import QtQuick.Effects
```

Add this public read-only property:

```qml
readonly property real focusedGlowOpacity:
  running && focused ? 0.18 : 0
```

Replace the current inner rectangle with:

```qml
RectangularShadow {
  anchors.fill: marker
  radius: marker.radius
  blur: 6
  spread: 1
  offset: Qt.vector2d(0, 0)
  color: root.focusedColor
  opacity: root.focusedGlowOpacity
  z: -1
}

Rectangle {
  id: marker

  anchors.fill: parent
  radius: root.indicatorGeometry.radius
  color: root.markerColor
  opacity: root.focused ? 1.0 : 0.72
}
```

Keep the indicator outside `motionContent` in `DockItem.qml`; urgent-window motion must continue moving only artwork and badges.

- [ ] **Step 3: Run the focused indicator checks**

```bash
qmltestrunner -input tests -import components
bash tests/check_focus_indicator.sh
bash tests/check_dock_visual_hierarchy.sh
```

Expected: all new geometry, component, grouping, workspace, badge, and glow assertions pass.

- [ ] **Step 4: Check interaction compatibility**

```bash
bash tests/check_hover_glow.sh
bash tests/check_urgent_window_motion.sh
bash tests/check_cross_axis_alignment.sh
```

Expected: hover glow remains attached to artwork, urgent motion remains one-shot and bounded, and cross-axis positioning remains valid.

- [ ] **Step 5: Commit the indicator treatment**

```bash
git add components/DockModel.js \
  components/DockApplicationStateIndicator.qml
git commit -m "feat: refine focused application indicator"
```

---

### Task 5: Document and validate the complete redesign

**Files:**
- Modify: `README.md`
- Modify: `docs/FOCUS_INDICATOR.md`
- Verify: all production and test files changed in Tasks 1–4

**Interfaces:**
- Consumes: the completed visual hierarchy.
- Produces: user-facing documentation and merge evidence; no new runtime interface.

- [ ] **Step 1: Add the visual hierarchy description to `README.md`**

Add this paragraph near the existing dock appearance/focus documentation:

```markdown
### Dock visual hierarchy

The compact dock is organized as **Controls | Applications | Trash | Workspaces**.
Controls, applications, and Trash use equal dynamic slots; faint separators mark
only semantic group boundaries. Workspaces share one segmented capsule, with the
active segment highlighted by the theme accent. Application attention or launcher
badges take the single top-right badge position; otherwise grouped applications
show an accent window count only when more than one window is open. The focused
application uses a thin accent line with a restrained glow.
```

Do not add a configuration entry because the redesign has no toggle.

- [ ] **Step 2: Update `docs/FOCUS_INDICATOR.md`**

Document these exact rules:

```markdown
- Running-only marker length: `thickness + 2`.
- Focused marker length: `max(14, min(32, round(iconSize * 0.56)))`.
- Thickness: `max(2, min(3, round(iconSize * 0.04)))`.
- Edge gap: `3px`.
- Focused glow: accent color, `0.18` opacity, blur `6`, spread `1`.
- The marker remains anchored outside urgent-window artwork motion.
```

Remove old `3–5px` thickness and `10–18px` focused-length descriptions.

- [ ] **Step 3: Run the focused regression set**

```bash
qmltestrunner -input tests -import components
bash tests/check_dock_visual_hierarchy.sh
bash tests/check_attention_badges.sh
bash tests/check_launcher_badge_counts.sh
bash tests/check_focus_indicator.sh
bash tests/check_cross_axis_alignment.sh
bash tests/check_hover_glow.sh
bash tests/check_urgent_window_motion.sh
```

All commands must pass. Do not run launcher-provider C++ tests because no provider file changes in this feature.

- [ ] **Step 4: Run the repository validation gate**

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run \
  tests/check_window_actions.sh tests/check_dock_visual_hierarchy.sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockApplicationBadge.qml \
  components/DockApplicationStateIndicator.qml \
  components/DockWorkspaceStrip.qml components/DockSeparator.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml shell.qml
git diff --check
```

A pre-existing portal warning about an already registered application ID is not a dock failure; any QML load error, binding loop, missing required property, lint error, or plugin-validation error is a blocker.

- [ ] **Step 5: Perform the minimal visual acceptance pass**

Run `./scripts/run` from the canonical checkout and verify these two orientations:

1. **Bottom dock:** one-window app has no count, two-window app has one accent top-right badge, an application badge suppresses that window count, the focused app has a thin underline, and workspaces appear in one capsule.
2. **Left dock:** the workspace capsule becomes vertical, the focused indicator becomes a vertical accent line, separators rotate correctly, and no badge or glow clips during magnification.

In both orientations, trigger one urgent-window nudge and open one preview/context menu to confirm that the redesign did not move the persistent focus marker into transient artwork motion.

- [ ] **Step 6: Commit documentation and validation evidence**

```bash
git add README.md docs/FOCUS_INDICATOR.md
git commit -m "docs: describe dock visual hierarchy"

git status --short
git log --oneline --decorate -5
```

Expected final status: clean working tree with the five task commits present on `feat/dock-visual-hierarchy`.

## Merge Boundary

The implementation PR should target `main` directly. It must not close, merge, or retarget the older open feature PRs; handle that cleanup separately after verifying each branch is already represented in `main`.
