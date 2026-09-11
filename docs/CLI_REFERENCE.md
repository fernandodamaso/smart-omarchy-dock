# SmartDock CLI reference

**Unreleased CLI-first candidate — Draft PR #44, `feat/fdm-914-cli-first`.** This describes implemented source, not an available release, permission to deploy, or completed Omarchy runtime qualification. Older installed builds may not implement this interface. Discover the selected host's schema instead of assuming this document describes that installation.

Start with [the agent guide](AGENT_CONFIGURATION.md). [Configuration inventory](CONFIGURATION.md) records every declared default and dependency. Source qualification belongs to [CLI_RUNTIME_CHECKS.md](CLI_RUNTIME_CHECKS.md); historical delivery evidence is not evidence for a newer SHA.

## Selection and transport

All commands below are prefixed with `smartdock`. Control options work before or after the command, including after a subcommand:

| Option | Meaning |
| --- | --- |
| `--json` | Exactly one versioned JSON object on stdout; diagnostics on stderr. |
| `--runtime auto` | Default: require exactly one matching SmartDock host. |
| `--runtime plugin` / `--runtime standalone` | Filter by host mode; multiple hosts of that mode still require an instance. |
| `--instance ID` | Exact native Quickshell ID or process ID, not a fuzzy/newest selector. |
| `--help`, `-h` | Offline help. |

`runtime.instanceId` is the process ID for that host lifetime; `runtime.quickshellId` is the native Quickshell ID attached by the client. Rediscover after a host restart. Explicit misses, ambiguity and protocol failures never select a different host. Retain the same selectors on every command in an operation.

The host's `data.configPath` is authoritative. The plugin uses its own `${XDG_CONFIG_HOME:-$HOME/.config}/smartdock/dock.json`; standalone launch may use `SMARTDOCK_CONFIG`. Changing the client's environment does **not** redirect an already-running host. No configuration command launches, restarts or installs a host.

The standard-library Python adapter currently uses `qs list --all --json` and `qs ipc --pid PID call -- smartdock request PAYLOAD`, with argv arrays, no shell evaluation, a 2-second subprocess timeout and an 8-second discovery/IPC deadline. Requests are bounded to 64 KiB and response stdout to 1 MiB. Diagnostics remain separate. The Omarchy wrapper's newest-instance selection cannot provide the exact selection required here; no guessed wrapper flags or raw socket protocol are used. Compatibility with the installed Quickshell build and real scheduling is a local gate.

## Discovery commands

| Command | Result and limits |
| --- | --- |
| `help` | Prints full help; bare `smartdock` does the same. No host or directories required. |
| `agent-guide` | Prints the installed `docs/AGENT_CONFIGURATION.md`; works without the source checkout or a host. With JSON, text is `data.text`. |
| `status` | Selected host identity, config path, load/write state and revision. Not a settings mutation. |
| `doctor` | Read-only status plus `data.checks`: `python`, `quickshell`, `omarchyShell`, `liveRuntime`. Missing runtime, invalid configuration or failed persistence exits nonzero. |
| `config schema` | Optional `KEY`; keyed `data.settings`, `schemaVersion: 1`, implemented `data.commands`, `source: runtime` or `bundled`. Defaults are loaded from `config/dock.json`, not duplicated in metadata. |
| `config get` | Optional `KEY` and `--effective`; keyed `data.settings` even for one key, `source`/`view: requested` or `effective`. Includes unknown retained keys on a full read. |

Only `config schema` may fall back to bundled metadata, and only after genuinely absent automatic discovery with no explicit instance. It is not the user's configuration. Explicit runtime selection, ambiguity, timeouts or malformed responses prohibit fallback. All other config/app/icon operations require a running host.

Status fields: `runtime`, `configPath`, `loadState` (`missing`, `loaded`, `invalid`), `loadError`, `loadPending`, `revision`, `writeState` (`idle`, `saving`, `saved`, `error`), `writeError`, `persisted`, `defaultsInUse`. A missing file is not a saved defaults file. Invalid disk configuration retains last-good live values and blocks ordinary writes; repair explicitly rather than replacing it with defaults. Revision is scoped to the host lifetime, not a compare-and-swap token. Pending readback makes persistence unconfirmed.

Requested values retain intent. Effective output projects current normalization and layout dependencies, not fully resolved rendering. Theme-owned/token colors and theme-owned border width are `null`, with `themeResolution: not-reported` and a warning on effective reads. Do not erase a token because its renderer-resolved value is unknown.

## Configuration commands

| Command | Arguments and semantics |
| --- | --- |
| `config set` | `KEY VALUE`. Reads the selected host's schema and sends one minimal `config.apply` patch. Strings are literal; booleans require lowercase `true`/`false`; numbers must be finite; arrays/objects are JSON arguments. |
| `config apply` | Exactly one of `--stdin` or `--file PATH`; optional `--dry-run`. Explicit UTF-8 JSON object input, at most 64 KiB. No implicit stdin, offline writer or deep merge. |
| `config reset` | Exactly one `KEY` or `--preferences`. One key resets that key, including a collection; preference reset has the exclusions below. |
| `config retry` | Retry a failed save using the complete **current** live snapshot, not an old patch. Does not increment the settings revision. Inspect the error first. |
| `config export` | `--output PATH`. Export requested live settings to a separate **new** owner-only JSON file; not necessarily saved source values. |

New patches reject unknown keys, unsafe/prototype-sensitive keys, wrong types, invalid enums/ranges, duplicate JSON keys/canonical application identities and non-finite numbers. Validation is atomic: one bad value rejects the complete patch. Array/object values replace that key; per-app commands are preferable to replacing a collection. Accepted unrelated legacy values and unknown extension keys remain untouched.

Dry run validates against current state and returns proposed `changedKeys`, `diff`, full `requested`, projected `effective`, `dryRun: true`, `applied: false`, `persisted: false`. `sourcePersisted` describes the current source. It does not write, create config directories or increment revision. Apply recomputes against latest host state; a dry run is not a reservation. Cooperating host intents serialize; disjoint changes survive and the later accepted same-key intent wins. Known pending reload/write returns busy instead of using stale state. Arbitrary external editors are not transaction-safe participants.

Mutation data includes status plus `changedKeys`, full `requested`/`effective`, `diff` keyed by changes with `{from,to}`, `dryRun`, `noop`, `applied`, `persisted`, `sourcePersisted`, and `themeResolution`. An actual completed save reports `writeState: saved`; an unchanged already-durable state need not perform another save. `noop` describes settings, not image reloads. A previous write error remains visible on an identical request.

A failed save can return `E_PERSISTENCE`, `applied: true`, `persisted: false`: the live change remains active for the session. Retry saves the latest snapshot. Busy/invalid states refuse unsafe mutations. A timeout has unknown outcome (`applied: null`, `persisted: null`); read status and affected values before another mutation. Never interpret exit status alone as visible-rendering confirmation.

Preference reset preserves `pinned`, `hiddenApplications`, `iconOverrides`, `margin` and unknown extension keys. It resets all other declared preferences, **including `controlCommand`**. That command is executable configuration used later by the launcher action; validation never executes it. Pointer action `close` may close all live grouped members when used. Change executable or destructive-on-use settings only for explicit user intent.

Export creates a new file with mode 0600, does not create missing parent directories, and refuses existing files, destination symlinks/hardlinks and aliases of the live path. There is no force switch. The plain file contains requested settings, including unsaved values and unknown keys. Its acknowledgment includes `exportWritten`, `exportPath`, `sourcePersisted`, `sourceRevision`, `sourceRuntime`, `configPath`, `applied: false`. A successful snapshot is not a successful live save. No whole-snapshot restore/import command exists: re-read and restore only touched supported keys. A snapshot containing unknown keys is deliberately not accepted wholesale by apply.

## Application commands

| Command | Arguments and semantics |
| --- | --- |
| `apps list` | At most one of `--query TEXT`, `--pinned`, `--hidden`; no filter lists the host catalog plus retained configured identities. |
| `apps pin` | `ID`; add pinned membership without showing a hidden app or launching it. |
| `apps unpin` | `ID`; remove pinned membership, not running windows or hidden membership. |
| `apps hide` | `ID`; hide the application without closing windows or changing pins. |
| `apps show` | Exactly `ID` or `--all`; clear the requested hidden membership, not pins. `--all` needs explicit broad intent. |
| `apps move` | `ID` and exactly `--before OTHER` or `--after OTHER`; both distinct IDs must already be pinned. |

Discovery uses the selected host's native `DesktopEntries.applications.values`, not a separate file scanner. Rows in `data.applications` contain `id`, `name`, `available`, `pinned`, `hidden`, `pinnedIndex` (zero-based, null when unpinned). Query matches ID/display-name text; mutation identity is exact after trimming, case folding and optional `.desktop` removal. Names and fuzzy results never become mutation targets automatically. Unsafe/path/control-containing, placeholder and prototype-reserved IDs are rejected.

Configured spelling and order are retained. Pinned/hidden filters preserve their configured order and include unavailable stored IDs. An otherwise unknown safe ID can be pinned without an installation claim. Membership commands are idempotent. Move operates on the latest complete pinned list, including hidden/unavailable entries, preserving all other relative order. These are host primitive intents, not stale client array replacements.

## Icon commands

| Command | Arguments and semantics |
| --- | --- |
| `icons list` | Requested `data.overrides`, normalized `effectiveOverrides`, `iconReloadRevision`, `renderVerified: false`, plus status. |
| `icons set` | `ID PATH`; update one app-wide mapping against the latest map and request fresh artwork. |
| `icons reset` | `ID`; remove only that mapping. Repeating a reset is a true settings/reload no-op. |
| `icons reload` | `ID`; require a valid existing local mapping and advance the shared reload revision without a config write. |
| `--profile DIR` | With `set`/`reset`/`reload`, target one browser profile instead of the whole application: the key becomes `ID@profile:DIR` (DIR is the on-disk profile directory, e.g. `Profile 1`, matching a browser-profile provider badge). |

Use static local PNG/SVG files referenced in place. The client resolves ordinary relative paths against its current directory; the shared model validates absolute paths and supported local `file:///` URLs, preserving spaces/Unicode through URL encoding. No remote URLs, downloads, system theme writes, imports or `.desktop` edits. Store artwork outside the plugin checkout. Missing/unreadable/corrupt files keep their requested mapping and fall back.

Set/reset preserves unrelated map entries, including untouched legacy sources. A bulk `iconOverrides` patch instead validates/replaces the whole map, rejecting canonical duplicates. A same-source set requests fresh bytes without a redundant settings write. There is no continuous artwork-file watch. Reload advances a global revision, so other mapped icons may refresh too.

Successful icon mutations add `reloaded`, `iconReloadRevision`, `renderVerified: false` to mutation data. Reload normally has `applied: false`, `noop: true`, `reloaded: true`; these fields are not contradictory. `reloaded` means requested, not decoded. Settings acceptance, durable save and actual rendering are separate observations.

The shared renderer applies across main app icons, preview metadata and picker rows. Fallback is profile-specific custom file → app-wide custom file → original desktop icon → `application-x-executable` → bundled theme-tinted `app-window` glyph. Custom artwork is not tinted. Identity, launch command, grouping, preview screenshots, badges, Trash and action glyphs are unchanged. A Chrome tab remains a Chrome-grouped item; artwork does not split browser groups.

## JSON and errors

Every response uses `apiVersion: 1`, Boolean `ok`, object `data`, array `warnings`; failures add `error: {code,message}`. Help/guide put text in `data.text`. The IPC endpoint is one typed host-owned `smartdock.request(string): string`, outside screen delegates. Requests are `{apiVersion:1, command:"config.apply", arguments:{patch:{showTrash:false},dryRun:false}}`; other requests use dotted commands with primitive/object arguments, never executable snippets. `set` maps to apply; export reads get and writes only its separate new snapshot. There is no second capabilities registry.

| Exit | Error codes | Response action |
| --- | --- | --- |
| 0 | none | Inspect operation-specific application/persistence/rendering fields. |
| 2 | `E_USAGE`, `E_VALIDATION` | Correct syntax or the requested key/value; no successful mutation. |
| 3 | `E_RUNTIME_NOT_FOUND`, `E_RUNTIME_AMBIGUOUS` | Discover/choose the intended exact host; do not start one automatically. |
| 4 | `E_PERSISTENCE`, `E_EXPORT` | Inspect live state and save/export error; a live change can remain unsaved. |
| 5 | `E_TRANSPORT`, `E_PROTOCOL`, `E_TIMEOUT` | Verify installed compatibility and selected-host state; applied outcome can be unknown. |
| 6 | `E_BUSY`, `E_CONFIG_INVALID` | Re-read once pending work settles, or explicitly repair the invalid file; do not replace defaults or retry forever. |

## Installation and lifecycle boundary

From the intended source checkout, `bash ./install.sh --cli-only` installs the wrapper at `${XDG_BIN_HOME:-$HOME/.local/bin}/smartdock` and the adapter, defaults, schema, agent guide, reference and inventory under `${XDG_DATA_HOME:-$HOME/.local/share}/smartdock-cli`. `bash ./uninstall.sh --cli-only` removes this bundle while preserving settings, plugin and standalone ownership. Both installation orders retain the wrapper while another bundle owns it. Help and guide use the installed bundle, not `.source-dir`. When both bundles exist the wrapper prefers client-only assets; update that bundle explicitly from the intended source.

Full `install.sh` is an explicit standalone installation with separate lifecycle effects and optional autostart; it is not needed to configure the plugin. Explicit wrapper commands `launch`/`--daemonize`, `restart`, `stop`, `update`, `uninstall`, and `autostart enable|disable|status` remain standalone lifecycle commands, outside this versioned control-command JSON contract. `smartdock update` is not a plugin or client-only updater. Use client-only reinstall for client updates and the normal, separately authorized Omarchy deployment path for a released plugin. No merge/deploy is authorized by this candidate reference.
