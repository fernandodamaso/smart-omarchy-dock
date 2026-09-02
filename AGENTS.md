# AGENTS.md

## Project overview

This is a Hyprland application dock implemented with Quickshell and Qt/QML. It runs either as a standalone Quickshell configuration or as an Omarchy Quattro overlay plugin hosted by the existing Omarchy shell.

## Development

- The canonical source checkout is `/home/admin/Projects/smart-omarchy-dock`.
- Installed Omarchy plugin checkouts are read-only deployment state; never edit
  them directly. Push validated changes from the source checkout, then update
  the installed plugin through `omarchy plugin update`.
- Releases are cut from validated `main`. Imports from `upstream` are explicit
  review work on a dedicated branch and must pass the complete validation gate.
- Run the dock with `./scripts/run`.
- Keep the standalone entry point at `shell.qml` and the Omarchy plugin entry point at `Overlay.qml`.
- Keep shared host behavior in `DockHost.qml`; never start a second Quickshell process from the plugin.
- Keep window lifecycle actions and SmartDock-minimized origins in the single
  `DockWindowActions` instance owned by `DockHost.qml`; per-screen docks and
  context menus must consume that shared controller rather than duplicate it.
- Keep mouse-wheel cycling grouped-only. `DockItem.qml` may own transient wheel
  accumulation/delivery state, but live-member selection, active-member origin,
  minimized restore, focus, and stale-window handling must stay in the shared
  host-owned `DockWindowActions` / `DockWindowModel` path.
- Put reusable visual components in `components/`.
- Keep user-facing defaults in `config/dock.json` and mirror fallback defaults in `shell.qml`.
- Installed user settings live outside the application at `~/.config/smartdock/dock.json`; updates must never overwrite them.
- Keep `install.sh`, `uninstall.sh`, and `scripts/smartdock` compatible with custom XDG directory variables.
- Prefer Quickshell APIs over shelling out to external commands.
- Use freedesktop desktop-entry IDs without the `.desktop` suffix.
- Preserve live configuration reloads.

## Validation

Before committing changes:

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh tests/check_pointer_actions.sh tests/check_window_cycling.sh
bash tests/check_window_actions.sh
bash tests/check_pointer_actions.sh
bash tests/check_window_cycling.sh
qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml shell.qml
git diff --check
```

For FDM-808 specifically, manual Omarchy/Hyprland validation must cover a
normal mouse wheel, high-resolution and natural-scroll input, grouped windows
across workspaces, minimized-member restore/focus, rapid member closure,
single-window pass-through, and two-monitor behavior. Do not infer these
runtime results from pure-model or structural checks.

A portal warning about an application ID already being registered can occur when another Quickshell process is running; it is not a dock failure.

## Style

- Use two-space indentation in QML.
- Keep JavaScript helpers small and local to the component that owns the behavior.
- Add new configuration options to both `config/dock.json` and the README.
