# SmartDock Hidden Applications Implementation Plan

**Goal:** Add persistent application-level hiding to SmartDock without closing, minimizing, or unpinning applications.

**Architecture:** Store canonical application identifiers in a new `hiddenApplications` configuration array. Build the normal grouped dock model first, then remove items whose normalized desktop ID is hidden. Expose hiding from each app icon's context menu and restoration from a dedicated Dock Settings section.

**Tech Stack:** Quickshell, Qt/QML, JavaScript helpers in `DockModel.js`, QtTest, shell validation scripts.

## Global Constraints

- Work only in the canonical source repository's isolated `codex/hidden-applications` worktree.
- Use `gpt-5.6-luna` at `xhigh` reasoning for implementation and review subagents.
- Follow strict test-first development: add a failing behavioral test, observe the expected failure, then write production code.
- Do not publish, push, update the installed Omarchy plugin, or edit `~/.config/smartdock/dock.json`.
- Hidden applications remain running, pinned, and available through Alt-Tab and workspaces.
- Hiding applies to the entire application across all current and future windows.
- Nothing is hidden by default, including Wispr Flow.
- Existing settings without `hiddenApplications` behave as an empty list.
- General settings reset does not clear `hiddenApplications`.
- Preserve unrelated behavior and do not absorb uncommitted changes from the original `main` checkout.

### Task 1: Persistence and Model Filtering

**Files:**
- Modify: `components/DockModel.js`
- Modify: `components/Dock.qml`
- Modify: `DockHost.qml`
- Modify: `shell.qml`
- Modify: `config/dock.json`
- Test: `tests/tst_dockmodel.qml`

**Required interfaces and behavior:**
- `DockModel.normalizeApplicationIds(value)` returns `[]` for non-arrays; trims IDs; drops blanks; deduplicates case-insensitively while preserving the first canonical spelling and insertion order.
- `DockModel.addHiddenApplication(ids, desktopId)` and `DockModel.removeHiddenApplication(ids, desktopId)` return normalized new arrays without mutating their inputs.
- `DockModel.normalizeSetting("hiddenApplications", value)` delegates to `normalizeApplicationIds`.
- Extend `DockModel.buildVisibleItems` by appending an optional final `hiddenApplicationIds` argument, preserving all existing call signatures. Build/group/sort normally, then exclude every item whose normalized `desktopId` is hidden.
- Add `hiddenApplications: []` to shipped configuration and runtime fallback settings. During `DockHost.loadSettings`, normalize a present value and synthesize `[]` when absent.
- In `Dock.qml`, normalize the setting and pass it to `buildVisibleItems` as the final argument.
- Do not add `hiddenApplications` to `resetSettingsPatch`; reset must leave it untouched.

**Test cases:**
- Normalization handles missing, malformed, blank, duplicate, mixed-case, and whitespace-padded IDs with literal expected arrays.
- Adding and removing IDs is case-insensitive, preserves canonical spelling, and does not mutate the input.
- A hidden pinned app is absent while the original pinned order remains unchanged and restoration returns it to that position.
- A hidden unpinned app with multiple grouped windows is absent.
- Unrelated apps and existing workspace sorting remain unchanged.

### Task 2: Context-Menu Hide Workflow

**Files:**
- Modify: `components/DockContextMenu.qml`
- Modify: `components/DockItem.qml`
- Modify: `components/Dock.qml`
- Modify: `DockHost.qml`
- Test: add the smallest project-appropriate focused wiring check under `tests/`; validate behavior rather than exact formatting.

**Required interfaces and behavior:**
- Add an application-level `hideFromDock()` signal to `DockContextMenu`.
- Show a `Hide from Dock` action for every non-control application item, whether pinned or unpinned. Keep `Remove from Dock` as a separate pinned-only action.
- Triggering the action dismisses the menu and emits the signal; it does not select or act on an individual window.
- Forward the canonical `desktopId` through `DockItem.hideRequested(string desktopId)` and `Dock.hideRequested(string desktopId)`.
- `DockHost.hideApplication(desktopId)` persists `DockModel.addHiddenApplication(settings.hiddenApplications, desktopId)` and is connected to each Dock instance.
- The icon disappears immediately through live settings propagation; no window-management request is dispatched.

### Task 3: Hidden Applications Management UI and Documentation

**Files:**
- Modify: `components/DockSettings.qml`
- Create if useful for focus and reuse: `components/DockHiddenApplicationRow.qml`
- Modify: `README.md`
- Test: extend model/UI checks with restoration and empty-state behavior where the existing harness can exercise real behavior.

**Required interfaces and behavior:**
- Add a full-width `Hidden Applications` section near other behavior/application controls in Dock Settings.
- Always render the section. When empty, display `No hidden applications` and omit the bulk action.
- For each hidden ID, display its desktop-entry icon and human name; fall back to the standard executable icon and the stored ID when no desktop entry exists.
- Each row has a `Show` control that commits `DockModel.removeHiddenApplication(current hidden list, id)` through the existing settings-patch path.
- When at least one ID is hidden, show `Show All`; it commits `{ hiddenApplications: [] }`.
- Preserve pinned membership and order when restoring.
- Document `hiddenApplications`, context-menu hiding, restoration, persistence, and reset behavior in README.

### Task 4: Integration Verification

**Owner:** Primary agent after task-level Luna reviews.

**Required verification:**
- Inspect the complete branch diff against its starting commit.
- Run the Qt model test suite and all repository shell checks.
- Run `timeout 6s ./scripts/run --no-color` and distinguish the documented duplicate-application-ID warning from failures.
- Run `bash -n install.sh uninstall.sh scripts/smartdock scripts/run`.
- Run `omarchy plugin validate .`.
- Run `/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml components/DockContextMenu.qml components/DockSettings.qml shell.qml` plus any new QML component.
- Run `git diff --check`.
- Perform a final whole-branch code review, address Critical/Important findings through one Luna fix wave, and re-review the fix diff once.
- Keep all commits local; do not push or deploy.
