# Host-Owned Window Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-menu/per-monitor window lifecycle ownership with one host-owned `DockWindowActions.qml` shared by every dock instance, without changing visible behavior.

**Architecture:** `DockHost.qml` owns exactly one controller and passes it through `Dock.qml` to `DockItem.qml` and `DockContextMenu.qml`. Mutable minimized-origin state stays in the controller; pure active-member/group helpers stay in `DockModel.js`. Existing click/menu behavior is preserved while consumers delegate lifecycle operations to the controller.

**Tech Stack:** Qt 6, QML/QtQuick, Quickshell Wayland/Hyprland APIs, JavaScript helpers, QtTest, Bash structural checks.

**Spec:** `docs/superpowers/specs/2026-09-02-host-owned-window-actions-design.md`

## Global Constraints

- Work only in the canonical Git-backed SmartDock source.
- Never edit installed Omarchy plugin state or `~/.config/smartdock/dock.json`.
- Preserve existing left-click, grouped cycling, context-menu, drag, tooltip, auto-hide, fullscreen, workspace-strip, standalone, and plugin behavior.
- Do not implement FDM-808 wheel delivery, FDM-810 previews, FDM-812 filtering, FDM-815 pointer settings, badges, urgency motion, or intelligent hide.
- Keep minimized origins and monitor identity ephemeral; never persist them to disk.
- Prefer Quickshell/Hyprland APIs over subprocesses.
- Runtime/local validation is mandatory before merge even if the GitHub-only implementation phase cannot execute it.

---

### Task 1: Add failing group-selection and architecture tests

**Files:**
- Modify: `tests/tst_dockmodel.qml`
- Create: `tests/check_window_actions.sh`

**Interfaces:**
- Produces expected pure API: `DockModel.liveGroupMembers(candidates, liveToplevels)` and `DockModel.activeGroupMember(candidates, activeToplevel, liveToplevels)`.
- Produces structural contract for one host-owned `DockWindowActions` instance.

- [ ] **Step 1: Add failing model tests**

Append tests equivalent to:

```qml
function test_filtersGroupMembersAgainstLiveToplevels() {
  var one = { title: "one" }
  var two = { title: "two" }
  var stale = { title: "stale" }

  var live = DockModel.liveGroupMembers([one, null, stale, two], [one, two])

  compare(live.length, 2)
  compare(live[0], one)
  compare(live[1], two)
}

function test_resolvesActiveGroupMemberOrDeterministicFallback() {
  var one = { title: "one" }
  var two = { title: "two" }
  var stale = { title: "stale" }

  compare(DockModel.activeGroupMember([one, two], two, [one, two]), two)
  compare(DockModel.activeGroupMember([one, two], stale, [one, two]), one)
  compare(DockModel.activeGroupMember([stale], stale, [one, two]), null)
  compare(DockModel.activeGroupMember([], null, [one, two]), null)
}
```

- [ ] **Step 2: Add the structural test**

Create `tests/check_window_actions.sh` so it fails until the foundation exists. It must assert:

```bash
#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

test -f components/DockWindowActions.qml

test "$(grep -c 'DockWindowActions[[:space:]]*{' DockHost.qml)" -eq 1
! grep -q 'DockWindowActions[[:space:]]*{' components/Dock.qml
! grep -q 'DockWindowActions[[:space:]]*{' components/DockItem.qml
! grep -q 'DockWindowActions[[:space:]]*{' components/DockContextMenu.qml

grep -q 'required property var windowActions' components/Dock.qml
grep -q 'required property var windowActions' components/DockItem.qml
grep -q 'required property var windowActions' components/DockContextMenu.qml

! grep -q 'property var minimizedOrigins' components/DockContextMenu.qml

grep -q 'windowActions: root.windowActions' components/Dock.qml
grep -q 'windowActions: root.windowActions' components/DockItem.qml
```

Use slightly stronger patterns if needed to avoid false positives.

- [ ] **Step 3: Verify RED locally**

Run:

```bash
qmltestrunner -input tests -import components
bash tests/check_window_actions.sh
```

Expected before implementation: model tests fail because the new helpers do not exist; structural check fails because `components/DockWindowActions.qml` does not exist.

In the GitHub-only phase, record this step as pending rather than pretending it ran.

- [ ] **Step 4: Commit tests before production code**

```bash
git add tests/tst_dockmodel.qml tests/check_window_actions.sh
git commit -m "test: define shared window actions contract"
```

---

### Task 2: Add pure group helpers and host-owned controller

**Files:**
- Modify: `components/DockModel.js`
- Create: `components/DockWindowActions.qml`
- Modify: `DockHost.qml`

**Interfaces:**
- Consumes: `DockModel.normalizeWindowAddress`, `DockModel.minimizeWindowRequest`, `DockModel.restoreWindowRequest`, `DockModel.focusWindowRequest`.
- Produces controller methods: `handleFor`, `addressFor`, `isAlive`, `isMinimized`, `windowState`, `originFor`, `originSnapshot`, `liveMembers`, `activeMember`, `minimizeToplevel`, `restoreToplevel`, `activateToplevel`, `closeToplevel`.

- [ ] **Step 1: Implement minimal pure helpers**

Add:

```js
function liveGroupMembers(candidates, liveToplevels) {
  var values = candidates || []
  var live = liveToplevels || []
  var result = []
  for (var i = 0; i < values.length; ++i) {
    var candidate = values[i]
    if (candidate && live.indexOf(candidate) >= 0)
      result.push(candidate)
  }
  return result
}

function activeGroupMember(candidates, activeToplevel, liveToplevels) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length === 0) return null
  if (activeToplevel && live.indexOf(activeToplevel) >= 0)
    return activeToplevel
  return live[0]
}
```

- [ ] **Step 2: Implement `DockWindowActions.qml`**

Use one QML `Item` with internal `property var minimizedOrigins: ({})` and a public copied snapshot. Required behavior:

```qml
function handleFor(toplevel) { ... }
function addressFor(toplevel) { ... }
function isAlive(toplevel) { ... }
function workspaceTarget(workspace) { ... }
function monitorIdentity(handle) { ... }
function originFor(value) { ... }
function originSnapshot() { ... }
function isMinimized(toplevel) { ... }
function windowState(toplevel) { ... }
function liveMembers(toplevels) { ... }
function activeMember(toplevels) { ... }
function minimizeToplevel(toplevel) { ... }
function restoreToplevel(toplevel) { ... }
function activateToplevel(toplevel) { ... }
function closeToplevel(toplevel) { ... }
function pruneOrigins() { ... }
```

Prefer `handle.lastIpcObject.workspace` over `handle.workspace` for origin lookup. Resolve monitor identity from IPC monitor data/name when present, otherwise leave it empty.

`restoreToplevel` must not clear an origin until it has a valid restore request to dispatch.

- [ ] **Step 3: Add lifecycle cleanup**

Connect to `ToplevelManager.toplevels`/`Hyprland.toplevels` changes and prune stored addresses that no longer correspond to a live window.

- [ ] **Step 4: Instantiate once in `DockHost.qml`**

Add one controller with a stable id such as:

```qml
DockWindowActions {
  id: windowActions
}
```

Pass `windowActions` to every `Dock` variant.

- [ ] **Step 5: Run focused tests locally**

```bash
qmltestrunner -input tests -import components
bash tests/check_window_actions.sh
```

Expected: pure helper tests pass; structural test may still fail until downstream wiring is finished.

- [ ] **Step 6: Commit controller foundation**

```bash
git add DockHost.qml components/DockModel.js components/DockWindowActions.qml
git commit -m "feat: add host-owned window actions controller"
```

---

### Task 3: Refactor Dock, DockItem, and DockContextMenu to consume the shared controller

**Files:**
- Modify: `components/Dock.qml`
- Modify: `components/DockItem.qml`
- Modify: `components/DockContextMenu.qml`

**Interfaces:**
- Consumes the controller API from Task 2.
- Produces no new user-facing behavior.

- [ ] **Step 1: Wire `Dock.qml`**

Require `windowActions` on `Dock.qml` and pass it to every `DockItem`.

- [ ] **Step 2: Wire `DockItem.qml`**

Require `windowActions`.

Change `activateOrLaunch()` so existing grouped-index behavior remains intact but activation calls:

```qml
root.windowActions.activateToplevel(runningToplevels[lastActivatedToplevel])
```

Pass the same controller to `DockContextMenu`.

Do not add wheel/middle/Shift handlers.

- [ ] **Step 3: Remove local lifecycle ownership from `DockContextMenu.qml`**

Require `windowActions` and remove local `minimizedOrigins`, `hyprToplevelFor`, `addressFor`, `isToplevelMinimized`, `clearMinimizedOrigin`, `minimizeToplevel`, `restoreToplevel`, `activateToplevel`, and any redundant copy-map/origin helpers.

Replace state bindings with controller calls, for example:

```qml
readonly property var selectedHandle: root.windowActions.handleFor(selectedToplevel)
readonly property bool selectedMinimized: root.windowActions.isMinimized(selectedToplevel)

function windowState(toplevel) {
  return root.windowActions.windowState(toplevel)
}
```

Menu actions call the shared controller for activation, minimize, restore, and close.

Move-to-workspace may continue to use the existing request helper, but ensure moving a SmartDock-minimized window clears its stale origin through a narrow controller method such as `forgetOrigin(toplevel)`.

- [ ] **Step 4: Preserve fullscreen and workspace actions**

Verify `selectedInfo`, fake fullscreen, `selectedWorkspaceId`, Move to Workspace, and window labels continue to resolve from the selected current handle.

- [ ] **Step 5: Run the contract tests locally**

```bash
qmltestrunner -input tests -import components
bash tests/check_window_actions.sh
```

Expected: PASS.

- [ ] **Step 6: Commit the consumer refactor**

```bash
git add components/Dock.qml components/DockItem.qml components/DockContextMenu.qml
git commit -m "refactor: share window lifecycle actions across docks"
```

---

### Task 4: Update validation documentation and prepare local handoff

**Files:**
- Modify: `AGENTS.md`
- Optionally modify: `README.md` only if architecture documentation is useful; no user-facing feature notes are required.

**Interfaces:**
- Produces exact local validation instructions for the Omarchy-capable agent.

- [ ] **Step 1: Add the new QML/test surfaces to validation guidance**

Extend the lint command to include `components/DockWindowActions.qml` and list `tests/check_window_actions.sh` among required checks.

- [ ] **Step 2: Run full local validation**

The local Omarchy agent must run:

```bash
timeout 6s ./scripts/run --no-color
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh
omarchy plugin validate .
qmltestrunner -input tests -import components
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockWindowActions.qml shell.qml
git diff --check
```

Then manually exercise single/grouped focus, minimize/restore, workspace switch while minimized, cross-monitor restore, close during menu interaction, fullscreen-to-other-app focus, grouped/ungrouped mode, standalone mode, plugin mode, and monitor reconnect when available.

- [ ] **Step 3: Record unresolved environment-only risks**

Do not claim runtime completion until the local agent confirms all commands and manual checks.

- [ ] **Step 4: Commit handoff documentation**

```bash
git add AGENTS.md
git commit -m "docs: add window actions validation gate"
```

## Completion Gate

Before merge, all four tasks must be complete and the local agent must provide actual command output for the full validation gate. The GitHub-only phase may prepare code and tests, but must leave runtime verification explicitly pending.