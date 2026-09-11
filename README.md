# SmartDock for Omarchy

> **Unreleased CLI-first candidate:** this branch belongs to
> [Draft PR #44](https://github.com/fernandodamaso/smart-omarchy-dock/pull/44),
> not a released `main` installation. Keep it unmerged and undeployed until the
> separate delivery gate is satisfied. The exact-SHA
> [local qualification runbook](docs/CLI_RUNTIME_CHECKS.md) is not a deployment command.

> Local Omarchy variant: pinned applications remain first, while grouped
> running applications from every workspace are appended automatically.

A theme-aware application, window, and workspace dock for Omarchy and Hyprland, built with Quickshell and Qt/QML.

![SmartDock for Omarchy running at the bottom of an Omarchy desktop](preview_2.png)

## Features

- Smooth pointer-distance magnification
- Freedesktop application icons and launching
- Configurable application-icon left, middle, and grouped-window scroll actions
- Optional grouped window previews when hovering application icons
- Focuses an existing application on another workspace
- Running-application indicators
- Dot-first application attention badges from live SNI/Hyprland state and available Omarchy notifications
- Reduced-motion bounded attention nudge with three-second reminders while attention remains active
- Optional authoritative application-provided launcher badge counts with dot fallback
- First-position sliders control for the app launcher, adding applications, and auto-hide
- Bundled Lucide SVG artwork for the Trash icon and dock context-menu actions
- Host-owned CLI configuration, app management, and local PNG/SVG icon overrides
- Optional dynamic Trash icon with item count, open, and confirmed empty actions
- Compact trailing workspace switcher that mirrors the Omarchy top-bar visibility rule
- Minimized-window markers, counts, tooltip summaries, and per-window status labels
- Fullscreen focus emphasis that enlarges the owner and fades other dock icons
- Per-window right-click management for workspace moves, fullscreen-with-bars,
  Hyprland-style minimize/restore, focus, and close
- Drag-to-reorder with persistent pinned-app order
- Context-menu hiding with persistent restoration through `smartdock apps show`
- Right-click actions to launch, close, pin, or unpin applications
- Fuzzy application search for adding dock items
- Configurable dock background transparency
- Omarchy theme-aware surfaces, borders, corner radius, typography, and hover states
- Optional reserved screen space while the dock is visible
- Optional auto-hide with screen-edge reveal
- Live JSON configuration reload
- Multi-monitor support

## Requirements

- Hyprland
- Quickshell 0.3 or newer
- Python 3 for the configuration CLI (standard library only)
- GLib's `gio` command for optional Trash integration
- A working freedesktop icon theme
- Optional numeric launcher counts: CMake, a C++20 compiler, and Qt 6.6+ Core/DBus development files to build the native provider

![SmartDock for Omarchy running at the bottom of an Omarchy desktop](preview.png)

## Install

Install the Git-managed Omarchy plugin from the SmartDock fork:

```bash
omarchy plugin add https://github.com/fernandodamaso/smart-omarchy-dock.git --enable --yes
```

The normal update command is:

```bash
omarchy plugin update io.github.fernandodamaso.smartdock --yes
```

Updates pull the fork's default `main` branch and preserve
`~/.config/smartdock/dock.json`. Installed plugin files are deployment state;
do not edit them directly. Development belongs in a separate clone, such as
`/home/admin/Projects/smart-omarchy-dock`, and changes reach an installed copy
through Git push followed by `omarchy plugin update`.

### Standalone installation

Standalone use is a secondary mode. From a source checkout, make sure
Quickshell is installed and run:

```bash
./install.sh
```

The installer uses only user directories, requires no `sudo`, and creates an
XDG autostart entry. To install without autostart, use
`./install.sh --no-autostart`.

Run the standalone dock immediately with:

```bash
smartdock --daemonize
```

Installed copies appear as **SmartDock for Omarchy** in application launchers.
Run `smartdock help` to see every command.

Manage autostart later from the CLI:

```bash
smartdock autostart status
smartdock autostart enable
smartdock autostart disable
```

### Update or remove

`smartdock update` only refreshes an installed standalone copy from its local
source copy. It does not update the Omarchy plugin; use the Git-managed
`omarchy plugin update` command above for that.

```bash
smartdock update
smartdock restart
smartdock uninstall
```

Uninstalling preserves the configuration; remove it too with
`smartdock uninstall --purge`.

## Run as an Omarchy plugin

Omarchy users should run SmartDock inside the existing Omarchy shell rather
than starting a second Quickshell process. The installed plugin ID is
`io.github.fernandodamaso.smartdock`:

```bash
omarchy plugin enable io.github.fernandodamaso.smartdock
```

The plugin uses `~/.config/smartdock/dock.json`, shared with the standalone
version. Do not run the standalone and plugin versions together, or two docks
will appear.

### Launcher badge count provider

Numeric counts are optional and provider-owned. Omarchy plugin installation
never compiles or executes an install hook. Build the small QtDBus provider from
a trusted source checkout when you want application-provided counts:

```bash
bash ./scripts/build-launcher-badge-provider
```

The script builds outside the Git checkout, runs the provider tests, and
installs only the resulting executable under
`${XDG_DATA_HOME:-$HOME/.local/share}/smartdock/providers/`. Reload or restart
the SmartDock plugin afterwards. If the binary, Qt runtime, D-Bus service, or an
application's launcher-count support is unavailable, SmartDock keeps the
FDM-809 attention dots; it does not poll or scrape another source for a number.

The provider listens to the established
`com.canonical.Unity.LauncherEntry.Update` session-bus protocol and accepts only
typed `count` and `count-visible` properties. Standalone SmartDock intentionally
does not own this provider and therefore remains dot-only. See
[`docs/launcher-badge-counts.md`](docs/launcher-badge-counts.md) for architecture,
compatibility, and local validation details.

SmartDock does not invoke Herdr or any recurring agent-status CLI. Agent-status
integration is intentionally excluded until a separate event-driven provider
exists; optional numeric counts remain limited to application-published
LauncherEntry state.

### Terminal-agent launchers

SmartDock bundles visible application entries that open these terminal agents
in separate Ghostty windows:

| Launcher | Desktop ID | Ghostty window class | Command |
| --- | --- | --- | --- |
| Pi | `smartdock-agent-pi` | `io.github.fernandodamaso.smartdock.agent.pi` | `pi` |
| Oh My Pi | `smartdock-agent-oh-my-pi` | `io.github.fernandodamaso.smartdock.agent.oh-my-pi` | `omp` |
| Command Code | `smartdock-agent-command-code` | `io.github.fernandodamaso.smartdock.agent.command-code` | `commandcode` |
| Cursor Agent | `smartdock-agent-cursor` | `io.github.fernandodamaso.smartdock.agent.cursor` | `cursor-agent` |
| Claude Code | `smartdock-agent-claude-code` | `io.github.fernandodamaso.smartdock.agent.claude-code` | `claude` |
| Kilo Code | `smartdock-agent-kilo-code` | `io.github.fernandodamaso.smartdock.agent.kilo-code` | `kilo` |
| Cline | `smartdock-agent-cline` | `io.github.fernandodamaso.smartdock.agent.cline` | `cline` |

Each launcher runs `ghostty --gtk-single-instance=false` with a unique, valid
GTK/Wayland application ID. Standalone users get these entries from the
normal `./install.sh`. Plugin users can install only the launchers and icons
from a SmartDock source checkout, without requiring Quickshell, installing a
second dock, enabling autostart, or changing the dock configuration:

```bash
./install.sh --agent-assets-only
```

The plugin itself is installed with:

```bash
omarchy plugin add https://github.com/fernandodamaso/smart-omarchy-dock.git --enable --yes
```

Agent grouping is best effort. SmartDock uses the terminal window's observed
title or agent marker as a fallback because these CLIs run inside a terminal,
so title updates can be delayed, overwritten by a shell, or unavailable. A
manually started Pi, Oh My Pi, or Kilo session usually retains a recognizable
title. Command Code, Cursor Agent, Claude Code, and Cline can replace their
branded title with arbitrary session or prompt text, so only their branded
startup/default phases are recognized outside the dedicated launchers. A
tab or split inside Ghostty usually shares the same top-level window and cannot
be separated reliably. The same limitation applies to multiple sessions in
tmux. An agent running over SSH or inside a container may expose only the local
shell/terminal title, so it can remain grouped under Ghostty instead of its
agent launcher. These entries still provide direct launches even when runtime
grouping cannot identify a session.
### Development

Development happens in the canonical source checkout or in your own clone,
never in the installed Omarchy checkout:

```bash
cd /home/admin/Projects/smart-omarchy-dock
./scripts/run
```

Quickshell watches the QML files, so UI changes reload while developing.

## Project history

SmartDock for Omarchy is an extensively developed MIT-licensed fork of
[nick-friedrich/hyprland-dock](https://github.com/nick-friedrich/hyprland-dock).
The upstream Git history, MIT license, and original copyright notice are
preserved in this repository.

## Configure

The [CLI reference](docs/CLI_REFERENCE.md) describes commands, JSON fields and
errors; the [configuration inventory](docs/CONFIGURATION.md) lists all 41
settings, declared defaults and dependencies. Both ship beside the offline
[agent guide](docs/AGENT_CONFIGURATION.md). Its recipes are executed against
the real CLI parser and production host/model harness in the existing CI;
that is not real Omarchy rendering or IPC qualification.

Use the selected running host through the CLI rather than editing a live
`dock.json`. Install just the client from a source checkout without starting a
second dock:

```bash
bash ./install.sh --cli-only
smartdock status --json
smartdock config schema --json
smartdock config get --json
smartdock config set iconSize 48 --json
smartdock agent-guide
```

The host reports its authoritative `data.configPath`; do not infer that path
from the working directory. Choose `--runtime plugin|standalone` and an exact
`--instance ID` when discovery needs disambiguation. No command silently starts
or restarts a host. Read the [agent configuration guide](docs/AGENT_CONFIGURATION.md)
for atomic patches, dry runs, persistence errors, reset scope and safe exports.
[`config/dock.json`](config/dock.json) contains bundled defaults, not necessarily
the running configuration.

Configuration is CLI-only: there is no settings window, live preference preview,
or graphical icon editor. The dock, ordinary window previews, application picker,
context menus, drag reordering, workspace controls and Trash remain available.
The first sliders icon opens the existing launcher/add-application/auto-hide menu.
Changes are applied through the same host-owned writer without resetting existing
preferences, pins, hidden apps, custom icons or extension keys.

Use `config set KEY VALUE` for a single preference and `config apply --stdin`
for a related batch. Background, border and workspace badge colors accept
`#RRGGBB`, Qt `#AARRGGBB`, and symbolic Omarchy tokens such as `@accent` or
`@menu.background`. Set the paired `Enabled` flag to use an override; set it to
`false` to follow the theme without discarding the saved override. Tokens keep
following live theme changes. Workspace badges default to accent with white text.

```bash
printf '%s\n' '{"backgroundColorEnabled":true,"backgroundColor":"@menu.background"}' | smartdock config apply --stdin --dry-run --json
printf '%s\n' '{"backgroundColorEnabled":true,"backgroundColor":"@menu.background"}' | smartdock config apply --stdin --json
smartdock config set backgroundColorEnabled false --json
smartdock config set showTrash false --json
smartdock config set interfaceAnimationsEnabled false --json
smartdock config reset hoverGlowOpacity --json
```

Inspect `applied`, `persisted` and `writeState` separately. A failed save may be
active for the session only; read status before `config retry`. A transport
timeout has an unknown outcome and requires readback before retrying. Preference
reset (`config reset --preferences`) preserves pins, hidden apps, icon overrides,
margin and unknown keys. Use a key reset for a narrow request.

`controlCommand` is executable configuration used later by the launcher action;
never execute it merely to validate a setting. Preference reset also resets this
command. Use runtime metadata and touched-key rollback rather than silently
falling back to raw configuration writes on an older or incompatible host.

The following is an example configuration shape, not a replacement snapshot to
apply. Read the running host's schema/defaults and preserve the user's values:

```json
{
  "iconOverrides": {},
  "iconSize": 42,
  "magnification": 1.2,
  "magnificationRadius": 95,
  "hoverGlowEnabled": true,
  "hoverGlowOpacity": 0.72,
  "hoverGlowRadius": 28,
  "showPreviews": true,
  "showTrash": true,
  "margin": 10,
  "backgroundOpacity": 0.88,
  "backgroundColorEnabled": false,
  "backgroundColor": "",
  "borderColorEnabled": false,
  "borderColor": "",
  "workspaceBadgeBackgroundColorEnabled": false,
  "workspaceBadgeBackgroundColor": "",
  "workspaceBadgeTextColorEnabled": false,
  "workspaceBadgeTextColor": "",
  "borderWidthEnabled": false,
  "borderWidth": 2,
  "position": "bottom",
  "fullLength": false,
  "reserveSpace": true,
  "autoHide": false,
  "clickAction": "focus-or-launch",
  "middleClickAction": "none",
  "scrollAction": "none",
  "controlCommand": "omarchy-menu toggle apps",
  "sortByWorkspace": false,
  "groupWindows": true,
  "interfaceAnimationsEnabled": true,
  "attentionBadgesEnabled": true,
  "urgentWindowAnimationEnabled": true,
  "launcherBadgeMode": "automatic",
  "hiddenApplications": [],
  "pinned": [
    "org.gnome.Nautilus",
    "com.mitchellh.ghostty",
    "chromium"
  ]
}
```

### Options

| Option | Description |
| --- | --- |
| `iconOverrides` | App-wide, SmartDock-only local PNG/SVG artwork by desktop ID; defaults to `{}`; use `icons set/reset/reload` |
| `iconSize` | Base icon size in pixels |
| `magnification` | Maximum icon scale under the pointer |
| `magnificationRadius` | Distance over which nearby icons magnify |
| `hoverGlowEnabled` | Show the accent glow behind the icon currently under the pointer |
| `hoverGlowOpacity` | Glow intensity from `0.0` (hidden) to `1.0` (full strength) |
| `hoverGlowRadius` | Glow blur radius as a percentage of the icon size, from `0` to `100` |
| `showPreviews` | When `true`, show grouped window previews while hovering application icons; defaults to `true` |
| `showTrash` | When `true`, show the Trash shortcut and count; disabling it removes the Trash section and pauses Trash polling |
| `margin` | Distance between the dock and screen edge |
| `backgroundOpacity` | Dock background opacity from `0.0` (transparent) to `1.0` (opaque) |
| `backgroundColorEnabled` | When `true`, use `backgroundColor` instead of Omarchy's menu background token |
| `backgroundColor` | Custom dock background in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@menu.background` |
| `borderColorEnabled` | When `true`, use `borderColor` instead of the theme border color |
| `borderColor` | Custom dock border color in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@accent` |
| `workspaceBadgeBackgroundColorEnabled` | When `true`, use `workspaceBadgeBackgroundColor` for application workspace-number badge backgrounds |
| `workspaceBadgeBackgroundColor` | Workspace badge background in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@accent` |
| `workspaceBadgeTextColorEnabled` | When `true`, use `workspaceBadgeTextColor` for application workspace-number badge text |
| `workspaceBadgeTextColor` | Workspace badge text in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@foreground` |
| `borderWidthEnabled` | When `true`, use `borderWidth` instead of the theme border width |
| `borderWidth` | Custom dock border width from `0` to `8` pixels |
| `position` | Screen edge: `top`, `bottom`, `left`, or `right` |
| `fullLength` | Fill the screen width, or height for a vertical dock |
| `workspaceLayout` | `flat` (default) or `grouped` workspace cards; grouped applies to top/bottom and scrolls when crowded |
| `workspaceMonitorScope` | Grouped cards: `all` (default) mirrors workspaces across docks; `current-monitor` shows only each dock’s monitor |
| `reserveSpace` | When `true` and `autoHide` is `false`, tiled windows stop beside the visible dock; hidden auto-hide docks do not reserve space |
| `autoHide` | Hide the dock until the pointer reaches its screen edge; can also be toggled from the right-click menu |
| `clickAction` | Action for an unmodified Left click; defaults to legacy-compatible `focus-or-launch` |
| `middleClickAction` | Action for an unmodified Middle click; defaults to `none` |
| `scrollAction` | Vertical scroll action; `cycle-windows` cycles grouped live windows, while `none` preserves pass-through |
| `controlCommand` | Shell command run by **Open App Launcher** in the first icon's controls menu; defaults to the stock `SUPER + ALT + SPACE` apps menu |
| `sortByWorkspace` | When `true`, group open apps by workspace number; closed pinned apps stay first |
| `groupWindows` | When `true`, combine an app's open windows into one dock icon; when `false`, show one icon per window |
| `interfaceAnimationsEnabled` | Animate workspace focus, card/icon insertion and removal, window moves, and context-menu opening; defaults to `true` |
| `windowScope` | Running-window visibility: `all`, `workspace`, `monitor`, or `workspace-monitor`; invalid/missing values use `all` |
| `showUrgentOutsideScope` | When enabled, a true Hyprland-urgent window may bypass a non-`all` scope; notification/SNI attention does not |
| `attentionBadgesEnabled` | Show application attention badges. FDM-809 dot severity remains the fallback; in automatic mode an authoritative positive visible launcher count may replace that dot. |
| `urgentWindowAnimationEnabled` | When `true`, active SNI, critical local-notification, or Hyprland urgent attention may nudge the owning application icon, no more than once every 3000 ms while attention remains. A launcher count alone never animates; a count with attention still does. Motion is effective only while `attentionBadgesEnabled` is also enabled; disabling it leaves the static badge intact. |
| `launcherBadgeMode` | `automatic` shows authoritative application-provided counts when available; `dots-only` ignores numeric provider state and preserves FDM-809 dots only. |
| `hiddenApplications` | Desktop-entry IDs hidden from the dock; applications remain running and pinned membership/order is preserved |
| `pinned` | Ordered desktop-entry IDs displayed in the dock |

### Application and icon commands

```bash
smartdock apps list --query 'Editor' --json
smartdock apps list --pinned --json
smartdock apps list --hidden --json
smartdock apps pin code --json
smartdock apps move code --before org.gnome.Nautilus --json
smartdock apps move code --after org.gnome.Nautilus --json
smartdock apps hide code --json
smartdock apps show code --json
smartdock apps show --all --json
smartdock apps unpin code --json
smartdock icons list --json
smartdock icons set code "$HOME/Pictures/Dock Icons/Ícone.svg" --json
smartdock icons reload code --json
smartdock icons reset code --json
```

Use actual IDs from `apps list`; the examples are not guaranteed installed IDs.
Discovery uses the host's native desktop-entry catalog and keeps unavailable
stored pins/hidden IDs visible in its output. IDs match exactly after case
folding and optional `.desktop` removal, never by fuzzy name. Pinning does not
unhide an app; hiding does not unpin it or close windows. Show only clears hidden
membership. Move requires two different pinned IDs and preserves the relative
order of all other entries, including hidden and unavailable pins. Repeating a
membership command is a no-op rather than another settings write.

`iconOverrides` defaults to `{}` and changes only SmartDock artwork. Each entry
applies across main icons, preview metadata and app-picker rows. It never changes
`.desktop` files, launch identity, window grouping, screenshots, badges, Trash or
action glyphs. A browser tab grouped as Chrome remains a Chrome item; custom
artwork does not split browser groups.

Only local static PNG/SVG files are accepted. Ordinary relative paths supplied
to the CLI are resolved from its current directory; the host accepts absolute
local paths and local `file:///` URLs, preserving spaces and Unicode. Remote
URLs and other formats are rejected. Files are referenced in place, not copied,
so keep them outside the plugin checkout. Per-app set/reset preserves unrelated
map entries. Preference reset also preserves `iconOverrides`.

The bounded fallback is **custom file → original desktop icon →
`application-x-executable` → bundled theme-tinted `app-window` glyph**. Custom
artwork is not tinted. Missing or corrupt images retain the requested mapping
and fall back instead of being silently removed.

There is no continuous artwork-file watch. After replacing bytes at the same
path, use `icons reload ID`; it bumps the global artwork revision without writing
settings, and other mapped icons may refresh too. Setting an equivalent source
also requests a reload without a redundant save. Every successful icon response
reports `renderVerified: false`: persistence and reload requests do not prove
image decoding or a visible redraw. Real rendering/cache behavior is reserved
for local Omarchy qualification, not claimed by headless tests.

### Application pointer actions

The Left and Middle click keys accept the same vocabulary: `none`,
`minimize-restore`, `previews`, `close`, and `focus-or-launch`. `scrollAction`
is intentionally narrower: `none` or `cycle-windows`.

```bash
smartdock config set clickAction focus-or-launch --json
smartdock config set middleClickAction none --json
smartdock config set scrollAction cycle-windows --json
```

Input precedence is intentionally strict:

- Right click always opens the existing application context menu.
- Left click with no modifier uses `clickAction`.
- Middle click with no modifier uses `middleClickAction`.
- Vertical-dominant scrolling uses `scrollAction`; horizontal/tied gestures pass through.
- Ctrl, Alt, Meta, Shift, and mixed modifier combinations do not trigger scroll actions.

The current action semantics are:

- `none`: no action.
- `minimize-restore`: all-or-nothing grouped behavior. If any member is visible,
  all visible members are minimized through the host-owned window controller;
  if all are minimized, all are restored through the same recorded-origin
  state.
- `previews`: show the grouped window preview popup when `showPreviews` is
  enabled. The same popup also opens after briefly hovering an application with
  two or more running windows.
- `close`: request graceful closure of every live grouped member.
- `focus-or-launch`: preserves the legacy Left click behavior exactly: repeated
  clicks focus successive windows in a running group in dock order, while a closed pinned
  application launches.

Existing configuration files need no migration. If either action key is absent,
it normalizes to its default; an absent or invalid legacy `clickAction`
normalizes to `focus-or-launch`. Older `focus` and `launch` action values are
also normalized to `focus-or-launch`, so existing settings retain their useful
behavior. Invalid values for `middleClickAction` normalize to `none`. Missing or invalid
`scrollAction` values also normalize to `none`, so existing configurations keep
their current behavior. When set to `cycle-windows`, scroll input is consumed
only for a grouped icon with at least two live windows. High-resolution vertical
deltas accumulate in 120-unit steps, residual input resets after about 220 ms,
and minimized targets restore through the shared host-owned window controller
before focus.

### Window scope filtering

`windowScope` filters individual running windows before grouping. `all` preserves
existing behavior; `workspace` uses the workspace active on Hyprland's focused
monitor; `monitor` uses each Dock's own screen/monitor; and
`workspace-monitor` requires both. Closed pinned launchers stay visible.

```bash
smartdock config set windowScope workspace --json
smartdock config set showUrgentOutsideScope true --json
```

When `showUrgentOutsideScope` is enabled, only Hyprland's actual per-window
urgent state bypasses scope. Explicitly hidden applications still stay hidden.
SmartDock-minimized windows use the shared host-owned workspace/monitor origin;
unknown or transient location data fails open so the only restore affordance is
not lost. Scope refresh is debounced once in `DockHost.qml` for all monitor
Docks, with no per-Dock `hyprctl` polling.

### Grouped-window wheel cycling

Attention dots deliberately represent **attention state**, not inferred unread
counts. SmartDock reduces three FDM-809 sources when they are available:
StatusNotifierItem `NeedsAttention`, Hyprland's live urgent state/events, and
the Omarchy notification service. Notification events are never counted.
Identity matching is exact after case-folding and an optional `.desktop` suffix
removal; desktop-entry ID, application ID, `startupClass`, display name, and
explicitly configured aliases are accepted, but substring/fuzzy matching is
not. Grouped applications render one badge; ungrouped applications assign the
badge to the first visible item for that app. Hidden applications do not render
a badge.

FDM-814 motion follows active badge severity: SNI `NeedsAttention`, critical
local-notification attention, and Hyprland urgent window state can trigger the
nudge. A previously absent Hyprland urgent **window address** still creates a
motion revision, while duplicate urgency for an address that remains urgent
does not. A launcher count without attention never triggers motion; a count
coexisting with attention still does. Titles, notification bodies,
terminal/editor output, sender data, and window content never create a motion
trigger. Each play is the bounded `0 -> 5 -> 0 -> 3 -> 0` px sequence over
about 520 ms with OutCubic easing; reminders repeat no more than once every
3000 ms while attention remains active. Hover, drag, context menus, and preview
interaction suppress motion without clearing the badge. Auto-hidden docks do
not reveal for attention; pending timer/reveal retries remain safe while the
badge is active. Hidden/restored applications and startup prime at the current
revision so stale urgency is not replayed. See
[`docs/attention-badges.md`](docs/attention-badges.md) for ownership and motion
semantics.

When the optional launcher provider is available and `launcherBadgeMode` is
`automatic`, a positive count with `count-visible=true` takes precedence over
the attention dot. Counts above 99 render as `99+`. Explicit zero or
`count-visible=false` hides the number and allows any current FDM-809 attention
dot to remain visible. `dots-only` ignores numeric state entirely. The count is
authoritative application state: focusing a window does **not** clear it.
Provider sender disconnects clear sender-owned state, and reconnects start from
fresh state rather than carrying stale fields across process ownership.

Dismissing a notification popup does not mark local attention read. Local
notification attention expires after 24 hours and clears only after the matched
application remains focused for about 800 ms. Live SNI state and authoritative
launcher counts are never cleared by SmartDock focus handling. Standalone mode,
or an Omarchy host without either optional service, simply omits the unavailable
source while the remaining FDM-809 sources continue to work.

The first dock icon is always the dock controls icon and is not part of
`pinned`. Clicking it opens the controls menu; **Open App Launcher** runs
`controlCommand`, while the menu also exposes Add Application and the auto-hide
toggle. Application context menus contain only application and window actions.
For example, with the Omarchy app-launcher plugin already installed:

```bash
smartdock config set controlCommand "omarchy-shell shell toggle tyrsolution.app-launcher '{}'" --json
```

The trailing Trash and workspace controls are not part of `pinned`. Trash uses
the freedesktop `trash:///` location and can be removed from the dock with
`showTrash`; while hidden, SmartDock also pauses its recurring Trash count
query. Workspace buttons always include 1 and 2, then add any focused or
occupied workspace through 10; clicking a number focuses it.

Pinned values are desktop-entry IDs. List the authoritative running host's IDs with:

```bash
smartdock apps list --json
```

Right-click any application in the dock and choose **Hide from Dock** to hide
the whole application while leaving its windows running and its pinned
membership unchanged. The canonical desktop-entry ID is stored in
`hiddenApplications`, so the choice persists across restarts and live config
reloads. Inspect hidden apps with `smartdock apps list --hidden --json`; use
`smartdock apps show ID --json` to restore one or `smartdock apps show --all --json`
to clear hidden membership. Restoring an application returns it to its existing
pinned position without pinning or unpinning anything. `config reset --preferences`
intentionally preserves `hiddenApplications` and the other application collections.

The configuration file is watched and updates automatically. Drag a dock icon to another slot to reorder it; the new `pinned` order is written back to this file. Reserved space follows visibility: while auto-hide is off, the `reserveSpace` option decides whether tiled windows keep a clear dock-sized area; while auto-hide is on, the hidden dock never reserves space.

Surface override settings are independent. Leave an `*Enabled` flag set to
`false` to follow the active Omarchy theme; enable it to use the matching
custom color or width. Custom background alpha is multiplied by
`backgroundOpacity` just like the theme background.

For a full-height vertical dock on the left, use one related patch:

```bash
printf '%s\n' '{"position":"left","fullLength":true}' | smartdock config apply --stdin --json
```

### Disable cursor warping

Hyprland controls whether the pointer moves when focus switches to a window on another workspace. This is compositor-wide behavior and cannot be reliably overridden by the dock.

On Omarchy, add this override to `~/.config/hypr/looknfeel.lua`:

```lua
hl.config({
  cursor = {
    warp_on_change_workspace = 0,
  },
})
```

Hyprland normally reloads after the file is saved. Validate the configuration with:

```bash
hyprctl reload
hyprctl configerrors
```

This disables cursor warping for all workspace changes, not only dock clicks.

## Roadmap

- Theme integration

## License

[MIT](LICENSE)

### Workspace cards (opt-in)

Use `smartdock config set workspaceLayout grouped --json` to enable horizontal
workspace cards. Use `smartdock config set workspaceLayout flat --json` to roll
back. Missing/invalid values and `config reset workspaceLayout` use flat.
Left/right positions render flat without changing the saved preference. Window
scope, workspace sorting and urgent-outside-scope affect the flat layout; their
saved values are preserved. `groupWindows` remains effective in either layout.

By default, `workspaceMonitorScope: all` shows the same workspaces, apps, and
globally focused workspace highlight on every monitor dock. Use
`smartdock config set workspaceMonitorScope current-monitor --json` for local
workspace membership and active highlighting, or set it to `all` to restore the
default. Missing/invalid values and `config reset workspaceMonitorScope` use all;
existing settings need no migration. This setting affects grouped layouts only;
flat layouts keep their existing window scope. Clicking a remote workspace or
app focuses it where it lives without moving it.

Every normal workspace in the selected scope always shows all its app icons inside a rounded translucent card, including inactive workspaces. Cards use narrow workspace labels and a subtle tint across the active group; the label and card styling identify focus. Window counts remain in the header tooltip. Click a header to switch workspaces. Empty workspaces retain their header. Closed pinned launchers and **Other windows** (unknown/special membership) stay outside normal cards. With `current-monitor`, known windows on another monitor are excluded. Window actions and previews use only the item's members; hide and launcher pinning remain application-wide. Grouped dragging and redundant per-icon workspace labels are disabled.

Grouped minimize/restore requires a validated recorded workspace: an unknown origin never moves a window to a guessed focused workspace. Flat mode retains its fallback. Sticky windows appear once on their monitor’s active normal workspace with a small marker; minimized windows retain their recorded origin. Local urgency marks its workspace and member icons. App-wide notification badges have one visible owner per app per dock, without claiming a notification belongs to a workspace.

Crowded cards scroll inside a bounded horizontal viewport. Use the previous/next buttons with a mouse; app wheel cycling keeps its configured behavior. Dock Controls and optional Trash stay fixed. Switching workspaces brings the active header into view, and scrolling a popup’s icon out of view closes the popup. Compact and full-length layouts retain magnification headroom. Horizontal workspace cards use a slimmer surface and tighter spacing without changing the configured icon size; application and utility tiles highlight on hover.

Both dock layouts use hover-highlighted icon tiles, accent window-count badges,
a broad focus underline, and spaced utility separators. Flat mode includes a
rounded workspace selector with a tinted active pill; grouped mode keeps every
workspace’s icons visible. Icon size, surface overrides and Show Trash still apply.
