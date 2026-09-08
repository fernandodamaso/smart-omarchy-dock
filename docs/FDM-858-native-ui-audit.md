# FDM-858 native Omarchy UI audit

## Reference points

- SmartDock baseline reviewed for this change: `main@2b11adfccd84883a2dca1287ffb4612a95e9697e`.
- Native Omarchy reference: `omacom/omarchy@148945000fa5bea240864fde9ab551df49f16da6` (`shell/Ui/Dropdown.qml`).
- Scope: custom **visual** QML under `components/`. JavaScript models and the nonvisual `DockBadgeTracker.qml`, `DockLauncherBadgeService.qml`, and `DockWindowActions.qml` controllers/services are not migration targets.

A native control is adopted only when it removes duplicated generic control behavior while leaving SmartDock-specific responsibilities intact. There is no removal quota.

## Decisions

| Component | Decision | Reason |
| --- | --- | --- |
| `Dock.qml` | Keep | Top-level dock/layer-shell composition and application state orchestration are SmartDock responsibilities, not a generic UI control. |
| `DockActionDropdown.qml` | **Replace internals; keep thin adapter** | Native `qs.Ui.Dropdown` owns option rendering, popup behavior, pointer handling, and keyboard navigation. The adapter keeps SmartDock's existing label composition and restores the settings-driven child binding after native selection. |
| `DockAppPicker.qml` | Keep | Application discovery/filtering, pinned-state behavior, dock-relative popup geometry, and selection flow are application-specific. |
| `DockApplicationBadge.qml` | Keep | Renders SmartDock-specific launcher/attention badge state; Omarchy exposes no equivalent generic badge control in the reviewed UI module. |
| `DockApplicationStateIndicator.qml` | Keep | Encodes dock-position-aware running/focused marker geometry rather than generic form/control behavior. |
| `DockAttentionMotion.qml` | Keep | Owns SmartDock's icon attention motion contract and animation lifecycle. |
| `DockColorSwatch.qml` | Keep | Small color-preview primitive used by SmartDock's specialized color settings; replacing it would not remove control logic. |
| `DockColorTokenDropdown.qml` | Keep | Specialized theme-token/color semantics and swatch rows are not equivalent to a plain action `Dropdown`. Out of scope for this PR. |
| `DockContextMenu.qml` | Keep | Owns window actions, nested menu pages, focus, keyboard selection, and dock-relative anchoring. `PopupCard` has a different bar/popout contract. |
| `DockControlItem.qml` | Keep | Owns dock magnification, transform origin, glow, tooltip suppression, and context-menu behavior. Native panel buttons do not remove those duties. |
| `DockHiddenApplicationRow.qml` | Keep | Combines application identity and SmartDock-specific hide/unhide settings behavior. |
| `DockItem.qml` | Keep | Core application icon behavior includes running-window state, magnification, drag/reorder, pointer actions, badges, previews, and menus. |
| `DockLucideIcon.qml` | Keep | Thin asset/tint helper for SmartDock's bundled Lucide SVGs; it does not duplicate a generic interactive control. |
| `DockMenuAction.qml` | Keep | Full-width menu row supports icon assets, keyboard-active highlighting, optional hover activation, and context-menu cursor behavior. Native `PanelActionButton` is an inline icon button, not an equivalent row. |
| `DockSeparator.qml` | Keep | Owns orientation-dependent slot sizing and icon-relative line length; a horizontal-only generic separator would not simplify it. |
| `DockSettingSlider.qml` | Keep | Already composes native `PanelSlider`; the wrapper adds SmartDock labels, formatting, snapping, and preview/commit semantics. |
| `DockSettings.qml` | Keep | Composes the settings surface, responsive layout, normalization, preview/commit paths, outside-click behavior, and host integration while already using native controls where appropriate. |
| `DockSettingsSection.qml` | Keep | Provides SmartDock's card/icon/title/description/accessory/content structure; `PanelSectionHeader` is only a styled header. |
| `DockSettingsToggleRow.qml` | Keep | Already composes native `ToggleSwitch`; the wrapper adds label/description layout plus row-wide pointer and keyboard activation. |
| `DockToolTip.qml` | Keep | Its Quickshell `PopupWindow` contract supports four dock edges, reanchoring, no focus grab, and an empty input mask; `PanelToolTip` is not equivalent. |
| `DockTrashItem.qml` | Keep | Trash state, drag/drop target behavior, magnification, actions, and menu integration are dock-specific. |
| `DockWindowPreview.qml` | Keep | Owns dock-relative preview-window lifecycle, anchoring, clipping, and interaction state. |
| `DockWindowPreviewTile.qml` | Keep | Window thumbnail/status/action presentation is domain-specific and tied to SmartDock window actions. |
| `DockWorkspaceGroup.qml` | Keep | Workspace card/header/window grouping and activation behavior are SmartDock presentation semantics. |
| `DockWorkspaceLayout.qml` | Keep | Owns viewport, overflow, active-workspace reveal, and grouped-dock geometry. |
| `DockWorkspaceStrip.qml` | Keep | Owns workspace visibility/count/focus presentation and horizontal/vertical dock adaptation. |

## Result

This audit found one high-confidence generic-control duplication worth replacing in this PR: `DockActionDropdown.qml`. The change deletes its custom popup, list delegates, option helpers, and keyboard implementation while preserving only the controlled-settings synchronization and existing label/layout composition.

No additional follow-up issue is created from this audit because the remaining visual components retain material SmartDock-specific responsibilities or already wrap the appropriate native primitive. Future replacements should be opened only when a concrete native component removes meaningful code without changing those contracts.

## Host-dependent validation handoff

The settings-binding regression intentionally lives in `local-tests/`, outside the headless CI `tests/` tree. On the Omarchy machine, run:

```bash
bash tests/run_action_dropdown_settings.sh
```

Exercise all six `DockActionDropdown` call sites through their existing settings paths: **Workspace layout**, **Workspaces from**, **Window scope**, **Left click**, **Middle click**, and **Scroll**. `Position` already uses native `ButtonGroup` and is not part of this refactor.

Then perform the FDM-858 physical smoke matrix on the exact PR head: mouse selection; Tab focus; Enter/Space open; arrow and `j`/`k` navigation; Escape dismissal; grouped-layout disabled dropdowns; label typography/spacing; Reset; external config reload without reopening Settings; and both standalone/overlay entry points. Record the installed Omarchy revision and exact PR head in the PR before moving it out of Draft.
