# Herdr Window Tree Completion — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans task by task. The user's execution method takes precedence: implementation through Cursor CLI Auto in Herdr, review through Codex CLI `gpt-6-astra` with high reasoning effort in Herdr. Do not substitute internal subagents.

**Goal:** Display real Herdr agents beneath their actual workspace window, with status counts, folding, and click/keyboard navigation to the exact pane; leave the verified feature running on the user's desktop.

**Architecture:** Finish the existing shared provider → shared service → host-owned sidebar path. Extend the current tree, input handling, and window-action controller. Reuse the process reader already written; add only the missing connection between compositor window PIDs and that reader.

**Tech Stack:** Python standard library, existing JavaScript models, Qt/QML, Quickshell, Hyprland, Omarchy tokens.

**Spec:** The user's September 19 Herdr Window Tree plan supplied in this conversation. Its remaining acceptance requirements are retained below; the original document was never saved.

## Starting point

- Checkout: `/home/admin/Projects/smart-omarchy-dock`.
- Branch: `feat/fdm-970-herdr-working-integration`.
- HEAD when this plan was written: `588756e6b8d50bac2bab752280548a073dc80cdf`.
- Uncommitted work already exists in `provider/herdr/attachments.py`, `provider/herdr/model.py`, `provider/herdr/bin/smartdock-herdr-provider`, `components/DockHerdrModel.js`, `provider/herdr/tests/test_attachments.py`, and `tests/test_herdr_sidebar_model.mjs`.
- That work implements local TUI classification, canonical-session resolution, bounded process ancestry, PID/start-time revalidation, and a pure association model. Preserve it. Do not start another scanner implementation.
- Last recorded checks: 27 attachment/model tests, the association model test, live self-process reader smoke, and whitespace checks passed. These are historical results, not final feature acceptance.
- The last requested Codex review result was not captured. Recover it if available; otherwise include the current Phase A diff in Task 1's review.
- Nothing has been committed or preview-reloaded for this feature. No nested tree UI or navigation is implemented yet.
- Preserve the unrelated untracked `empty-server.log`.

## Execution rules

- Implement the six tasks below sequentially. Give each worker only its task, ownership, acceptance criteria, and relevant interfaces.
- Cursor implementation args: `--model auto`. Codex review args: `--model gpt-6-astra -c model_reasoning_effort=high`. These identifiers were already verified; do not repeat model research unless a launch rejects them.
- Use the current Herdr session. Workers report completion through Herdr; wait with `herdr agent wait`, retaining the command session so the coordinator can resume the wait. Do not poll agent inventories or transcripts repeatedly.
- Workers do not reload the desktop, change settings, commit, push, or touch unrelated files. Coordinator reviews, checkpoints, previews, and closes task-owned panes after acceptance.
- One review of each completed task. Fix demonstrated defects, then review and check the changed paths. Do not restart a whole audit after each small fix or add tests merely to increase coverage.
- Keep the one provider, one helper per canonical endpoint, existing `herdr.agents` lease, discovery cadence, reconnect generations, and final-consumer shutdown.
- No new dependencies, generic tree framework, second dock, per-window provider, or per-screen lease.
- No PR, push, merge, or Linear work. No direct configuration-file writes.
- Before the first preview, rediscover the selected runtime with `smartdock dev status`, `smartdock status --json`, `smartdock config schema --json`, and `smartdock config get --json`. The widget was already enabled at the last check. Only mutate configuration if necessary, with a fresh private export, runtime instance selector, and the existing widget order preserved.
- Finish each visible milestone on the actual desktop before starting the next visible milestone. A passing headless check is not a substitute.

## Review focus

1. A replacement window or stale agent must never receive another agent's navigation: Tasks 1, 4, and 5.
2. Disconnected and partial inventories must not appear as healthy zero-agent sessions: Tasks 2 and 6.
3. Folding and matched-session filtering must not release the shared source or duplicate its inventory: Tasks 2, 3, and 6.
4. Long or markup-like names must remain plain text without covering kinds, counters, or controls: Task 3.
5. Agent input must not inherit window dragging, destructive menus, or modifier-based movement: Tasks 5 and 6.

## Task 1 — Finish the association bridge (remaining Phase A)

**Own:** `provider/herdr/attachments.py`, `provider/herdr/bin/smartdock-herdr-provider`, `provider/herdr/model.py`, `components/DockHerdrService.qml`, `components/DockHerdrModel.js`, and the identity-collection portion of `components/DockSidebarController.qml`.
**Checks:** Extend `provider/herdr/tests/test_provider.py`, `tests/test_herdr_sidebar_model.mjs`, and the existing controller/service test harness only for this connection.

The compositor supplies a PID, but not the `startTime` required by the current association model. Resolve the missing value through the existing provider's opened proc reader. This is implementation work, not a reason to restart design or stop the feature.

- [ ] Add `DockHerdrService.setWindowProcesses(revision, pids)`, writing one bounded JSON metadata command over the existing provider stdin:

  ```javascript
  { kind: "window-processes", revision: 1, pids: [123, 456] }
  ```

  Accept only an integer revision and at most 256 unique positive integer PIDs, within the existing 4 KiB command limit. Never accept paths, commands, or process arguments.
- [ ] Read UID and PID/start time through `open_linux_proc`; close every handle. Reuse the attachment scan and existing cadence. Publish the result in the normal snapshot:

  ```javascript
  windowProcesses: {
    revision: 1,
    identities: [{ pid: 123, startTime: 456789 }]
  }
  ```

- [ ] The controller gathers PIDs from each live window's Hyprland `lastIpcObject`, using its existing handle registry for identity. Increment the request revision when the live handle/PID set changes, even if a replacement uses the same PID. Workspace moves alone do not change this identity revision.
- [ ] Coalesce requests with the existing refresh scheduling. Reissue the latest request after a provider restart. Withhold new associations until the response matches the current request revision and provider epoch; do not start a feedback loop on every snapshot.
- [ ] Build `{key, pid, startTime}` inputs and call the existing `associateWindows(servers, windows)`. Keep nearest-ancestor matching, shared-terminal-PID ambiguity, unresolved-session fallback, and independently proven multiple windows for a session.
- [ ] Add checks for an obsolete metadata reply after window replacement, missing/foreign process identity, and successful use of a real resolved PID/start-time pair. Reuse the existing ancestry/parser tests without expanding that audit.
- [ ] Coordinator verifies the actual development terminal has one unambiguous association using live compositor and provider identities; print only the outcome, not raw argv/environment. If this specific live match fails, investigate the concrete mismatch before proceeding.
- [ ] Codex reviews the full outstanding Phase A change once. Run the affected checks and record the Phase A local commit. No desktop reload is needed for this backend checkpoint.

## Task 2 — Put actual agents in the tree (Phase B)

**Own:** `components/DockSidebarModel.js`, `components/DockSidebarController.qml`, `components/DockSidebarRow.qml`, `components/DockSidebarInteractionModel.js`, `components/DockHerdrAgentsView.qml`, `components/DockSidebarWidgetView.qml`, `components/DockSidebarWidgetArea.qml`.
**Checks:** `tests/test_herdr_sidebar_model.mjs`, existing sidebar/browser model checks, and the existing widget/controller harness.

- [ ] Read the normalized snapshot from `controller.widgetView("herdr.agents")`. Preserve the existing host-owned lease; `widgetsChanged()` schedules projection refresh when data changes.
- [ ] Add the snapshot and association map to `SidebarModel.project`. Emit child rows immediately after their associated window:

  ```javascript
  {
    kind: "herdr-agent",
    key: JSON.stringify(["herdr-agent", window.key, agent.id]),
    windowKey: window.key,
    providerEpoch: snapshot.providerEpoch,
    serverId: agent.serverId,
    agentId: agent.id,
    connectionGeneration: agent.connectionGeneration,
    paneId: agent.paneId,
    terminalId: agent.terminalId || "",
    title: agent.name || agent.label || agent.agent || "Coding agent",
    agentKind: agent.agent || "",
    status: agent.status
  }
  ```

- [ ] Extend existing tree annotations/compact child metrics. Preserve monitor/workspace placement, window handles, scroll anchors, stable agent ordering, and browser rows.
- [ ] Display `Herdr` on associated parent rows; retain the original window title in the normal tooltip. Main-area window activation remains unchanged.
- [ ] Filter matched servers and their agents out of the fallback view. Label remaining sources `Unmatched / unattached Herdr sessions`. Hide its entire redundant container when empty, while keeping the lease active. Folding never changes which sessions are matched.
- [ ] Emit non-actionable state children: `No active agents` only for known healthy empty inventory; `Reconnecting`, `Herdr unavailable`, or a partial-inventory indication otherwise. Preserve a last verified parent association during provider loss only while its exact live window handle/PID remains unchanged; never preserve actionable agents or live counts.
- [ ] Add one model fixture covering matching, unmatched fallback, movement/status key stability, and empty/unavailable distinctions. Check that delegates acquire no provider.
- [ ] Review, checkpoint, and run live checkpoint B. Required visible result: real agent names beneath the actual Herdr window. Agent activation is not yet enabled at this checkpoint.

## Task 3 — Finish the compact appearance and folding (Phase C)

**Own:** `components/DockHerdrModel.js`, `components/DockSidebarRow.qml`, `components/DockSidebarController.qml`, `components/DockSidebarInteractionModel.js`.
**Checks:** Extend the same Herdr model fixture and existing fold/controller checks.

- [ ] Add shared status normalization/counting and one status-color mapping. Count unique live agent IDs per window; counters appear in order `working`, `idle`, `done`, `blocked`, `unknown`, omitting zeros. Assert the five status counts sum to `agents`.
- [ ] Use accent blue, muted idle, green done, amber blocked, hollow/muted unknown. `done` describes Herdr state, not proven task success. Tooltips and accessibility labels include status text; counter tooltips include status and count.
- [ ] Render name and kind as plain text, with familiar capitalization (`Codex`, `Claude`, `Cursor`). Reserve kind/control width first, then elide the name. Reuse Omarchy `Color`/`Style` tokens and current tree connectors.
- [ ] Add session-memory fold keys `herdr:<window-key>`; missing means expanded. Keep counts visible when collapsed, consume chevron clicks, prune folds only when their window disappears, and restore them after rail mode.
- [ ] Use one combined layout fixture with long/markup-like names, missing kinds, all statuses, multi-digit counts, and narrow width. Verify fold persistence without a new subscription.
- [ ] Review, checkpoint, and run live checkpoint C. Inspect a tight dock crop, aligned kinds/counters, last-child connectors, and chevron behavior. If the original mockup is unavailable, use its documented hierarchy and layout; do not invent screenshot fixture content.

## Task 4 — Add the narrow focus transport (Phase D1)

**Own:** `provider/herdr/bin/smartdock-herdr-helper`, `provider/herdr/bin/smartdock-herdr-provider`, `provider/herdr/model.py`, `components/DockHerdrService.qml`, `tests/check_herdr_data_access.sh`, `docs/HERDR_DATA_ACCESS.md`.
**Checks:** Extend existing `test_protocol.py`, `test_provider.py`, and service tests.

- [ ] Confirm the installed Herdr `agent.focus` parameter shape from its existing API documentation/source once. Send only that method with the selected pane as target.
- [ ] Add `DockHerdrService.focusAgent(target)`, returning a request ID, and `focusAgentFinished(requestId, ok, errorCode)` for completion. Target:

  ```javascript
  { providerEpoch, serverId, connectionGeneration, agentId, paneId, terminalId }
  ```

- [ ] Resolve the endpoint from provider state; validate epoch, generation, live server, current agent membership, pane, and terminal identity. Never accept a socket path or arbitrary RPC method from QML. Reconcile current membership before the helper sends focus when required to reject a closed/replaced target.
- [ ] Return a bounded correlated action result; `acceptLine()` handles it separately from versioned snapshots. Timeouts finish once without automatic retry. Provider shutdown fails pending requests cleanly.
- [ ] Advertise the explicit navigation capability. Update the data-access guard/docs to allow this action and the bounded window-process metadata request while retaining all other control/privacy restrictions.
- [ ] Use one table-driven transport check for default/named endpoint routing, wrong epoch/generation, missing or changed agent, unavailable server, unsupported command, and timeout. Verify no extra helper/subscription starts.
- [ ] Review and checkpoint. This task exposes no UI activation yet; the live click check follows immediately in Task 5.

## Task 5 — Wire clicks to the captured agent pane (Phase D2)

**Own:** `components/DockSidebarController.qml`, `components/DockSidebarRowInput.qml`, and activation routing in `components/DockSidebarViewport.qml` / `components/DockSidebarRow.qml` where required by the existing path.
**Checks:** Extend existing sidebar interaction tests.

- [ ] Capture the exact window handle and full target on press. On release, revalidate the live row, association, handle, epoch, generation, and agent identity before invoking `focusAgent`.
- [ ] Suppress duplicate requests for the pending target. On successful completion, revalidate again before activating the containing window through the shared `DockWindowActions`. Show a short inline error on failure; do not activate another window or launch a terminal.
- [ ] Explicitly exclude agent rows from dragging, window close/context menus, and modifier-based movement. Unsupported modified clicks do nothing. Hover, snapshot changes, and expansion never navigate.
- [ ] Check removal between press/release and window replacement while a request is pending, using the existing captured-target harness.
- [ ] Review, checkpoint, and run live checkpoint D. With task-owned targets, click an agent in a different Herdr tab and confirm that exact pane is selected. Check a named-session target without changing the default session. Record provider/subscription continuity once.

## Task 6 — Keyboard, lifecycle, and final acceptance (Phase E)

**Own:** `components/DockSidebarKeyboard.qml`, `components/DockSidebarController.qml`, `components/DockSidebarInteractionModel.js`, `components/DockSidebarRow.qml`, `components/DockHerdrAgentsView.qml`, and relevant existing tests/docs.

- [ ] Make only live matched agents navigable. Enter uses the same captured-target activation path as clicking. Up/Down traverse visible navigable rows. Space folds a Herdr parent. Left collapses a parent or returns a child to its parent. Right expands a parent or enters its first agent. Preserve Escape's existing focus-return behavior.
- [ ] On collapse, move sidebar selection from a hidden child to its parent. On removal, recover to the parent or nearest surviving row. Data refreshes never steal desktop focus.
- [ ] Verify disconnection removes actionable children and counts, recovery uses a fresh baseline/generation, partial inventory remains explicit, and unmatched sessions remain readable. Keep fold memory and the shared lease through rail mode and mirrored screens.
- [ ] Add the missing keyboard/focus cases to `tests/tst_sidebarkeyboard.qml` and existing controller tests. Reuse existing lifecycle tests for final release/re-enable; add assertions only for the new integration.
- [ ] Finish `docs/HERDR_DATA_ACCESS.md`: nested presentation, conservative process association, unmatched fallback, explicit click-to-pane capability, shared ownership, and local-only privacy.
- [ ] Review and run the final regression gate once:

  ```bash
  python3 -B -m unittest discover -s provider/herdr/tests -p 'test_*.py' -v
  python3 -B -m unittest discover -s tests -p 'test_herdr_*.py' -v
  node tests/test_herdr_sidebar_model.mjs
  node tests/test_sidebar_model.mjs
  node tests/test_browser_tabs_model.mjs
  bash tests/check_herdr_data_access.sh
  bash tests/check_launcher_badge_counts.sh
  QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
  git diff --check
  ```

  Also run changed-QML lint with `-I "$OMARCHY_PATH/shell"`, applicable existing syntax checks, and `omarchy plugin validate .`. Identify unrelated baseline failures precisely; do not repair unrelated artifacts. Repeat failed/affected checks after a fix, not the entire suite without cause.
- [ ] Commit the reviewed task and run live checkpoint E: keyboard navigation, folding, moving the task window, rail/expanded modes, task-owned disconnect/recovery, and final consumer release/re-enable. Restore any touched setting afterward, keeping `herdr.agents` enabled for the requested final feature.
- [ ] Confirm one shared provider across the mirrored views; disabling the final consumer stops only SmartDock backend work while Herdr stays alive.
- [ ] Clean up only task-owned temporary windows/panes/sessions. Leave the newest verified source selected and running. Report the final SHA, visible result, checks, and any remaining concrete limitation.

## Live checkpoint procedure: B, C, D, E

1. Receive the worker report; inspect its diff and the Codex review. Run affected checks and QML syntax/whitespace checks. Commit only reviewed task files.
2. Tell the user what visible behavior will change. If the checkout is already selected, run `smartdock dev reload`; otherwise use `smartdock dev use /home/admin/Projects/smart-omarchy-dock`.
3. Rediscover the restarted host with `smartdock dev status` and `smartdock status --json`.
4. Inspect and interact with the actual existing desktop through Hypruse. Capture a tight local crop. A responding CLI alone does not pass.
5. Record the checkpoint SHA, checks, live outcome, and crop path in this document without private process arguments or user content.
6. If the dock breaks, restore only that checkpoint's task changes to the preceding working version, reload, and confirm recovery before fixing the demonstrated failure. Never reset the whole worktree or user preferences.

## Finish line

The feature is complete when real agents appear beneath the right Herdr window with correct counts and folds; clicking or pressing Enter opens the exact pane; keyboard/window/browser interactions still work; empty/disconnected/unmatched states are truthful; and the final verified version is visible on the user's desktop. Backend-only progress does not satisfy this finish line.
