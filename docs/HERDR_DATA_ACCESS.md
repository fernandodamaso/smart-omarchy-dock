# Herdr data access: SmartDock-owned local provider (FDM-970)

SmartDock now owns the local Herdr integration. It does **not** require omaherdr
to be installed or running and it does not import, call, stop or configure
omaherdr.

The production path is:

```text
local Herdr session socket(s)
  -> provider/herdr/bin/smartdock-herdr-helper
  -> provider/herdr/bin/smartdock-herdr-provider
  -> components/DockHerdrService.qml
  -> internal sidebar widget herdr.agents
```

The first milestone is intentionally local-only. Normalized snapshots advertise
`capabilities.remote: false`; no SSH bridge or remote-session support is implied.

## Activation and ownership

`sidebarWidgets` still defaults to `[]`. Registering the source descriptor does
not start Herdr work.

Enable the production widget explicitly:

```sh
smartdock config set sidebarWidgets '["herdr.agents"]'
```

When the sidebar has usable mapped screens, the host acquires one lease from the
shared `DockHerdrService`. The first active lease starts exactly one provider
process. Additional SmartDock views share it. Suspending or removing the final
active lease sends `quit`, waits briefly for clean provider/helper shutdown and
then terminates only if the process did not exit. SmartDock never stops Herdr or
an omaherdr process.

Plugin mode exposes the service through the plugin singleton
(`Service.qml -> Overlay.qml -> DockHost.qml`). Standalone mode creates one
service next to its single `DockHost`.

## Local discovery

`provider/herdr/discovery.py` resolves local endpoints from:

- the documented default socket `~/.config/herdr/herdr.sock`;
- documented named sockets under `~/.config/herdr/sessions/<name>/herdr.sock`;
- bounded `herdr session list` metadata when available, including running
  unattached sessions.

Canonical socket paths are deduplicated before helpers are started, so aliases
for the same endpoint do not create duplicate subscriptions. A failed or stopped
named-session lookup never falls back to the default socket.

The provider checks a cheap filesystem fingerprint every 10 seconds and reruns
metadata discovery only when the local socket/session set changes. Explicit
`refresh` also rescans. There is no recurring `herdr agent list` or equivalent
agent-status subprocess loop.

## Socket protocol

The private helper is adapted from omaherdr's proven transport behavior but is
owned by this repository. It:

1. opens `events.subscribe` and waits for acknowledgement;
2. takes the baseline `session.snapshot`;
3. replaces the per-pane status subscriptions when pane inventory changes;
4. takes another baseline after each replacement to cover the live-stream gap;
5. forwards status and structural invalidations to the provider;
6. reconnects with bounded backoff.

Stdin accepts `snapshot`, `quit`, and one bounded JSON `focus-agent` command that
calls only Herdr `agent.focus` with a pane id. The helper emits correlated
`action-result` records with fixed error codes. There is no generic RPC surface,
answer command, notification command or transcript access.

Sidebar click-to-focus requires **Herdr 0.9.1+**. On 0.9.0, `agent.focus`
updates server focus and marks agents seen, but does not move attached TUI
clients to the target pane (fixed upstream in 0.9.1). Multi-panel tab headers
focus that Herdr tab by targeting the first nested panel's pane id; single-panel
tabs and agent rows target their own pane.

Structural invalidations include the current Herdr workspace/tab/pane/layout
event families, including `workspace.metadata_updated` and `pane.updated`.
They debounce to a replacement snapshot; a 60-second safety snapshot reconciles
missed structural changes.

## Normalized snapshot

The provider emits JSON-lines with `schemaVersion: 1`, a process-scoped
`providerEpoch` and monotonically increasing `revision`. Public state contains:

- `capabilities`;
- `servers`;
- `agents`;
- `attention` (blocked/done agents only);
- `liveCounts`;
- `completeness`.

A server is live only after both a valid snapshot and a healthy event
subscription are observed. Disconnect immediately removes that server from live
agent totals. A connected, observed-empty inventory reports zero; unavailable or
unknown inventory reports `liveCounts: null`.

Agent identities include the server ID and connection generation so a pane ID
reused after reconnect cannot alias prior state. Valid Herdr
`state_change_seq` values remain decimal strings to preserve uint64 precision.
Observed status ages are in-memory monotonic ages only; they are not persisted.

The view renders projected names/labels/statuses as plain text. Socket paths,
transcripts, cwd, arbitrary metadata, credentials and raw provider exceptions are
not exposed through widget diagnostics.

## Bounds

The integration keeps the following hard limits:

- 8 MiB incoming socket snapshot;
- 1 MiB incoming event/helper frame;
- 1 MiB normalized provider output frame;
- 2 MiB bounded provider event queue;
- 64 discovered servers;
- 256 public agent rows;
- 4 KiB private stdin command;
- 2-second helper socket/output deadlines.

Truncation is explicit in `completeness`; partial data never claims an exact
overall total.

## Installation

Standalone installation copies `provider/herdr/` into the installed SmartDock
tree beside `components/`. The helper and provider are invoked with Python 3;
no omaherdr package, daemon, D-Bus service or runtime download is installed.

Plugin/source mode uses the same repository-owned provider files.

## Verification

Headless gates:

```sh
python3 -B -m unittest discover -s provider/herdr/tests -p 'test_*.py' -v
python3 -B -m unittest discover -s tests -p 'test_herdr_*.py' -v
bash tests/check_herdr_data_access.sh
bash tests/check_launcher_badge_counts.sh
git diff --check
```

The provider tests cover socket bootstrap/events, discovery, endpoint
deduplication, unavailable-vs-empty semantics, reconnect generations, status
updates, truncation, process refresh, pane focus transport and clean helper
shutdown. The lifecycle tests lock the real source registry, shared service
ownership, standalone/plugin wiring, schema registration and packaging.

These tests use controlled socket/provider fixtures. They establish source and
protocol behavior but are not a substitute for the separate native
Omarchy/Quickshell qualification with a real Herdr installation. That native
gate should verify default, named and unattached local sessions, omaherdr absent,
and coexistence when omaherdr is installed separately.

Canonical issue: https://linear.app/fdamaso/issue/FDM-970
