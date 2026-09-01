# Changelog

## 1.1.1-custom.18 - 2026-09-01

### Added

- Added a theme-aware Dock Settings panel with live previews, persistent controls, and reset-to-defaults support.
- Added a dynamic Trash utility with open, item-count, empty/full icon, and confirmed Empty Trash actions.
- Added compact workspace navigation at the trailing edge using the same visibility rule as the configured Omarchy workspace widget.
- Added independent opt-in dock background color, border color, and border width overrides in Dock Settings.
- Added clickable alpha-aware color swatches beside the background and border hex fields.
- Added ready-to-choose Omarchy theme-token presets for dock background and border colors; symbolic selections follow theme changes.
- Added live color squares to each theme-token selector option and its selected-value trigger.
- Added Dock Settings controls for enabling hover glow and adjusting its intensity and radius.

### Changed

- Renamed the user-facing dock branding to **SmartDock for Omarchy** while
  preserving the existing plugin ID, commands, configuration path, and
  internal Hyprland workspace namespace for compatibility.
- Replaced the first dock item's grid artwork with a sliders-style controls icon.
- Split the dock into leading controls, centered applications, and trailing utilities so full-length and vertical layouts remain organized.
- Kept dock-wide settings, application pinning, and auto-hide actions exclusively in the controls icon menu.
- Tied reserved screen space to visibility so the dock reserves a dock-sized area only while auto-hide is disabled; the Reserve space control is disabled while auto-hide is enabled.
- Added themed glyphs to the Dock Settings, Add Application, and Auto-Hide actions.
- Colorized the symbolic Trash icon with white/accent states and aligned workspace controls to the same icon centerline at every dock edge.
- Made the idle Trash glyph fully opaque white; it still changes to the theme accent while hovered.
- Reworked Dock Settings into a responsive 980 px two-column layout so desktop screens avoid vertical scrolling.
- Bundled Lucide `trash-2` artwork and matching Lucide icons for dock and window context-menu actions.
- Clicking the controls icon now opens its menu; the menu's **Open App Launcher** action runs the configured launcher command.
- Centered application, control, Trash, and workspace icons symmetrically on every dock edge.
- Moved application, controls, and Trash hover labels to popup-backed tooltips so long names remain visible at dock edges.
- Replaced hover fill-and-border tiles with a soft theme-accent glow behind each magnified icon.
- Forced the color picker to use an in-overlay Quick implementation so GTK's native
  color window cannot appear behind Dock Settings.
- Kept the dock's edge input strip available while Dock Settings is open, so hover
  magnification and glow previews remain visible during live edits.
- Released Hyprland's compositor-wide exclusive pointer routing after the settings
  surface acquires keyboard focus, restoring dock hover events reliably.

## 1.1.1-custom.17 - 2026-09-01

### Fixed

- Removed the workspace badge border and restored white workspace numbers without changing the separate hover tooltip styling.

## 1.1.1-custom.16 - 2026-09-01

### Changed

- Removed borders from dock tooltips and made tooltip labels white for clearer contrast.

## 1.1.1-custom.15 - 2026-09-01

### Changed

- Made workspace number badges opaque and accent-colored so they remain visible over application icons.

## 1.1.1-custom.14 - 2026-09-01

### Changed

- Replaced dock, menu, picker, tooltip, badge, border, radius, typography, and hover styling with Omarchy theme tokens.
- Kept `backgroundOpacity` as a user-controlled multiplier on the active theme surface alpha.
- Made standalone launches expose the same Omarchy QML modules without modifying `/usr/share/omarchy`.

## 1.1.1 - 2026-08-22

### Added

- Optional auto-hide with animated screen-edge reveal, configurable through `autoHide` or the dock context menu.

### Fixed

- Keep the revealed dock's full interaction area clickable and allow more time to move from the screen edge to an icon.

## 1.1.0 - 2026-08-22

### Added

- Drag-to-reorder pinned applications with automatic config persistence.
- Right-click actions to open a new window or close a running application.
- Fuzzy application picker and right-click actions for pinning or unpinning apps.
- Configurable dock background transparency through `backgroundOpacity`.

### Fixed

- Focus existing browser-based web apps instead of launching duplicate windows.
