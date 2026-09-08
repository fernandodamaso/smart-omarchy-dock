# Compact Dock Implementation Plan

> **For agentic workers:** Use the executing-plans skill and execute the assigned tasks through Herdr Codex agents; coding uses gpt-6-astra / low, review uses gpt-6-astra / medium. Coordinator integrates and delivers.

**Goal:** Make the existing workspace dock visibly slimmer and more elegant, preserving all apps in every workspace and mirrored monitor behavior.

**Architecture:** Refine existing QML geometry and surfaces. Keep the current models, scoped controller, layout viewport, settings persistence, and native Qt effects. No dependencies or new appearance settings.

**Tech Stack:** Quickshell, Qt Quick/QML, existing Omarchy theme and BorderSurface.

**Spec:** User-approved design in this conversation: approximately 25–30% lower dock; narrow workspace labels; always-visible app icons; faint inactive boundaries and soft active accent; hover-first icon tiles; restrained shadow/highlight and 120–160ms transitions.

## Global Constraints

- Keep this worktree and fix/workspace-card-presentation branch. PR-only delivery to main, then Omarchy plugin update; installed plugin is never edited directly.
- Preserve configured icon size, colors/opacity/border overrides, magnification, reduced/disabled effects preferences, auto-hide, reserve-space and live settings reload.
- Preserve keyboard/accessibility, urgency, badges, tooltips/previews and stable presentation-ID ownership. No accordion, no model/action changes.
- No source dock on live outputs. Any new GUI must be workspace9 silent/no initial focus; never move existing user windows. Root owns deployment and live capture.
- Separate file ownership; workers do not commit, deploy or alter user settings. Root owns structural test adjustments when old style assertions intentionally change.

### Task 1: Compact workspace cards (Astra low)
**Files:** components/DockWorkspaceGroup.qml, components/DockWorkspaceLayout.qml.
**Interface:** Keep slotSize, headerWidth, items, active/urgent, viewport and activation contract. New group height is slotSize + 10; root geometry owner uses the same value.
- [x] Read full components and existing tests before editing.
- [x] Use narrow numeric headers (about 28–32px, named labels elided with existing full tooltip). Preserve a practical whole-height keyboard/mouse target and visible keyboard focus.
- [x] Group height slotSize + 10, 6px icon spacing, 8px group spacing; occupied app row starts header.width + 4 and right inset 6. Empty groups retain a small pill.
- [x] Remove permanent active header slab; tint the whole active card subtly, faint inactive border. Keep clear urgency and focused workspace. Use 140ms color transitions without changing geometry or app visibility.
- [x] Run existing workspace layout/model/action checks; report exact changes and any stale structural assertions. No redundant new styling-only test suite.

### Task 2: Compact host and hover surfaces (Astra low)
**Files:** components/Dock.qml, components/DockItem.qml, components/DockControlItem.qml, components/DockTrashItem.qml if present.
**Interface:** Group height slotSize + 10 from Task1. Preserve public props, models and controller routes.
- [x] Trace itemSize, crossExtent, reservedSize, dockBackground, grouped rowY, utility separators and icons, magnification/clipping paths before edits.
- [x] Target horizontal background iconSize + 32 (31px icons => 63px versus87), grouped item slot iconSize + 14, main padding8, viewport base padding8 plus existing magnification allowance. Align group rowY to slotSize + 10 and global/fallback icon centering. Keep sufficient transparent magnification headroom and matching exclusive-zone geometry. Preserve vertical behavior unless a shared style change naturally applies.
- [x] Remove static utility boxes; use hover-first app/control/trash tiles, faint or transparent at rest and subdued fill/border on hover, 140ms color changes. Keep focus underline and badges unobscured.
- [x] Add restrained native shadow/top-edge highlight only within existing surface/mask bounds; respect custom border and opacity, avoid changing user config or adding blur rules. Reuse existing effects. Omit extra hover lift if it conflicts with attention/magnification motion.
- [x] Run relevant existing visual/position/layout checks and report evidence. No new infrastructure.

### Task 3: Integrate, validate and review (root + Astra medium)
**Files:** existing tests/check_*.sh only if stale visual assertions need narrow updates; README.md if appearance description needs correction; this plan.
- [x] Inspect combined diff and check rendered geometry (small/large icons, named/empty/multiple cards, badges, overflow, top/bottom and vertical/flat regression).
- [x] Run shell syntax, all check_*.sh and test_*.mjs, Python discovery, offscreen qmltestrunner, plugin validation, Omarchy-aware qmllint and diff check. Capture exact logs in /tmp/smartdock-compact-validation.
- [ ] Astra medium reviewer independently checks correctness, accessibility, clipping, config compatibility and runnable source-component geometry. Resolve actionable findings before acceptance.
- [ ] Commit exact candidate; record base/head and run PR Headless CI. No manual review pause requested by user.

### Task 4: Deliver and visually verify (root)
- [ ] Merge passing reviewed PR, fast-forward canonical main and use omarchy plugin update. Restart existing shell if necessary; do not run a second dock.
- [ ] Capture both installed docks without moving focus. Inspect slimmer height, workspace labels, app visibility, focus/badges and utility alignment. Compare against original screenshot. Verify shell logs and user settings checksum.
- [ ] If live visual defects appear, fix through a follow-up validated PR before reporting done. Close all created Herdr worker panes after reading completed results.
- [ ] Report PR, measured visible size change and honest validation limitations.

## Implementation notes

- The outer shadow is omitted because the surface fills its window width and would clip; the subtle top-edge highlight and native hover glow provide the bounded effects. No compositor blur rule or user preference is changed.
- Header width uses one bounded text-based expression (30–80px), keeping multi-digit workspace labels readable at larger icon sizes.
- Review found a real supported-size magnification regression: grouped focus markers now remain on the unscaled slot. The existing grouped-action test executes the production marker bindings and checks compact bounds; independent offscreen QML exercises actual components. Original notification-badge placement remains correct across supported 24–96px icons.
- Exact commit, review, CI and installed capture evidence are recorded in the delivery PR; post-merge steps below remain the execution checklist rather than a second documentation-only release.
