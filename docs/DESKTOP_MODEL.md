# Shared desktop construction — SB-01 / FDM-963

`components/DockDesktopModel.js` extracts the classic construction path from
`Dock.qml` without introducing a sidebar, configuration migration or service.
The SB-02 sidebar extension is documented in `SIDEBAR.md`; the classic extraction
contract below remains unchanged. The extraction baseline is `1a81fe650f686f1b8dfb10b25f5c0d1de6a4bab8`.

## Snapshot interface

```js
DesktopModel.build({
  mode: "classic-grouped", // or "classic-flat"; no sidebar mode in SB-01
  settings: {
    pinned, hiddenApplications, workspaceGroups,
    workspaceMonitorScope, workspaceMonitorOrder, sortByWorkspace
  },
  applications, toplevels, hyprToplevels, hyprWorkspaces, hyprMonitors,
  minimizedOrigins, focusedWorkspace, dockMonitor, filteredToplevels
}) // -> { records, visibleItems, workspacePresentation }
```

The caller supplies normalized settings and array snapshots. `minimizedOrigins`
is the host-owned snapshot (or an empty object); `focusedWorkspace` is the
canonical focused workspace identity, and `dockMonitor` is the resolved native
monitor or null. `filteredToplevels` is the existing classic window-scope result,
including its urgent-exception policy. No caller setting is written by the builder. Sidebar mode copies its presentation
settings to enforce all-monitor scope and inactive classic grouping; classic mode
retains the normalization boundary below. Unsupported modes throw rather than silently selecting a renderer.

- `records` retains actual toplevel object identities and native location data.
  Grouped mode uses the complete inventory; flat mode uses the filtered inventory.
- In classic modes, `visibleItems` is **always** the classic filtered flat presentation, even in
  grouped mode. It retains saved local grouping and optional workspace sorting.
- `workspacePresentation` is the unprojected native grouped presentation in
  grouped mode, or **null** in flat mode. Null means the classic caller leaves its
  inactive workspace snapshot alone; it is not an instruction to clear it.

Native `monitorGroups`, `groups`, `primaryWorkspaceIdentity`, `globalLaunchers`,
`fallbackItems` and `renderedItems` are preserved. Visual monitor ordering uses
`monitorGroups`/`groups`; `renderedItems` remains primary-workspace-first
badge/preview traversal, not a visual list. Closed pins and fallback windows
must not disappear in a downstream projection. Saved local application/workspace
pairs stay opt-in; the legacy `groupWindows` setting remains inactive.

`Dock.qml` still decides `groupedRequested` (horizontal + grouped layout), freezes
construction during workspace drag, coalesces refreshes, registers badge scopes,
compares snapshots, dismisses previews only on replacement, and schedules reveal.
The order of those observable side effects is unchanged. Animated reconciliation
in `DockPresentationModel.js/.qml` and all host action/config/provider ownership
are untouched. The builder does not create watchers, timers, providers or caches.

## Characterization and tests

`tests/fixtures/desktop-classic-refresh.js` is the verbatim production refresh
function from the baseline, not a second hand-written model. The Node test runs
it and the current production method against the **real imported JS helpers**.
Synthetic data supplies desktop snapshots; recorded badge/preview calls are
lifecycle observations, not evidence of a running compositor.

`desktop-classic-baseline.json` binds the oracle source and all 264 baseline
case outputs to SHA-256 hashes. It was captured before extraction. The capture
command refuses a modified production refresh, so it cannot bless the new
implementation as its own oracle. Keep this baseline immutable during SB-01.

The matrix covers all four edges, flat/grouped, all/current-monitor workspace
scope, all four window scopes, sorted/unsorted and saved/individual groups.
Additional cases retain two active monitors, physical/explicit order, focus-only
changes, empty/named workspaces, conflicting/unknown owners, sticky/minimized
origins, missing origins, hidden applications, closed pins, pending addresses,
duplicate application IDs across workspaces and inactive legacy preferences.
Tests also compare exact member identity, non-mutation, no-op equality, drag
read barriers, scheduling and mode/destruction badge cleanup.

```bash
node tests/test_desktop_model.mjs
node tests/test_workspace_model.mjs
node tests/test_workspace_groups.mjs
node tests/test_workspace_monitor_order.mjs
node tests/test_workspace_monitor_sections.mjs
node tests/test_presentation_model.mjs
node tests/test_badge_model.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components -import tests/qml-imports
```

`tests/tst_desktopmodel.qml` additionally imports the actual `.pragma`/`.import`
helper graph under Qt, including grouped/flat and unsupported-mode cases. The
complete existing Headless CI glob discovers both new test suites.

## Real-component qualification (SB-06)

`tests/runtime/desktop-model.qml` creates the real `Dock`, `DockWindowActions`,
`DockWorkspaceMonitorDrag` and `DockBadgeTracker`. It does **not** override
`refreshVisibleItems` or substitute a fake Dock. It checks builder parity against
live snapshots, both layouts, all edges, no-op snapshot identity, actual drag
registration and teardown, and real badge-scope cleanup. The panel stays hidden;
this fixture does not assert pixel appearance or physical interaction behavior.

In the isolated guest described in `docs/DEV_SESSIONS.md`:

```bash
SMARTDOCK_ISOLATED_RUNTIME=1 bash tests/runtime/check-desktop-model.sh
```

This fixture requires a real Quickshell/Omarchy Wayland session. A Node or pure Qt
pass is not a runtime pass. SB-06 / FDM-968 owns unexecuted fixture validation,
standalone smoke, plugin validation, shell-aware lint, live rendering, drag/input,
preview behavior, monitor/hotplug and reload checks. Follow its sanitized-evidence
and disposable-session cleanup requirements. Do not run beside the production
dock, switch installed sources, or deploy as part of this source slice.

## SB-02 handoff

FDM-964 may stack on the accepted exact SB-01 head without an installation or
production merge. Extend this interface for the sidebar's all-monitor scope and
no classic saved grouping; add its projection as `DockSidebarModel.js`, not by
repurposing animated reconciliation. Keep one existing host/action/writer/provider
path. Record the child PR's exact parent base and rerun evidence after any
retarget/rebase, as required by `docs/DELIVERY.md`.

## SB-02 extension

`mode: "sidebar"` now requests all windows on all monitors, regardless of classic
`filteredToplevels`, `workspaceGroups` or sorting preferences. The input is not
mutated. `records` is complete inventory; `visibleItems` is all-window flat data;
`workspacePresentation` retains the native grouped shape. The sidebar projection
adds stable handle identities and structural application grouping. See `SIDEBAR.md`.
The unknown-app-ID pin-matching guard is sidebar-only; classic characterization
remains the original immutable oracle.
