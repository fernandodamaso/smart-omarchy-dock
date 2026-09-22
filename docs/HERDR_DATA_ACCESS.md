# Herdr data access: SmartDock-owned local + attached-remote provider (FDM-970 / FDM-980)

SmartDock owns the Herdr integration. It does **not** require omaherdr to be
installed or running and it does not import, call, stop or configure omaherdr.
Local servers are discovered directly; remote servers are considered only while
this desktop has a verified attached `herdr --remote <target>` TUI process.

The production path is:

```text
local Herdr session socket(s)
  OR verified attached remote Herdr TUI
     -> bounded non-interactive SSH -> in-memory remote smartdock-herdr-helper
  -> provider/herdr/bin/smartdock-herdr-helper
  -> provider/herdr/bin/smartdock-herdr-provider
  -> components/DockHerdrService.qml
  -> internal sidebar widget herdr.agents
```

Normalized snapshots continue to advertise global `capabilities.remote: false`
until FDM-982 completes native qualification. FDM-980 can nevertheless emit
source-qualified server rows with `transport: "remote"`; those rows advertise
`capabilities.focusAgent: false`. The global bit therefore remains a rollout /
qualification gate rather than a claim that remote source code is absent.

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
## Attached remote discovery and SSH transport

Remote support is attachment-driven only. The process classifier recognizes the
current TUI forms `herdr --remote TARGET [--session NAME]` (including the
equivalent `--flag=value` spelling and the documented `--remote-keybindings`
modifier). Help/version/control/handoff shapes, duplicate flags and unsafe
targets fail closed. PID/start-time/same-user/ancestry proof is retained before
an attachment is accepted, and raw argv is never published.

The attached Herdr process's direct child SSH bridge is used as bounded read-only
evidence for the remote Herdr executable. Bare PATH lookup is not trusted. A
finite worker pool resolves the requested remote session without blocking the
provider loop. Named-session lookup fails closed: failure to prove `work`, for
example, never falls back to remote `default`.

SSH is argv-based and non-interactive:

```text
ssh
-o BatchMode=yes
-o ConnectTimeout=8
-o ServerAliveInterval=15
-o ServerAliveCountMax=3
--
<TARGET>
<FIXED BOOTSTRAP>
```

The bootstrap is fixed. Session, executable, helper source and socket values are
validated or base64-encoded fixed-position data. Remote `~` expansion and
canonicalization happen on the remote host; SmartDock never applies the local
home or local `realpath()` to a remote path. No password prompt, saved-machine
scan, credential persistence, remote install, Herdr startup/reconfiguration, or
generic remote command passthrough is introduced.

The repository-owned helper is shipped in memory and executed with remote
Python 3; no SmartDock file is persisted remotely. A private `lease` renewal
does no Herdr work and causes a remote helper to self-exit when its owning
provider disappears. Periodic safety snapshots also act as application-level
liveness probes, so a live SSH process with a hung helper is invalidated and
reconnected rather than treated as healthy.

Multiple local TUI attachments for one `(target, session)` share resolution.
After resolution, aliases dedupe only when remote metadata proves the same
remote machine authority and canonical socket. Different hosts with the same
session name remain distinct.

## Socket protocol

The private helper is adapted from omaherdr's proven transport behavior but is
owned by this repository. It:

1. opens `events.subscribe` and waits for acknowledgement;
2. takes the baseline `session.snapshot`;
3. replaces the per-pane status subscriptions when pane inventory changes;
4. takes another baseline after each replacement to cover the live-stream gap;
5. forwards status and structural invalidations to the provider;
6. reconnects with bounded backoff.

Stdin accepts `snapshot`, `quit`, one bounded JSON `focus-agent` command and
the remote-only private owner `lease`. Local focus calls only Herdr
`agent.focus` with a pane id; remote server rows disable `focusAgent` and the
provider rejects those requests before helper forwarding. The helper emits correlated
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
- `servers` (bounded `transport`, `host`, `session`, health and per-server capabilities);
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
- 2 MiB bounded provider event queue with per-source caps and a reserved local lane;
- at most 4 concurrent remote metadata resolvers and 64 queued resolutions;
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

The provider tests cover socket bootstrap/events, local and remote attachment
classification, bounded SSH/bootstrap construction, finite resolver concurrency,
remote endpoint deduplication, unavailable-vs-empty semantics, reconnect
generations, owner-lease/probe liveness, queue isolation, status updates,
truncation, process refresh, pane focus transport and clean helper shutdown.
The lifecycle tests lock the real source registry, shared service
ownership, standalone/plugin wiring, schema registration and packaging.

These tests use controlled socket/provider fixtures. They establish source and
protocol behavior but are not a substitute for FDM-982 native
Omarchy/Quickshell qualification with real local and remote Herdr installations.
That gate owns real SSH reachability, current installed Herdr/Python compatibility
and the decision to enable global `capabilities.remote`.

Canonical issues:
- https://linear.app/fdamaso/issue/FDM-970
- https://linear.app/fdamaso/issue/FDM-980
