# FDM-885 Remaining Qualification and Adoption Implementation Plan

> **For the executing Cursor agent:** Execute this plan task-by-task and track progress with the checkboxes. Own implementation, review, testing, and evidence through completion; no particular model, reasoning-effort setting, agent orchestration tool, or skill framework is required.

**Goal:** Resolve the remaining writer-review concern, finish FDM-885's real runtime acceptance, preserve/adopt the existing ChatGPT artwork through authorized delivery, and publish accurate completion evidence.

**Architecture:** Retain the single DockHost writer, shared artwork renderer, existing Settings editor and resolved desktop-ID routes. Fix only demonstrated defects in their owning components. Runtime qualification uses disposable configuration and real native input; production adoption follows the repository's PR/plugin-update path.

**Tech Stack:** QML/Qt 6, Quickshell, Omarchy/Hyprland, existing Node VM tests and QML tests, ydotool, grim, gh, Linear.

**Spec:** [FDM-885](https://linear.app/fdamaso/issue/FDM-885), [FDM-877](https://linear.app/fdamaso/issue/FDM-877), [implementation contracts, sections 10–11](https://linear.app/fdamaso/document/smartdock-app-icon-overrides-implementation-plan-and-agent-contracts-21a2238b0bb5), `AGENTS.md`, `docs/DELIVERY.md`. Read the full current issues and comments before execution.

## Global Constraints

- Work in `/home/admin/Projects/smart-omarchy-dock`, on `feat/fdm-881-app-icon-workflow`; one source writer at a time.
- Original input: `304735ad1e7e34f85fb049a91ebc34d86de1f40b`. Resume head: `ade2f5876f0937dc3ef1b380ba4f8e3017ff9ea2`.
- PR #43 base: `feat/fdm-878-app-icon-overrides` at `27f35995d8da72a42d9a381250b1fd61783b51ae`; PR #42 carries that parent delivery.
- Preserve unrelated work. No reset/clean, force-push, direct feature merge to main, installed-checkout edits, or user-artwork deletion.
- App-wide, dock-only artwork; identity, grouping, launching, thumbnails, badges and global launchers remain behaviorally intact.
- No second writer/service, polling, runtime dependency, broad refactor, or new CI gate.
- Agent-opened windows must be silently placed on the coding agent's workspace without moving existing windows or switching the user's workspace.
- Do not treat model tests, config edits, screenshots of an unopened UI, or direct `Overlay.qml` startup as proof of unperformed UI/hosted-overlay actions.
- No human review/acceptance gate. Stop only for a genuine authorization, credential, destructive-action or inaccessible physical-observation boundary.
- Merge/deployment authorization is separate from branch-write/runtime authorization. Do all feasible pre-delivery qualification before stopping at that boundary.
- Each new commit needs fresh exact-head evidence. Preserve historical evidence as historical; consolidate the final record.

## Resume state and evidence

Three commits already pushed:

| Commit | Purpose |
|---|---|
| `8454060` | Restore missing grouped Settings boolean and regression guard. |
| `3beb72a` | Preserve failed optimistic settings for Retry. |
| `ade2f58` | Defer watcher reloads and distinguish pre-write bytes from external edits; executable writer-sequence coverage. |

CI passed at the resume head: run `34504776397`. Existing observations include real standalone Change/Apply/Restore, chooser Cancel/Escape/layering, menu navigation, outside-click dismissal, failed Apply + Retry, and external edit during error + Retry. Prior local results include 171 pure QML tests and 16 wrapper tests. These do not prove remaining acceptance below.

Historical local artifacts (check existence; `/tmp` is not durable): `/tmp/fdm885-report.md`, `/tmp/fdm885-review.md`, `/tmp/fdm885-ui.oTVzeO/`, `/tmp/fdm885-ui-retry.etUMLT/`, `/tmp/smartdock-fdm885-runtime.cAsq2C/`. Final re-review did not return a report; do not claim it passed.

Existing user config: `~/.config/smartdock/dock.json`. Existing artwork: `/home/admin/Pictures/Icons/svg/chatgpt.svg`. Prior hashes were respectively `9ea2f04b93002c560816bd774b362ee2a75c987d6cd570c9823db16d12d01d17` and `5a8dad2864cc1c8109ebae74bea447df2f30b978bdad56749247c406e1cb2227`; a difference now may be subsequent user work, not damage to undo.

## File ownership

- `DockHost.qml`: writer and watcher lifecycle; only change after reproduction.
- `tests/test_icon_settings_write.mjs`: executable production-handler regressions.
- `tests/test_icon_overrides.mjs`: adjust fixture fields only if the host contract needs them.
- `components/DockIconOverrideEditor.qml`, `DockSettings.qml`, `DockAppIcon.qml`, `Dock.qml`, `DockItem.qml`, `DockContextMenu.qml`: only narrow fixes demonstrated by the runtime matrix.
- `local-tests/tst_icon_override_editor.qml` and existing fixtures: targeted editor/runtime regressions where needed.
- This plan is the tracked checklist. Keep screenshots and transient logs in an execution-specific temporary directory; publish concise durable PR/Linear evidence.

### Task 1: Re-establish baseline and close the writer review

**Consumes:** current branch, production FileView handlers, `fixture()` in `tests/test_icon_settings_write.mjs`.
**Produces:** reviewed writer behavior and a new tested commit only if a defect is confirmed.

- [ ] Inspect `git status`, worktrees, remote refs, PR #42/#43 and current Linear state. Fetch safely; never overwrite this planning document or unrelated work. If the remote advanced, inspect the additional commits before adopting them.
- [ ] Establish exclusive branch-write ownership before editing. If another worker is reviewing concurrently, keep its access read-only and record its review result.
- [ ] Reproduce the outstanding concern: after successful save B and watcher settlement, an external editor restores exact pre-write bytes A. `onLoaded` currently suppresses A based on `settingsWriteBaseText` even while the writer is saved.
- [ ] Add this executable case using the existing fixture (before altering production):

```js
check('external rollback to pre-write bytes loads after a successful save', () => {
  const f = fixture()
  const original = JSON.stringify(plain(f.host.settings), null, 2) + '\n'
  f.load(original)
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  f.complete()
  f.fileChanged()
  f.flush()
  assert.equal(f.host.settings.iconOverrides.chatgpt, 'file:///tmp/chatgpt.svg')
  f.external(original)
  f.flush()
  assert.deepEqual(plain(f.host.settings), JSON.parse(original))
})
```

- [ ] Run `node tests/test_icon_settings_write.mjs` and record the actual RED result. If it does not fail, explain the event sequence and do not make a speculative fix.
- [ ] If confirmed, first evaluate the minimal restriction of stale-base suppression to a failed-write state:

```qml
if (root.settingsWriteState === "error"
    && raw === root.settingsWriteBaseText) return
```

This is a candidate correction, not a pre-approved final implementation. Check actual FileView timing and consecutive saves before accepting it. Do not add generalized transactions or timers to solve an unobserved race.
- [ ] Keep executable coverage for failed Apply, failed Restore, unchanged old-disk notification, external edit during saving/error, successful completion followed by external rollback, consecutive saves, and Retry writing the latest whole map. Run `node tests/test_icon_settings_write.mjs` and all `tests/test_icon*.mjs`.
- [ ] Reproduce successful-save/external-rollback in the real disposable runtime and repeat failed Apply + Retry to ensure both contracts hold.
- [ ] Run Task 5's gate before committing a runtime fix, stage only intended source/test files, commit normally and push the same feature branch. Record input/new head.
- [ ] Perform a fresh review of the complete local-fix range and this writer sequence. Resolve actionable findings with focused tests; retain an explicit verdict and any residual concern.

### Task 2: Complete standalone editor, persistence and failure scenarios

**Consumes:** Task 1 candidate, `SMARTDOCK_CONFIG`, existing Settings/editor and one host writer.
**Produces:** real UI evidence for each row below; owning-component fixes only for reproduced failures.

- [ ] Create a fresh disposable config and fixture directory under `/tmp/opencode`; back up real config before any later real-config action. Inspect current monitors, clients and layers. Keep the installed bottom dock intact; use one agent-owned source dock on a safe alternate edge.
- [ ] Start native input using a disposable ydotool daemon/socket. Verify pointer coordinates with `hyprctl cursorpos`; do not reuse old screenshot coordinates or the previous scaling factor blindly. Keep dock/input processes alive for the scenario duration, record their exact PIDs, and clean them up afterward.
- [ ] Exercise every sequence below through the UI, observing config bytes separately from session rendering:

| Sequence | Required observation |
|---|---|
| Failed Restore with config file mode 0444, then 0644 and Retry | Row disappears from session, warning/Retry remains visible; Retry removes only the correct disk key and keeps all other settings. |
| Select A then B quickly | Only B can become applicable; no stale A preview/completion can write. |
| Open chooser for app A, then switch/close owner | Stale acceptance cannot affect app B; Cancel/Escape leaves config unchanged. |
| Valid draft plus unrelated external setting change | Draft remains usable. |
| Valid draft plus external override change for selected app | Draft invalidates and actual external value appears. |
| Edit same temporary SVG and reselect exact path | Preview and applied artwork show new bytes without restarting. |
| Apply PNG/SVG with spaces/Unicode and alpha/non-square shape | Correct colors/proportions/transparency, unchanged dock geometry; custom artwork not tinted. |
| Apply override, use Appearance Reset | Override remains while appearance defaults reset. |
| Apply from UI, terminate only test dock, restart same config | Persisted choice reappears; Restore removes it durably. |
| Open chooser, Escape, outside click, reopen | Topmost dialog owns Escape; no orphan popup or stuck-open dock. |

- [ ] For each failure: capture reproduction, add the smallest meaningful regression in the owning existing test, fix on the same branch, run affected checks and Task 5's gate, and repeat the failed real sequence on the new head.

### Task 3: Complete artwork parity, app behavior and lifecycle checks

**Consumes:** candidate from Tasks 1–2, real DesktopEntries, shared `DockAppIcon` inputs, existing window controller.
**Produces:** confirmed cross-surface and behavior parity; explicit unavailable-hardware records.

- [ ] Resolve the actual local ChatGPT item from its desktop entry/window, distinguishing `chatgpt.desktop` from `ChatGPT Website.desktop`; do not infer identity from its title.
- [ ] Apply a distinctive disposable icon. Observe main dock, preview metadata, picker rows and hidden-app rows using the same app identity. Compare preview screenshots before/after to ensure thumbnails remain untouched.
- [ ] Test missing and corrupt custom artwork, then missing/corrupt desktop fallback in disposable entries/fixtures. Observe normal/generic/bundled terminal fallback without repeated retries; confirm failed map is still listed and removable.
- [ ] Pin/unpin and hide/unhide the test app. Confirm retained override and correct presentation; do not count the earlier hidden-config mutation alone as pass.
- [ ] Launch the closed pinned app with its original launch route; verify focus/minimize and grouping remain correct. Use silent launch placement, record only agent-created window addresses, and close only those windows afterward. If ChatGPT delegates to an existing window, do not silently substitute another app as ChatGPT evidence.
- [ ] Exercise grouped/ungrouped windows across workspaces and both available monitors. Confirm app-wide changes, badges/actions and source identity remain stable. Keep user windows/workspaces intact.
- [ ] Test pointer-driven auto-hide, Settings/chooser holding the dock open, dismissal returning it to hiding, and alternate edges. Confirm layer cleanup after owner destruction.
- [ ] Test screen lifecycle via a supported removable agent-created virtual output if available, without disabling physical user monitors. A virtual-output test proves only that lifecycle path; physical hotplug remains explicitly not run if unavailable.

### Task 4: Qualify the actual hosted overlay before production adoption

**Consumes:** tested source candidate and installed Omarchy plugin-loader behavior.
**Produces:** real host-owned overlay evidence, distinct from standalone/direct entrypoint evidence.

- [ ] Read the installed plugin loader and supported validation/development commands without editing deployment checkouts. Establish a supported isolated source-plugin hosting route using a temporary plugin registry/config or source-host harness with the actual loader and services.
- [ ] Document exactly what host is used. Loading `Overlay.qml` as a top-level standalone config does not satisfy this task; a second shell is never launched from inside the plugin.
- [ ] In that actual hosting route, exercise ordinary Apply/Restore, chooser layering/Escape, persistence, and popup disposal using isolated config and a safe edge. Ensure the plugin shares its host process and controller.
- [ ] If no supported isolated hosting route can be established, finish Tasks 1–3 and 5, publish the precise hosting constraint, and request only the required merge/deployment authorization. Do not waive hosted testing or claim it passed.

### Task 5: Validate and publish exact-head qualification

**Consumes:** final candidate and scenario results.
**Produces:** clean pushed branch, current CI and one consolidated PR/Linear evidence record.

- [ ] Run the full gate with a safe disposable `SMARTDOCK_CONFIG`. Timeout 124 is acceptable only when logs prove successful loading and expected timeout, not an earlier fatal error.

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh
for script in tests/check_*.sh; do bash -n "$script" || exit; bash "$script" || exit; done
for script in tests/test_*.mjs; do node "$script" || exit; done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
OMARCHY_PATH=/usr/share/omarchy bash tests/run_action_dropdown_settings.sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml shell.qml
git diff --check
git diff --check origin/feat/fdm-878-app-icon-overrides...HEAD
```

- [ ] Record all exit codes; loops must fail on any failed test. Classify lint warnings, raw-QML import limitations and portal warnings separately from actual failures. The wrapper uses Quickshell stubs: it is not physical host evidence.
- [ ] After the last source commit, verify clean status, local/remote SHA equality, and `Headless CI` success for that exact SHA with `gh pr view 43 --repo fernandodamaso/smart-omarchy-dock --json headRefOid,baseRefOid,statusCheckRollup,isDraft`.
- [ ] Update PR #43 and FDM-885 with a consolidated record: original input, final base/head, commits/fixes, versions, commands/results, each runtime criterion's pass/fail/not-run status, review verdict, config/artwork preservation and adoption status. Link useful screenshots only; replace stale current-head claims without erasing historical context.
- [ ] Move FDM-885 to In Progress if still Ready. Update FDM-877's current state to qualification/adoption pending until Task 6 is complete. Neither issue becomes Done on CI alone.

### Task 6: Authorized delivery, real ChatGPT adoption and completion

**Consumes:** qualified candidate, explicit normal delivery authorization, preserved user config/artwork.
**Produces:** update-preserved real customization and honestly completed issues.

- [ ] Check whether explicit merge/deployment authorization already exists. If absent, request that bounded decision after all feasible qualification; no manual code review or runtime-validation request is needed.
- [ ] Follow `docs/DELIVERY.md`: deliver PR #42 through its PR path; retarget/rebase or rebuild PR #43 on resulting main; preserve remote work and do not force-push without authorization. Record the new base/head and rerun required checks/runtime gates after the stack changes.
- [ ] Deliver PR #43 only after current checks/review/required qualification. Update the installed plugin using the discovered supported `omarchy plugin update` command. Never patch installed files directly.
- [ ] Back up current real user config, then select `/home/admin/Pictures/Icons/svg/chatgpt.svg` from the actual ChatGPT item's new UI. Verify resolved target, all relevant real surfaces and unchanged launching/focusing/minimizing/grouping.
- [ ] Restart through the supported shell/plugin lifecycle and verify persistence. Use Restore and verify default behavior, then reapply the chosen existing artwork so final state is the requested customization.
- [ ] Exercise a normal supported plugin update/reload and compare config/artwork checksums and references. Record actual source/installed revisions; a no-op already-up-to-date check is not evidence of a revision-changing update.
- [ ] Publish final adoption and update evidence. Mark FDM-885 Done only when all required scope is met; update FDM-877's success criteria and mark it Done only when its qualification/adoption scope is also met. Unavailable optional physical hardware checks remain clearly not run.
- [ ] Close task-created test processes and windows, restore disposable file permissions, verify only intended production dock remains, and report final SHA, PR links, adoption result and any genuine residual blocker.

## Completion review

Before claiming completion, reconcile every FDM-885 checklist row with Tasks 1–6 and the final evidence record. Do not count historical tests against a changed writer/renderer without affected revalidation. Review verifies both source correctness and whether the recorded physical actions actually cover the requirement; incomplete evidence is remaining work, not a pass.
