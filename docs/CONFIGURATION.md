# SmartDock configuration inventory

**Unreleased CLI-first candidate.** Discover `smartdock config schema --json` on the selected running host before changing it. Its keyed metadata and `config/dock.json` are the runtime/default authorities; this table is a tested reference, not a second settings engine or a replacement for the user's configuration.

Use [the agent workflow](AGENT_CONFIGURATION.md) for minimal, reversible changes and [the CLI reference](CLI_REFERENCE.md) for command/output/error details. CLI preferences and icons replace the removed Settings page; ordinary dock menus, app picker and window previews remain.

## All declared settings

Defaults below are JSON literals. `tests/test_cli_docs.py` checks these 41 rows against the shipped defaults. Bounds apply to new CLI writes; compatible legacy requested values survive unrelated changes. There is no automatic whole-file migration.

| Key | Declared default | New-write type, limits and dependencies |
| --- | --- | --- |
| `iconOverrides` | `{}` | Object mapping canonical app IDs to local PNG/SVG sources; prefer per-app intents. Preserved by preference reset. |
| `iconSize` | `42` | Integer 24–96 logical pixels. |
| `magnification` | `1.2` | Number 1–2; effective step 0.05. Set 1 for no hover enlargement. |
| `magnificationRadius` | `95` | Number 40–240; effective step 5. |
| `hoverGlowEnabled` | `true` | Boolean; gates the hover glow. |
| `hoverGlowOpacity` | `0.72` | Number 0–1; effective step 0.05. |
| `hoverGlowRadius` | `28` | Number 0–100; effective step 5; relevant when glow is enabled. |
| `showPreviews` | `true` | Boolean; permits ordinary grouped-window previews and the previews pointer action. |
| `showTrash` | `true` | Boolean; false removes Trash and pauses its polling, never empties it. |
| `margin` | `10` | Nonnegative integer, no arbitrary maximum; preserved by preference reset. |
| `backgroundOpacity` | `0.88` | Number 0–1; effective step 0.05; multiplies background color alpha. |
| `backgroundColorEnabled` | `false` | Boolean; enables the paired background override. |
| `backgroundColor` | `""` | Color string; requires backgroundColorEnabled. |
| `borderColorEnabled` | `false` | Boolean; enables the paired border override. |
| `borderColor` | `""` | Color string; requires borderColorEnabled. |
| `workspaceBadgeBackgroundColorEnabled` | `false` | Boolean; enables the paired workspace-number badge background override. |
| `workspaceBadgeBackgroundColor` | `""` | Color string; requires workspaceBadgeBackgroundColorEnabled. |
| `workspaceBadgeTextColorEnabled` | `false` | Boolean; enables the paired workspace-number badge text override. |
| `workspaceBadgeTextColor` | `""` | Color string; requires workspaceBadgeTextColorEnabled. |
| `borderWidthEnabled` | `false` | Boolean; enables a fixed width instead of theme-owned widths. |
| `borderWidth` | `2` | Integer 0–8 logical pixels; relevant only with borderWidthEnabled. |
| `position` | `"bottom"` | String: top, bottom, left, right. Vertical edges render workspaceLayout as flat. |
| `fullLength` | `false` | Boolean; extend along the available edge. |
| `reserveSpace` | `true` | Boolean; effective false while autoHide is enabled, without erasing this request. |
| `autoHide` | `false` | Boolean; existing edge-reveal auto-hide, not a new hide-mode enum. |
| `clickAction` | `"focus-or-launch"` | String: none, minimize-restore, previews, close, focus-or-launch. Close is destructive-on-use. |
| `middleClickAction` | `"none"` | Same canonical action vocabulary as clickAction. |
| `scrollAction` | `"none"` | String: none or cycle-windows. |
| `controlCommand` | `"omarchy-menu toggle apps"` | Nonempty string; executable-on-use launcher configuration, never executed by validation. |
| `sortByWorkspace` | `false` | Boolean; flat-layout workspace sorting; closed pins remain first. |
| `workspaceLayout` | `"flat"` | String: flat or grouped. Grouped cards render on top/bottom only. |
| `workspaceMonitorScope` | `"all"` | String: all or current-monitor; grouped cards only. |
| `groupWindows` | `true` | Boolean; group an application's windows; applies in both layouts. |
| `interfaceAnimationsEnabled` | `true` | Boolean; interface transitions, not every compositor animation or attention nudge. |
| `windowScope` | `"all"` | String: all, workspace, monitor, workspace-monitor; flat-layout running-window filtering. |
| `showUrgentOutsideScope` | `true` | Boolean; genuinely urgent windows may bypass flat window scope; hidden apps remain hidden. |
| `attentionBadgesEnabled` | `true` | Boolean; gates attention indicators without installing a notification daemon. |
| `urgentWindowAnimationEnabled` | `true` | Boolean; existing bounded attention motion, also gated by attentionBadgesEnabled in rendering. |
| `launcherBadgeMode` | `"automatic"` | String: automatic or dots-only. Uses an already-available provider; does not start/install one. |
| `browserProfileBadgesEnabled` | `true` | Boolean; per-window browser profile corner badges (photo or initial) from the browser-profile provider. No provider or DevTools endpoint means no badges; the setting installs nothing. |
| `hiddenApplications` | `[]` | Safe desktop ID array with no new canonical duplicates; independent of pins and retained by preference reset. |
| `pinned` | `["org.gnome.Nautilus","com.google.Chrome","com.mitchellh.ghostty","code","obsidian","chatgpt"]` | Ordered safe desktop ID array, including unavailable/hidden apps; no new canonical duplicates; retained by preference reset. |

## Requested, effective and rendered

Requested settings retain accepted intent: `hoverGlowOpacity: 0.72` projects to 0.70, `hoverGlowRadius: 28` to 30, and `backgroundOpacity: 0.88` to 0.90. A requested grouped layout survives moving to a vertical edge; effective layout becomes flat and effective workspaceMonitorScope becomes all. Auto-hide makes effective reserveSpace false without rewriting the requested value. New pointer writes require canonical values; stored legacy `focus`/`launch` aliases read effectively as `focus-or-launch` without an unrelated rewrite.

Effective output is a headless projection, not complete rendered truth. Theme-owned/token colors and theme-owned border width are null with a warning. The normalized urgentWindowAnimationEnabled flag does not by itself report badge-gated animation eligibility; the renderer also requires attentionBadgesEnabled and eligible live attention. Numeric launcher counts alone do not trigger motion. Standalone remains dot-only without the plugin-owned provider. Report these dependencies rather than inventing a fully resolved effective value.

Colors accept an empty string, `#RRGGBB`, Qt **`#AARRGGBB`** (alpha first), or a syntactically valid symbolic token. Pair each color with its Enabled flag in one atomic patch. Disabling only that flag restores inheritance without discarding the stored override. An empty override inherits the theme. Unknown symbolic tokens are retained and use renderer fallback rather than being silently deleted; the CLI does not certify that a token exists in the installed theme.

Existing token families include:

```text
@background @foreground @accent @muted @urgent
@bar.background @bar.text @bar.active
@popups.background @popups.text @popups.border
@tooltip.background @tooltip.text @tooltip.border
@menu.background @menu.text @menu.border
@menu.selected-background @menu.selected-text @menu.selected-border
@notifications.background @notifications.text @notifications.border @notifications.countdown
```

Colors remain live theme bindings after Settings removal. Custom background alpha is multiplied by backgroundOpacity. Workspace-number badges inherit accent/white when their overrides are disabled. Image artwork is a separate local-file mapping, not a color token; custom images are not tinted.

## Layout, windows and identity

Workspace cards and window filtering are different features. Grouped cards organize all matching workspace members using workspaceMonitorScope; flat layout retains windowScope, sortByWorkspace and urgent-outside-scope filtering. Do not move a vertical dock without authorization merely to make cards visible. In flat layout, workspace scope uses the focused monitor's active workspace, monitor scope uses each dock's screen, and combined scope requires both. Closed pinned launchers remain visible; explicitly hidden applications remain hidden. Minimized origins and transient location fallbacks remain owned by the shared window controller.

Right click remains the context menu. Existing modifier precedence, grouped close/minimize/restore and wheel rules remain unchanged. Pinning does not show a hidden app; hiding does not unpin/close it; unpinning does not hide a running app. Restore and move use exact host-discovered IDs and preserve unrelated order, including unavailable entries. Application display-name queries are discovery, not mutation identities.

Icon overrides are app-wide and SmartDock-only. Set/reset changes one latest-map entry, including for an unavailable safe identity, without changing desktop files, launch commands, grouping or screenshots. The local PNG/SVG is referenced in place. Use explicit reload after same-path byte replacement. Missing/corrupt artwork retains the mapping and uses the bounded original/generic/bundled-glyph fallback. All CLI icon acknowledgments retain `renderVerified: false`.

## Reset, preservation and executable settings

`config reset --preferences` preserves pinned, hiddenApplications, iconOverrides, margin and unknown extension keys; **controlCommand is reset** along with other preferences. `config reset KEY` explicitly resets that key even if it is normally preserved. Do not perform a broad reset for a narrow request.

Existing unknown keys and untouched legacy values survive minimal mutations. New unknown keys are rejected. An explicit array/object patch replaces that whole key, not a deep merge. Prefer `apps`/`icons` commands for individual membership/order/artwork changes and touched-key rollback after fresh readback.

`controlCommand` is executable configuration: store only an intentionally chosen command, quote it literally, and never run it merely to check validity. The existing launcher action can execute it later. Pointer `close` can close every live member of an application group when used. Changes to either require explicit intent; schema reads, dry runs and metadata validation do not execute them.
