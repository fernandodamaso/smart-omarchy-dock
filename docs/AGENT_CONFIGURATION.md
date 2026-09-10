# Configure SmartDock through its CLI

Use the running host as the source of truth. Do not edit its dock.json, launch another dock, restart Omarchy, install a badge provider or change desktop/theme files to configure it.

## Discover before changing anything

```sh
smartdock status --json
smartdock doctor --json
smartdock config schema --json
smartdock config get --json
smartdock config get hoverGlowOpacity --effective --json
```

If discovery is ambiguous, repeat with `--runtime plugin|standalone` or `--instance ID`. Global control options work before or after the command. `runtime.instanceId` is the host process ID for this host lifetime; `runtime.quickshellId` is the native qs ID. Both are exact selectors. No newest-instance selection is performed. Read `data.configPath`; do not infer a target from your working directory or SMARTDOCK_CONFIG (which only affects explicit standalone launch).

Bare `smartdock` and `smartdock help` show help; `agent-guide` prints this file. These do not contact a host or create directories. `config schema` may return `source: bundled` only with automatic discovery and no matching host. That is default metadata, not the user's configuration. Explicit targeting errors, ambiguity, timeouts and malformed protocol responses never fall back to bundled metadata. All other configuration reads require a running host.

## Requested, effective and saved are different

Read `data.settings` (a keyed object even for one key). Requested values retain intent: hoverGlowOpacity 0.72 renders as 0.70; grouped layout renders flat on left/right without erasing the request; autoHide disables effective reserveSpace. Theme-owned or symbolic colors and theme-owned border width appear as null in effective output with a warning because the headless host does not report renderer-resolved values. Never replace a token merely because that effective value is unknown.

Status distinguishes missing, loaded and invalid disk configuration; defaults are not marked persisted when the file is missing. Invalid JSON preserves last-good live settings. `revision` is scoped to this host lifetime. `writeState` is idle, saving, saved or error; `persisted` does not become true merely because the live state changed. Read `loadError`, `writeError` and `loadPending` before attempting a change.

## Machine interface and failures

`--json` emits exactly one object with `apiVersion: 1`, `ok`, `data`, `warnings`, and `error.code/message` on failure. Subprocess diagnostics go to stderr. IPC uses one host-owned `smartdock.request(string): string` endpoint, outside screen delegates. Requests carry `apiVersion`, `command` and an `arguments` object.

Exit codes: 0 success; 2 usage/validation; 3 absent/ambiguous host; 4 persistence/export failure; 5 transport/protocol/timeout; 6 busy/invalid existing configuration. A timeout reports null applied/persisted: read status before retrying; never assume rollback. Commands and metadata describe only the currently implemented surface. Mutation, app and icon commands are added by the next ordered migration slices; Settings remains available until those replacements are verified.

## Install only the client

```sh
bash ./install.sh --cli-only
bash ./uninstall.sh --cli-only
```

Client files live in `${XDG_DATA_HOME:-$HOME/.local/share}/smartdock-cli`; the shared wrapper lives in `${XDG_BIN_HOME:-$HOME/.local/bin}/smartdock`. Client-only install/removal neither writes the user config nor installs/starts the standalone dock, autostart entry, terminal-agent assets or provider. It coexists with standalone installation in either order; uninstalling one retains the wrapper while the other owns it. Standalone launch, restart, stop, update, autostart and uninstall are explicit lifecycle commands, not plugin configuration operations.

The adapter uses Python 3 standard library only and bounded argv subprocesses. It uses upstream `qs list --all --json` and explicit `qs ipc --pid PID call -- smartdock request PAYLOAD`. The Omarchy `omarchy-shell` wrapper selects the newest instance and cannot express an exact selector, so it is not used for ambiguous-sensitive targeting. No raw socket protocol is implemented. Compatibility with the installed Quickshell build and live Omarchy scheduling remains a local qualification check, not something headless tests prove.
