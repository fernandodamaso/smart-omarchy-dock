# SmartDock CLI-first Migration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to execute the owning issue's approved slice with tests and an evidence-backed review. Do not repeat implementation already accepted by a predecessor.

**Goal:** Configure the existing dock through a discoverable host-owned CLI, preserve useful runtime behavior, remove Settings, and hand one exact Draft candidate to local qualification.

**Architecture:** The standard-library Python adapter parses/selects/transports; one DockControl belongs to DockHost outside per-screen delegates. Production models validate latest-state intents and the existing FileView remains the single live writer. The retained icon model/renderer is reused rather than rebuilt.

**Tech Stack:** Bash, Python 3 standard library, Quickshell/Qt QML, existing JavaScript models; existing shell/Node/Python/pure-QML CI.

**Spec:** [CLI reference](../CLI_REFERENCE.md), [complete inventory](../CONFIGURATION.md), [agent workflow](../AGENT_CONFIGURATION.md); approved Linear contract document `0766c721737f` and recipes document `0bdbe2e2e1dd`, under FDM-914.

## Global constraints

- Repository `fernandodamaso/smart-omarchy-dock`; aggregate `feat/fdm-914-cli-first`, Draft PR #44. Planning base `4f5d77b0fc7bf20a48365cd2c54dab00a150b373`.
- Unreleased candidate; no automatic merge, deployment, installed-checkout edit or local qualification by remote CLI-05.
- Preserve `Overlay.qml`, `shell.qml`, `Service.qml`, plugin identity and useful dock/app/window behavior. No second writer, daemon, provider startup, offline writer, capabilities registry, GUI/TUI, test framework or CI workflow.
- Configuration authority is selected-host metadata/path, not a guessed checkout path. Preserve unknown/legacy state and independent pins/hidden/artwork.
- AI owns review/fixes/test acceptance. Human involvement is limited to genuinely required credentials, destructive approval or unavailable physical/local observations.
- FDM-889 workspace dragging is independent. Never write/import its branch/PR; keep shared README/configuration documentation edits scoped and coordinate later reconciliation.

## Ordered implementation slices

### CLI-01 / FDM-915 — discovery and read contract (remote accepted)

- [x] Extend scripts/smartdock with explicit lifecycle separation; add scripts/smartdock_cli.py and single host-owned components/DockControl.qml.
- [x] Declare metadata/defaults, exact runtime selection, JSON/errors, status/doctor, requested/effective reads and offline guide/schema boundaries.
- [x] Add isolated CLI-only install/removal and retain standalone coexistence.

Accepted predecessor `d4d775672215788fa33abc3cbda1d78cfe07b6e4`; historical CI run `34527564715`. Not a substitute for final-head tests.

### CLI-02 / FDM-916 — atomic mutations and persistence (remote accepted)

- [x] Add typed set/apply/dry-run/reset/export/retry through DockConfigModel and the existing host FileView boundary.
- [x] Preserve unrelated state, no-op semantics, current-snapshot retry, failed-write echo protection and normal successful-save rollback.
- [x] Report actual save completion separately from live application; safe new-file-only export is not an offline writer.

Accepted predecessor `62fe86250efcc1ed6e6a2804703d795a6e479fa7`; historical CI run `34529571154`. Writer provenance is PR #43 at `7473a23abcfaca7454a7f791f241dd3e7ca9e061`.

### CLI-03 / FDM-917 — primitive app/icon intents (remote accepted)

- [x] Use native application catalog identities; preserve hidden/unavailable pins and relative order with latest-state primitive intents.
- [x] Reuse PR #42 model/renderer/forwarding at `27f35995d8da72a42d9a381250b1fd61783b51ae`; foundation `05a5b5cf614a56e7739172e7e6d987da8b721d23`, renderer `b734a6d1e2bd15fc7ee680230d6ddfba61c2a430`.
- [x] Add per-app icon list/set/reset/reload, same-source refresh and honest renderVerified:false without importing the Settings editor.

Accepted predecessor `5f9982cb139f101445bc97f4e54cfb952efe2357`; historical CI run `34534739067`.

### CLI-04 / FDM-918 — Settings cutover (remote accepted)

- [x] Remove Settings/menu route, preview-only preferences, exclusive controls/editor helpers and host/auto-hide coupling.
- [x] Preserve ordinary previews, picker, menus, drag, theme bindings, workspace/window behavior, Trash and shared writer.
- [x] Split mixed regression coverage; retain historical changelog/plan entries as history, not available UI routes.

Accepted input to CLI-05 `5c750cdfd843e403f8f1f2bd359f594df0f3b42c`; historical CI run `34539189072` (40 Python, 166 pure-QML). CLI-05 must re-run all checks at its own final head.

### CLI-05 / FDM-919 — docs, packaging, tested recipes and handoff

**Files:** create docs/CLI_REFERENCE.md, docs/CONFIGURATION.md, this plan and docs/CLI_RUNTIME_CHECKS.md; finish docs/AGENT_CONFIGURATION.md; scope README/CHANGELOG/AGENTS and install.sh updates to CLI documentation. Add focused tests/test_cli_docs.py through existing discovery, reusing tests/host_harness.mjs and actual CLI parsing. No new workflow or local-test framework.

**Interfaces:** consumes the accepted parser/schema/host/model/install behavior; produces offline installed guide/reference/inventory, executable recipe inputs and one exact-SHA local runbook.

- [x] Add failing tests for missing deliverables, installed documentation and marked recipe inputs before implementation.
- [x] Observe the actual test-first CI failure at `6e876fbc2bac975d2e944a09a82375c77ad51fce`, run `34590436812`: five new documentation assertions fail while the existing 40 Python tests and 166 QML tests pass.
- [ ] Publish all docs and scoped packaging/routing changes; execute actual guide input through the real parser and production-host harness.
- [ ] Review the aggregate source/contract/integration, fix actionable findings, and obtain full existing exact-head CI.
- [ ] Record actual final base/head/check URLs and pause remote branch writes in FDM-919. Mark remote completion and local readiness only when evidence supports it.

The remaining checkboxes are evidence steps, not a request for human review. The live FDM-919 completion comment and PR review/checks at the named SHA are authoritative; this plan does not pre-claim their result.

### CLI-06 / FDM-920 plus retained ICO-08 / FDM-885 — local gate

- [ ] Acquire the handed exact Draft head in isolated source/display/config/artwork state; no merge/deploy prerequisite.
- [ ] Execute [CLI_RUNTIME_CHECKS.md](../CLI_RUNTIME_CHECKS.md), including real IPC/FileView, theme/image/cache and actual monitor behavior with surviving icon checks in the same run.
- [ ] Let the local coding agent fix evidenced defects, review/retest and publish fresh exact-SHA CI; preserve unknown keys, pins, original artwork and concurrent work.
- [ ] Record PASS/FAIL/NOT RUN honestly and restore touched test state. Deleted Settings/dialog cases are superseded, not passed. Keep unresolved runtime requirements open.

## Verification and source ownership

Use the existing CI commands in docs/DELIVERY.md: shell syntax; every tests/check_*.sh; every tests/test_*.mjs; Python unittest discovery; pure-QML qmltestrunner; git diff --check against the actual base. These execute source behavior with unavailable transport/FileView services substituted and do not prove the full Omarchy runtime. No historical #42/#43 test result is final-head acceptance.

The remote handoff carries repository, PR/branch, actual base/head, commands/results/exact-head CI, implemented surface, explicit not-yet-verified runtime claims, exact-head runbook link, retained icon provenance and next local owner. After handoff, remote writes pause until the local owner releases ownership. Never absorb FDM-889's unrelated drag work or force-push over newer source.
