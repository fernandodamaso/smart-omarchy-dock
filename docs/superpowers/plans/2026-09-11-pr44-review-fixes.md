# PR #44 Review Fixes Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this bounded review patch and verify each resulting SHA.

**Goal:** Fix the three reproduced configuration/drag regressions and finish the Settings cutover cleanup without expanding into speculative runtime hardening.

**Architecture:** Keep one host-owned writer. Standalone default configuration must live outside bundled defaults. Reject surrounding whitespace in new bulk identity arrays while preserving untouched legacy values. Translate drag placement into the existing latest-state application move intent, preserving forward/after and backward/before semantics.

**Tech Stack:** Existing Bash, Python, QML and JavaScript model harnesses and Headless CI; no added dependency or workflow.

**Spec:** The accepted PR #44 review and K3 reconciliation in the user conversation, with source input `5e8aa532a04ec2039f7255736e04573cac64de35` and base `4f5d77b0fc7bf20a48365cd2c54dab00a150b373`.

## Global constraints

- Work only on `feat/fdm-914-cli-first` / Draft PR #44; no force-push, merge, deployment or changes to PR #45.
- Preserve unknown settings, legacy pins, pin order, hidden membership and icon mappings.
- Do not weaken bulk schema validation or reintroduce a GUI/second writer.
- The completed FDM-920 run concerns the old exact SHA; new runtime changes need relevant retesting, not automatic reuse of that evidence.
- Retain valid writer provenance and useful renderer diagnostics. Client-side validation duplication, bundle-corruption hardening and transport-error reclassification are outside this focused patch.

## Execution

- [ ] Add `tests/test_pr44_regressions.mjs` and observe its five regression groups fail against unchanged production source in the existing CI. Tests exercise actual host/model methods, actual standalone path binding, private-filesystem restart/reset, both drag directions, validation/preservation, local fixture imports and migration notes.
- [ ] Update `shell.qml`: retain `SMARTDOCK_CONFIG` precedence; otherwise use `(XDG_CONFIG_HOME || HOME + '/.config') + '/smartdock/dock.json'`. Never copy or overwrite existing user state on discovery.
- [ ] Update `components/DockConfigModel.js`: reject newly supplied application-array values whose spelling differs from `trim()`, while preserving internal spaces, case, accepted suffixes and all untouched values.
- [ ] Update `DockHost.qml`: derive drag source/target indices using canonical IDs, choose `after` for a forward drop and `before` for a backward drop, and use `changeApplication('move', args)`. Retain busy/persistence/no-op handling and strict bulk validation.
- [ ] Delete the obsolete local dropdown fixture; make both removal audits traverse `local-tests/` when present and tolerate its absence. Mark the historical FDM-858 audit superseded, retaining its historical record. Add explicit launcher/source-config migration notes to CHANGELOG.
- [ ] Run all existing Headless CI stages at the final SHA, inspect failures and source diff, fix only evidenced issues, and record exact base/head, tests and runtime boundary in PR #44 and the existing Linear handoff.

## Verification commands

```bash
node tests/test_pr44_regressions.mjs
for script in install.sh uninstall.sh scripts/smartdock scripts/run tests/check_*.sh; do bash -n "$script" || exit; done
for script in tests/check_*.sh; do bash "$script" || exit; done
for script in tests/test_*.mjs; do node "$script" || exit; done
python3 -m unittest discover -s tests -p 'test_*.py'
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
git diff --check 4f5d77b0fc7bf20a48365cd2c54dab00a150b373...HEAD
```

Tests substitute FileView/Quickshell services and do not establish real compositor drag, plugin loading or FileView timing. The next local owner must requalify those affected cases and retain the outstanding FDM-885 surface-interaction checks.
