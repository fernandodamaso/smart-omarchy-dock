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

Bare `smartdock` and `smartdock help` show help; `agent-guide` prints this file. These do not contact a host or create directories. `config schema` may return `source: bundled` only with automatic discovery and no matching host. That is default metadata, not the user's configuration. Explicit targeting errors, ambiguity, timeouts and malformed protocol responses never fall back to bundled metadata. All other configuration operations require a running host.

## Requested, effective and saved are different

Read `data.settings` (a keyed object even for one key), with `data.source` equal to `requested` or `effective`. Requested values retain intent: hoverGlowOpacity 0.72 renders as 0.70; grouped layout renders flat on left/right without erasing the request; autoHide disables effective reserveSpace. Theme-owned or symbolic colors and theme-owned border width appear as null in effective output with a warning because the headless host does not report renderer-resolved values. Never replace a token merely because that effective value is unknown.

Status distinguishes missing, loaded and invalid disk configuration; defaults are not marked persisted when the file is missing. Invalid JSON preserves last-good live settings. `revision` is scoped to this host lifetime. `writeState` is idle, saving, saved or error; `persisted` does not become true merely because the live state changed. A known pending reload also makes disk/live parity unconfirmed. Read `loadError`, `writeError` and `loadPending` before attempting a change.

## Apply the smallest requested change

```sh
smartdock config set showTrash false --json
smartdock config set hoverGlowOpacity 0.72 --json
smartdock config set backgroundColor '#80112233' --json
```

`set` obtains the selected runtime's schema and parses the declared type: strings are literal arguments, booleans require lowercase `true`/`false`, numbers must be finite, and arrays/objects use JSON. Quote shell metacharacters; the CLI never evaluates `controlCommand`, but the existing launcher action may execute it later. Pointer actions such as `close` may close windows when used. Change these only for explicit user intent.

For a related multi-key change, use one atomic patch. Input is only read with explicit `--stdin` or `--file PATH`; there is no implicit stdin or offline writer. UTF-8 JSON object input is bounded to 64 KiB; duplicate keys, invalid JSON, non-finite numbers, unknown new keys and invalid values are rejected. One invalid value rejects the entire batch.

```sh
printf '%s\n' '{"backgroundColorEnabled":true,"backgroundColor":"@menu.background"}' | smartdock config apply --stdin --dry-run --json
printf '%s\n' '{"backgroundColorEnabled":true,"backgroundColor":"@menu.background"}' | smartdock config apply --stdin --json
smartdock config get backgroundColor --json
smartdock config get backgroundColor --effective --json
```

Inspect `data.changedKeys`, `diff`, proposed `requested` and `effective` on a dry run. It does not change live state, increment revision, save defaults or create directories. Apply recomputes against the latest host state; it does not replay a dry-run snapshot. Unrelated pins, hidden apps, custom icons, legacy values and extension keys survive narrow edits. New pointer values must use canonical names even when a legacy requested alias remains untouched in the file.

Mutations return `applied` and `persisted` separately. A completed save is `writeState: saved`; a persistence error exits 4 with `applied: true`, `persisted: false` and keeps the live change. Busy/invalid configuration exits 6. An identical patch does not write again and does not hide an existing save error. Repair an invalid disk file externally before using mutations; do not automatically replace it with defaults.

```sh
smartdock status --json
smartdock config retry --json
smartdock config get --json
```

Use retry only after inspecting a failed save. It saves the complete current live snapshot, not an old patch, and does not increment the setting revision. Pending loads/writes are refused. If completion has not been observed, the response is busy rather than falsely successful. A timeout has unknown applied/persisted outcome: read status and the affected values before deciding whether another mutation is necessary.

## Reset and export deliberately

```sh
smartdock config reset hoverGlowOpacity --json
smartdock config reset --preferences --json
smartdock config export --output "$HOME/smartdock-snapshot.json" --json
```

Reset requires exactly one key or `--preferences`. Preference reset leaves `pinned`, `hiddenApplications`, `margin`, custom icons and unknown extension keys alone; reset a specific key to reset that key explicitly. Do not use a broad reset for a narrow request.

Export reads the selected host's requested settings, including unsaved live values and unknown keys, then creates a **new** plain JSON file with owner-only permissions. It never overwrites an existing file, follows a destination symlink, writes onto the live configuration, or creates missing parent directories. Existing hardlinks and directory aliases of the live path are refused as well. There is no force switch. `exportWritten` describes the snapshot; `sourcePersisted` describes the live configuration and may remain false. A successfully exported unsaved snapshot is not evidence that SmartDock saved its settings. Reapplying a snapshot with unknown extension keys is not an import mechanism: apply accepts only known setting keys. Keep it as a backup, or select the intended known keys for a new patch.

## Machine interface and failures

`--json` emits exactly one object with `apiVersion: 1`, `ok`, `data`, `warnings`, and `error.code/message` on failure. Subprocess diagnostics go to stderr. IPC uses one host-owned `smartdock.request(string): string` endpoint, outside screen delegates. Requests carry `apiVersion`, `command` and an `arguments` object.

Exit codes: 0 success; 2 usage/validation; 3 absent/ambiguous host; 4 persistence/export failure; 5 transport/protocol/timeout; 6 busy/invalid existing configuration. CLI set maps to a minimal `config.apply` host intent; export reads `config.get` and only writes the separate new snapshot. Commands and metadata describe the currently implemented surface. App/icon intents are added by the next ordered migration slice; Settings remains available until those replacements are verified.

## Install only the client

```sh
bash ./install.sh --cli-only
bash ./uninstall.sh --cli-only
```

Client files live in `${XDG_DATA_HOME:-$HOME/.local/share}/smartdock-cli`; the shared wrapper lives in `${XDG_BIN_HOME_HOME:-$HOME/.local/bin}/smartdock` (the variable is `XDG_BIN_HOME`). Client-only install/removal neither writes the user config nor installs/starts the standalone dock, autostart entry, terminal-agent assets or provider. It coexists with standalone installation in either order; uninstalling one retains the wrapper while the other owns it. Standalone launch, restart, stop, update, autostart and uninstall are explicit lifecycle commands, not plugin configuration operations.

The adapter uses Python 3 standard library only and bounded argv subprocesses. It uses upstream `qs list --all --json` and explicit `qs ipc --pid PID call -- smartdock request PAYLOAD`. The Omarchy `omarchy-shell` wrapper selects the newest instance and cannot express an exact selector, so it is not used for ambiguous-sensitive targeting. No raw socket protocol is implemented. Compatibility with the installed Quickshell build, live Omarchy scheduling and actual FileView saves remains a local qualification check, not something headless tests prove.
