# Herdr provider provenance

This directory contains SmartDock-owned source, not a runtime dependency on the
omaherdr plugin. The derived source remains Apache-2.0 licensed; the repository's
root MIT license does not replace this directory's upstream license.

## Pinned source

- Repository: https://github.com/njpatel/omaherdr
- Revision: `c20d9b0db3a65b5a7590876c56026bc906306e04`
- Attribution: Neil Jagdish Patel and the omaherdr contributors.
- License: full upstream Apache-2.0 text in `LICENSE.omaherdr`.
- License Git blob: `d645695673349e3947e8e5ae42332d0ac3164cd7`.

| Original path | Original Git blob | Adapted path / retained behavior |
| --- | --- | --- |
| `bin/omaherdr-helper` | `ea2b6a90506cfcd0cc48cbd0b09fbc40bc49e98b` | `bin/smartdock-herdr-helper`: acknowledged bootstrap, structural/per-pane subscriptions, replacement snapshots, socket reconnect and stdin lifecycle. |
| `bin/omaherdr-daemon` | `2a7ac64f71c3c59efe8e5dd3f7d60e73f9e87cf8` | `discovery.py`, `remote.py`, `model.py` and `bin/smartdock-herdr-provider`: local session resolution, attachment-driven remote SSH resolution, endpoint deduplication, helper supervision, status reconciliation and normalized counts. |
| `tests/test_events.py` | `6e9fb91c8971411b8e55965225f67aa078faa4bb` | `tests/test_events.py`: temporary Unix-socket bootstrap/event regressions, extended for this extraction. |

Original files can be inspected at
`https://github.com/njpatel/omaherdr/blob/<revision>/<original-path>` using the
revision and paths above.

The working integration branch was stacked from SmartDock
`5eb3b2349d3914c7ee0eecc73a2515c535080cf1`, the current PR #82 head when the
child branch was created.

## Deliberate changes, 2026-09-18

- SmartDock owns discovery, normalization and helper supervision. No omaherdr
  module, daemon, D-Bus service, state file or process is required at runtime.
- FDM-970's first milestone was local-only. FDM-980 selectively adapts the
  pinned daemon's process-attached remote discovery and in-memory helper shipping,
  but does not copy saved-machine monitoring, the notifier, attention-policy
  engine, persistence, remote provisioning, or any generic command surface.
  Remote focus is intentionally disabled in the FDM-980 source contract.
- Discovery resolves default/named/unattached local sessions and deduplicates
  canonical socket endpoints. A failed named-session lookup never resolves to
  the default socket.
- The helper requires one explicit absolute socket and removes arbitrary `rpc`
  forwarding. Stdin accepts `snapshot`, `quit`, bounded `focus-agent` JSON,
  and, only when launched remotely, the private `lease` owner-watchdog renewal.
  The lease performs no Herdr action. The only Herdr socket requests remain
  `session.snapshot`, `events.subscribe` and the allowlisted local
  `agent.focus` action.
- Frames, request deadlines, queue bytes, JSON shape, public rows and output
  writes are bounded. Oversize/invalid state fails explicitly instead of
  becoming a healthy empty inventory.
- Public metadata is projected before leaving the provider: identity, bounded
  labels, focus/status and lossless state-change sequence only. Cwd, terminal
  titles, transcripts and arbitrary metadata are dropped.
- Subscription acknowledgement precedes the baseline snapshot. Per-pane stream
  replacement takes a fresh snapshot to cover the live-only gap.
- The pinned upstream structural set is reconciled with the current Herdr socket
  contract by also handling `workspace.metadata_updated` and `pane.updated`.
- Disconnection invalidates live totals immediately. Last-known state is not
  reused as current; agent IDs are scoped to a connection generation.
- No recurring agent-status CLI polling is introduced. Local metadata discovery
  remains fingerprint-driven. Remote metadata lookup is attachment-driven,
  bounded, finite-concurrency and non-interactive; named-session lookup fails
  closed and never substitutes the default session.
- Remote transport uses fixed SSH options and a fixed Python bootstrap. Target,
  session, executable and socket values are validated or base64-encoded data,
  never free-form remote shell commands. SmartDock writes no persistent remote
  files and never installs, starts, or reconfigures remote Herdr.
- Remote helper stdin writes are non-blocking. Provider event admission reserves
  capacity for local sources and caps each helper source. Safety snapshots double
  as app-level liveness probes; a private owner lease bounds orphan helper
  lifetime after provider/network loss.

This remains Herdr-derived state, not a second agent detector. Herdr supplies
the agent identity/status; SmartDock only transports, bounds and presents it.

## Maintenance

Before importing an upstream fix, compare the pinned source, retain applicable
notices, record the new pin/modifications and rerun the focused provider suite
plus full repository CI. No runtime download, submodule initialization,
auto-sync or upstream merge is required.

If a future import adds an upstream NOTICE, retain it alongside this file and
the existing Apache-2.0 license.
