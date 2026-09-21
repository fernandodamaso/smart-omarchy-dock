# Herdr data access: inactive scaffold (FDM-970, step 1)

**Delivered:** a read-only socket helper extracted/adapted from omaherdr, pinned
provenance/license, real Unix-socket fixture tests and an explicit CI gate.
**Not delivered:** discovery, a shared provider/service, installation, normalized
live counts, remote access, widgets or real Herdr/Omarchy qualification.

SmartDock does not need omaherdr installed or running. This branch does not
modify either product's active processes, installed checkouts or user settings.
It does not wire the helper into `Service.qml`, `DockHost.qml` or any widget.

## Source entry points

| File | Purpose |
| --- | --- |
| `provider/herdr/bin/smartdock-herdr-helper` | Explicit single-socket transport; standard-library Python 3. |
| `provider/herdr/UPSTREAM.md` | Upstream commit, source-to-destination map and modifications. |
| `provider/herdr/LICENSE.omaherdr` | Full license for the reused source. |
| `provider/herdr/tests/test_events.py` | Real Unix-socket fake server; bootstrap, events, reconnect, no RPC, backpressure and cleanup. |
| `provider/herdr/tests/test_protocol.py` | Shape validation, framing, privacy projection and lossless sequences. |
| `tests/check_herdr_data_access.sh` | Provenance and inactive/read-only scaffold guards. |

## Running tests

From the source repository, without Herdr, omaherdr, SSH or a graphical session:

```sh
python3 -B -m unittest discover -s provider/herdr/tests -p 'test_*.py' -v
bash tests/check_herdr_data_access.sh
```

The existing `Headless CI` now executes that nested suite explicitly. Keep the
existing launcher-badge anti-polling guards intact. Tests exercise a synthetic
server matching the inspected protocol; they are not live compatibility evidence.

## Private helper protocol

A future owner starts one helper for an explicitly resolved local Unix socket:

```sh
python3 -B provider/herdr/bin/smartdock-herdr-helper /absolute/path/to/herdr.sock
```

Do not run this command merely to import/register the future service. It opens
real socket subscriptions until stdin closes, `quit` arrives or SIGTERM is sent.
Do not redirect its output into public logs: even projected labels are user data.
Use the installed `herdr api schema --json` to qualify that binary's API before a
real integration; see https://herdr.dev/docs/socket-api/ for protocol guidance.

Stdin accepts newline-delimited `snapshot` and `quit` only. Every other command
returns `{"kind":"error","error":"unsupported_command"}` without invoking Herdr.
Output is JSON-lines with these records:

- `snapshot`: `ok: true` and projected `snapshot`, or `ok: false` and a fixed error.
- `event`: source event name and projected identity/status metadata.
- `status`: `connected: true|false`.
- `error`: fixed command error code; never echoed source text.

The helper's records are **not** the versioned FDM-970 public provider snapshot.
A successful snapshot alone does not establish a healthy event stream. The future
provider must use both snapshot and connection state, invalidate live counts on
failure, and scope identities to its per-server connection generation.

The helper subscribes and waits for acknowledgement before bootstrap. Per-pane
subscription changes trigger a follow-up snapshot covering the replacement gap.
Structural events are forwarded as invalidation signals: their full layout data
is deliberately omitted. The future supervisor must debounce them into snapshot
requests and perform the provider-owned safety reconciliation. This scaffold
adds no process-discovery or periodic CLI/status-polling loop.

Limits: 8 MiB per incoming snapshot, 1 MiB per event/output frame, 4 KiB per stdin
command, 32 JSON nesting levels, 100,000 visited JSON nodes and 16,384 records per
source collection. I/O deadlines are 2 seconds per connection/read or output
operation; reconnect delay grows from 1 to 30 seconds. Output is a single bounded
frame with a write deadline, not an unbounded queue; an undrained pipe terminates
the helper. Oversized snapshots/output fail explicitly, never become healthy
empty data. The future normalized provider must add its 64-server/256-agent caps
and completeness metadata; those aggregate limits are not implemented here.

No arbitrary RPC, focus, answers, notifications, transcript reads, persisted
status ages, terminal subprocesses, remote connections or omaherdr state files.

## Next implementation: FDM-970 step 2

Continue this branch with a SmartDock-owned `provider/herdr/discovery.py`,
`provider/herdr/model.py` and `provider/herdr/bin/smartdock-herdr-provider`.
Port the audited daemon's `Discovery` / `Helper` / `Server` behavior selectively;
do not copy its notifier or turn the helper into a second agent detector.

Resolve default/named/unattached local sessions, deduplicate actual endpoints,
supervise one helper per endpoint, debounce structural invalidations, reject
late output from replaced helpers, and publish versioned live/unavailable/partial
state. Never silently resolve a failed named-session lookup to the default socket.

After that, add the demand-driven shared QML service and XDG-aware packaging.
Keep one acquisition owner across all SmartDock consumers. Qualification must
prove data access with omaherdr absent; coexistence is tested separately. No
widget issue is a prerequisite for this backend work.

Canonical issue: https://linear.app/fdamaso/issue/FDM-970
