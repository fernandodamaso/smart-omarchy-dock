# Dock cleanup plan (approved, 2026-09-07)

Goal: one clean PR, no new behavior or dependencies. Historical docs untouched.
XDG/restoration bugs are explicitly excluded from this cleanup.

## Task 1 — dead code and docs (this worker)
- `DockModel.js`: remove `hasActiveMember`, `workspaceFromHandle`,
  `shouldRefreshFullscreenPresentation`, `floatWindowRequest`, `pinWindowRequest`.
- `DockWindowActions.qml`: remove `activeMember`, `focusToplevels`,
  `showToplevelPreviews`, and `previewController` plus its obsolete comment.
- `DockWindowModel.js`: remove `activeGroupMember` (now transitively dead).
- `DockBadgeModel.js`: remove `attentionSeverityFromBadgeToken`.
- `DockContextMenu.qml`: remove `selectedTitle`.
- `install.sh`: remove `agent_commands`.
- Tests: remove only obsolete assertions/import destructuring/structural guards
  tied to deleted symbols; preserve mixed-test assertions for active functions
  and active pointer/focus/preview/ownership behavior.
- README: remove advertised floating and workspace-pinning features; preserve
  application pinning, workspace moves, and minimize/restore.

## Task 2 — settings theme tokens
- Required `var themeColorTokens` on `DockSettings` with a live binding from `Dock`.

## Task 3 — window-model reuse
- Reuse `DockModel.normalizeWindowAddress` within `DockWindowModel` via QML JS import.
- Controller `handleForToplevel` keeps liveness semantics.
- Reuse `copyOriginSnapshot`.
- Preview path uses live `liveGroupMembers`, keeping the `>= 2` gate.

## Task 4 — settings merge
- Merge as `Object.assign({}, settings || {}, patch || {})`, preserving shallow
  non-mutation and patch precedence.

## Execution
- Sequential fresh Herdr OpenCode workers using the configured default model.
- Parent reviews, commits, and runs checks; final full checks with exact-SHA PR.
- No merge and no deployment from workers.
