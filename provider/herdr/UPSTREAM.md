# Herdr transport provenance

This directory contains SmartDock-owned source, not a runtime dependency on the
omaherdr plugin. The included derived source remains Apache-2.0 licensed; the
repository's root MIT license does not replace this directory's upstream license.

## Pinned source

- Repository: https://github.com/njpatel/omaherdr
- Revision: `c20d9b0db3a65b5a7590876c56026bc906306e04`
- Attribution: Neil Jagdish Patel and the omaherdr contributors.
- License: full upstream Apache-2.0 text in `LICENSE.omaherdr`.
- License Git blob: `d645695673349e3947e8e5ae42332d0ac3164cd7`.

| Original path | Original Git blob | Adapted path / retained behavior |
| --- | --- | --- |
| `bin/omaherdr-helper` | `ea2b6a90506cfcd0cc48cbd0b09fbc40bc49e98b` | `bin/smartdock-herdr-helper`: structural subscriptions, per-pane subscriptions, acknowledged bootstrap, replacement snapshots, socket reconnect and stdin lifecycle. |
| `bin/omaherdr-daemon` | `2a7ac64f71c3c59efe8e5dd3f7d60e73f9e87cf8` | `project_record` / `project_snapshot` in the helper adapt field projection/identity filtering ideas from `slim`, `identifier` and `attention_input`; no daemon is imported. |
| `tests/test_events.py` | `6e9fb91c8971411b8e55965225f67aa078faa4bb` | `tests/test_events.py`: real temporary Unix-socket fixture and bootstrap-race regression, extended for this extraction. |

Original files can be inspected at
`https://github.com/njpatel/omaherdr/blob/<revision>/<original-path>` using the
revision and paths above. This scaffold was based on SmartDock
`86fb65893295c95df664e6f274b19375a50f088a` (FDM-970 step 1).

## Deliberate changes, 2026-09-18

- Require an explicit absolute socket path. No guessed default/named session and
  no installed-plugin imports. Importing the helper has no runtime side effects.
- Remove arbitrary `rpc` forwarding. Stdin accepts only `snapshot` and `quit`;
  the only Herdr requests are `session.snapshot` and `events.subscribe`.
- Bound frames, request deadlines, JSON structure, output writes and stdin.
  Use monotonic reconnect deadlines, sanitized error codes and SIGTERM/EOF cleanup.
- Project metadata before writing stdout: identity, bounded labels, focus and
  reported status only. Drop cwd, terminal titles, transcripts and arbitrary
  metadata. Preserve valid uint64 state-change sequences as decimal strings.
- Retain subscription-before-snapshot ordering and resnapshot each replacement.
  Tests wait for acknowledgement before asserting the new pane subscription set.
- Do not import the upstream widget, notifier, persistence, attention-policy
  engine, process discovery, terminal focus logic or SSH launcher.

This is not a new implementation of agent detection. Herdr still supplies the
reported agent status. Neither the upstream regression nor these fixture tests
prove compatibility with every Herdr version or qualify the real desktop.

## Maintenance

SmartDock owns the adapted files. Before importing an upstream fix, compare the
pinned source, retain applicable notices, record the new pin and modifications,
and rerun the focused suite plus the repository gate. No runtime downloads,
submodule initialization, auto-sync or upstream merge is required to use this
source. Include any applicable upstream NOTICE if a future import adds one.
