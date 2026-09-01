# SmartDock for Omarchy

> Local Omarchy variant: pinned applications remain first, while grouped
> running applications from every workspace are appended automatically.

A theme-aware application, window, and workspace dock for Omarchy and Hyprland, built with Quickshell and Qt/QML.

![SmartDock for Omarchy running at the bottom of an Omarchy desktop](preview_2.png)

## Features

- Smooth pointer-distance magnification
- Freedesktop application icons and launching
- Focuses an existing application on another workspace
- Running-application indicators
- First-position sliders control for the app launcher, Dock Settings, adding
  applications, and auto-hide
- Bundled Lucide SVG artwork for the Trash icon and dock context-menu actions
- Theme-aware graphical settings panel with live previews and persistent changes
- Dynamic Trash icon with item count, open, and confirmed empty actions
- Compact trailing workspace switcher that mirrors the Omarchy top-bar visibility rule
- Minimized-window markers, counts, tooltip summaries, and per-window status labels
- Fullscreen focus emphasis that enlarges the owner and fades other dock icons
- Per-window right-click management for workspace moves, fullscreen-with-bars,
  Hyprland-style minimize/restore, floating, workspace pinning, focus, and close
- Drag-to-reorder with persistent pinned-app order
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
- GLib's `gio` command for Trash integration
- A working freedesktop icon theme

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

Installed copies use `~/.config/smartdock/dock.json`. When running from the repository, edit [`config/dock.json`](config/dock.json):

The same settings are available graphically: click or right-click the first
sliders icon and choose **Dock Settings…**. Slider changes preview while dragging and
are saved when released; switches and choices save immediately. The panel
expands to a wide two-column layout on desktop screens so the full form is
visible without vertical scrolling; narrow displays fall back to the
scrollable layout. The centered panel leaves the dock's edge strip interactive,
so moving over dock icons continues to preview magnification and hover glow while
you adjust settings.

Background and border override rows include clickable theme-aware swatches.
They open a color dialog with alpha support; manual hex entry remains available
and accepts the same `#RRGGBB` / `#AARRGGBB` values. Each row also includes a
ready-to-choose list of Omarchy theme tokens (for example `@accent`,
`@menu.background`, and `@popups.border`). The selector shows a live color
square for every token, including the currently selected value. Selecting a
token stores the symbolic reference, so its color follows future theme
changes; choosing a hex value stores a fixed override.

```json
{
  "iconSize": 42,
  "magnification": 1.2,
  "magnificationRadius": 95,
  "hoverGlowEnabled": true,
  "hoverGlowOpacity": 0.72,
  "hoverGlowRadius": 28,
  "margin": 10,
  "backgroundOpacity": 0.88,
  "backgroundColorEnabled": false,
  "backgroundColor": "",
  "borderColorEnabled": false,
  "borderColor": "",
  "borderWidthEnabled": false,
  "borderWidth": 2,
  "position": "bottom",
  "fullLength": false,
  "reserveSpace": true,
  "autoHide": false,
  "clickAction": "focus-or-launch",
  "controlCommand": "omarchy-menu toggle apps",
  "sortByWorkspace": false,
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
| `iconSize` | Base icon size in pixels |
| `magnification` | Maximum icon scale under the pointer |
| `magnificationRadius` | Distance over which nearby icons magnify |
| `hoverGlowEnabled` | Show the accent glow behind the icon currently under the pointer |
| `hoverGlowOpacity` | Glow intensity from `0.0` (hidden) to `1.0` (full strength) |
| `hoverGlowRadius` | Glow blur radius as a percentage of the icon size, from `0` to `100` |
| `margin` | Distance between the dock and screen edge |
| `backgroundOpacity` | Dock background opacity from `0.0` (transparent) to `1.0` (opaque) |
| `backgroundColorEnabled` | When `true`, use `backgroundColor` instead of Omarchy's menu background token |
| `backgroundColor` | Custom dock background in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@menu.background` |
| `borderColorEnabled` | When `true`, use `borderColor` instead of Omarchy's menu border token |
| `borderColor` | Custom dock border color in `#RRGGBB`, `#AARRGGBB`, or an Omarchy token such as `@accent` |
| `borderWidthEnabled` | When `true`, use `borderWidth` instead of the theme border width |
| `borderWidth` | Custom dock border width from `0` to `8` pixels |
| `position` | Screen edge: `top`, `bottom`, `left`, or `right` |
| `fullLength` | Fill the screen width, or height for a vertical dock |
| `reserveSpace` | When `true` and `autoHide` is `false`, tiled windows stop beside the visible dock; hidden auto-hide docks do not reserve space |
| `autoHide` | Hide the dock until the pointer reaches its screen edge; can also be toggled from the right-click menu |
| `clickAction` | `focus-or-launch` focuses an existing window; `launch` always starts a new instance |
| `controlCommand` | Shell command run by **Open App Launcher** in the first icon's controls menu; defaults to the stock `SUPER + ALT + SPACE` apps menu |
| `sortByWorkspace` | When `true`, group open apps by workspace number; closed pinned apps stay first |
| `pinned` | Ordered desktop-entry IDs displayed in the dock |

The first dock icon is always the dock controls icon and is not part of
`pinned`. Clicking it opens the controls menu; **Open App Launcher** runs
`controlCommand`, while the menu also exposes Dock Settings, Add Application,
and the auto-hide toggle. Application context menus contain only application
and window actions. For example, to use the Omarchy app
launcher plugin instead of the stock apps menu:

```json
{
  "controlCommand": "omarchy-shell shell toggle tyrsolution.app-launcher '{}'"
}
```

The trailing Trash and workspace controls are fixed dock utilities and are
also not part of `pinned`. Trash uses the freedesktop `trash:///` location.
Workspace buttons always include 1 and 2, then add any focused or occupied
workspace through 10; clicking a number focuses it.

Pinned values are desktop-entry filenames without the `.desktop` suffix. List available IDs with:

```bash
find /usr/share/applications ~/.local/share/applications \
  -type f -name '*.desktop' 2>/dev/null \
  | sed 's#.*/##; s/\.desktop$//' | sort -u
```

The configuration file is watched and updates automatically. Drag a dock icon to another slot to reorder it; the new `pinned` order is written back to this file. Reserved space follows visibility: while auto-hide is off, the `reserveSpace` option decides whether tiled windows keep a clear dock-sized area; while auto-hide is on, the hidden dock never reserves space.

The three surface override settings are independent. Leave an `*Enabled`
flag set to `false` to follow the active Omarchy theme; enable it to use the
matching custom color or width. Custom background alpha is multiplied by
`backgroundOpacity` just like the theme background.

For a full-height vertical dock on the left, use:

```json
{
  "position": "left",
  "fullLength": true
}
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
