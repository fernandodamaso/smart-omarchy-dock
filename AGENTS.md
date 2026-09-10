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
- Follow `docs/DELIVERY.md` for PR-only delivery, exact-SHA evidence, protected-main
  policy, and stacked-branch retarget/rebuild rules. Never merge a local feature
  branch directly onto `main` and push that merge as feature delivery.
- Run the dock with `./scripts/run`.
- Keep the standalone entry point at `shell.qml` and the Omarchy plugin entry point at `Overlay.qml`.
- Keep shared host behavior in `DockHost.qml`; never start a second Quickshell process from the plugin.
- Keep window lifecycle actions and SmartDock-minimized origins in the single
  `DockWindowActions` instance owned by `DockHost.qml`; per-screen docks and
  context menus must consume that shared controller rather than duplicate it.
- Put reusable visual components in `components/`.
- Keep user-facing defaults in `config/dock.json`; `DockControl` loads them for
  both host modes. Keep CLI metadata in `config/settings-schema.json` and retain
  compatible runtime normalization in `DockModel.js`.
- Installed user settings live outside the application at `~/.config/smartdock/dock.json`; updates must never overwrite them.
- Keep `install.sh`, `uninstall.sh`, and `scripts/smartdock` compatible with custom XDG directory variables.
- Prefer Quickshell APIs over shelling out to external commands.
- Use freedesktop desktop-entry IDs without the `.desktop` suffix.
- Preserve live configuration reloads.

## Configuration workflow

Use `smartdock status --json`, `smartdock config schema --json`, and
`smartdock config get --json` to discover the selected running host before a
minimal CLI mutation. The host-reported config path is authoritative. Read
`docs/AGENT_CONFIGURATION.md` for typed patches, app/icon intents, persistence,
retry and reset boundaries. `bash ./install.sh --cli-only` installs just the
client; it must not start another dock or alter live settings.

Preferences and icon editing are CLI-only. Do not reintroduce a settings window,
preview-only preferences, or a second config writer. Retain ordinary window
previews, the app picker, dock menus, drag reordering and live theme bindings.
The host's FileView remains the only live settings writer. Saved settings and
verified rendering are separate facts; headless tests do not qualify Omarchy
focus, auto-hide scheduling, image decoding or cache behavior.

## Validation

GitHub `Headless CI` runs the host-independent subset documented in
`docs/DELIVERY.md`. Before committing runtime changes, also run the full local
validation gate when the owning issue requires it:

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh
qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml shell.qml
git diff --check
```

A portal warning about an application ID already being registered can occur when another Quickshell process is running; it is not a dock failure.

## Style

- Use two-space indentation in QML.
- Keep JavaScript helpers small and local to the component that owns the behavior.
- Add new configuration options to `config/dock.json`, the CLI schema and the README.
