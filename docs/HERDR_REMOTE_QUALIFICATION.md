# Herdr remote sidebar and native qualification

FDM-981 / HERDR-REMOTE-02 owns source presentation and action guards.
FDM-982 / HERDR-REMOTE-03 owns the real second-machine qualification.
See [HERDR_DATA_ACCESS.md](HERDR_DATA_ACCESS.md) for acquisition and protocol,
[DELIVERY.md](DELIVERY.md) for exact-SHA delivery, and
[DEV_SESSIONS.md](DEV_SESSIONS.md) for isolated native testing.

## Source contract

Both matched window-nested rows and the unmatched Herdr fallback consume the
same provider snapshot. No view acquires another provider or subscription.

Remote default sessions display the sanitized host label. Named sessions display
`<host label> · <session>`. Local parent labels remain `Herdr`; local fallback
labels retain their existing provider label/session fallback. All text is plain
text; no raw SSH output, command line, credentials, socket or executable path is
used to derive a display label.

Association uses the validated local Herdr TUI client process and nearest proven
ancestor identity. It does not use the remote agent PID, window title or focus.
An ambiguous nearest surface or conflicting server claims stay unmatched, and
the server remains visible in the fallback. Independently proven clients may
associate the same server with more than one local window.

A connecting server displays reconnecting, an unavailable server displays
unavailable, and an observed complete live empty inventory displays no active
agents. Partial/unknown inventory must not be called healthy empty. Working
animation is driven by an agent's working state, not server reconnection.

Every actionable single-panel tab, multi-panel header and agent child retains
provider epoch, server ID, connection generation, agent/pane/terminal identity,
transport/host/session metadata and per-server focus capability. Input capture,
currentness validation and hover affordance require the authoritative capability.
False, absent or malformed capability is not support. The backend also rejects
unsupported focus before helper forwarding. Failure settles pending UI requests;
newer provider epochs, connection generations or missing agents cannot reuse the
old action identity.

The production remote capability remains **false**. A deliberately capability-
bearing test fixture establishes source routing only, not visible remote-TUI
focus support or compatibility with an installed Herdr release. No remote
version, including an unknown/unparseable one, is enabled by this milestone.

## Source verification

```sh
node tests/test_herdr_remote_rows.mjs
node tests/test_herdr_sidebar_model.mjs
node tests/test_herdr_focus_activation.mjs
python3 -B -m unittest discover -s provider/herdr/tests -p 'test_*.py' -v
python3 -B -m unittest discover -s tests -p 'test_herdr_*.py' -v
bash tests/check_herdr_data_access.sh
bash tests/check_launcher_badge_counts.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components -import tests/qml-imports
git diff --check
```

Also run the entire current Headless CI matrix on the exact PR base/head pair.
`test_herdr_remote_rows.mjs` exercises real row projection, rather than only
hand-constructed focus targets. `tst_herdr_remote_fallback.qml` loads the production
fallback view with synthetic snapshots; it is not a native Herdr/SSH acceptance.
The existing local appearance and eight-phase working-indicator suites remain
part of the same gate.

## FDM-982 native handoff

The Linear/PR handoff records exact base, candidate head, merged candidate and CI
run. Do not silently replace that candidate with a later `main`. New source
changes require a new review and exact-head CI before final native acceptance.

1. Record the clean source checkout SHA, deployed/tested checkout SHA, Omarchy,
   Quickshell, and local/remote Herdr versions. Capture installed `herdr --help`
   and relevant session help; validate actual CLI forms rather than assuming
   fixtures establish installed-version compatibility.
2. Use an authorized second machine and an existing working SSH connection.
   Verify non-interactive SSH with the provider's fixed options: BatchMode=yes,
   ConnectTimeout=8, ServerAliveInterval=15, ServerAliveCountMax=3. Do not disable
   host-key verification, install remote SmartDock, or provision/reconfigure
   remote Herdr. Confirm Python and the existing remote Herdr are available.
3. Use the isolated source-testing workflow. Never start a second production
   dock. For an explicitly authorized desktop preview, follow DEV_SWITCH.md,
   back up touched settings, and reset the source switch afterward.
4. Exercise local-only, remote default, remote named, local+remote same-name,
   and two remote hosts with the same session name. Compare actual Herdr state
   with displayed host/session, statuses, counts and nearest-window nesting.
   Include ambiguous/unmatched clients and connected-empty inventory.
5. Observe live status changes and working-dot motion. Disable motion and verify
   the static status remains. Reconnecting/unavailable sessions must neither
   look healthy empty nor animate solely because of connection activity.
6. Treat remote inventory and remote actions as separate decisions. First verify
   that unqualified remote rows have no focus affordance and enqueue nothing.
   Any native experiment with a qualified version must be isolated and reviewed;
   never enable all remote versions merely to get past this gate. Observe both
   the correlated action response and the visible selected remote pane/tab.
   An ACK alone is not proof of visible focus, and an unsupported production
   capability is not a successful focus test.
7. Exercise remote Herdr/host loss, SSH auth/reachability failure, local TUI exit,
   reconnect, provider/dock restart, widget disable/reactivation and final
   release. Verify local inventory keeps progressing, generations invalidate
   old actions, pending requests settle, and no owned SSH/helper survives its
   bounded shutdown/owner lease. Do not kill unrelated Herdr or SSH processes.
8. Capture short screenshots/recordings and bounded, sanitized evidence for the
   exact candidate. Rerun the issue-required native gates plus source suites;
   diagnose failures and repeat affected checks after fixes. Restore source and
   settings when testing ends.

For each scenario record `PASS`, `FAIL`, or `BLOCKED`, candidate SHA, both Herdr
versions, observed behavior, and evidence. Keep inventory qualification separate
from visible-TUI focus qualification. Only a completed native gate can justify
changing global `capabilities.remote` or version-specific remote action support.
No source test or CI success substitutes for unavailable desktop/second-host
access; record that blocker rather than marking the native issue complete.
