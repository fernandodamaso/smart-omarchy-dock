# Task 2 Report: Context-Menu Hide Workflow

## Result

Implemented persistent application-level hiding from the context menu. The action is available for pinned and unpinned application items, dismisses the menu, emits the application-level signal, forwards the canonical `desktopId` through `DockItem` and `Dock`, and persists the hidden ID through `DockHost.hideApplication()` using `DockModel.addHiddenApplication(settings.hiddenApplications, desktopId)`. Settings assignment continues to drive the existing visible-item model, so the icon disappears immediately without dispatching a window-management request.

## Files changed

- `components/DockContextMenu.qml`: added `hideFromDock()` and a `Hide from Dock` action in both the no-window and running-window application menu layouts. The action is excluded for control items and is separate from the pinned-only `Remove from Dock` action.
- `components/DockItem.qml`: added `hideRequested(string desktopId)` and forwarded the context-menu signal with the item desktop ID.
- `components/Dock.qml`: added `hideRequested(string desktopId)` and forwarded each application item's request.
- `DockHost.qml`: added `hideApplication(desktopId)` and connected it to every `Dock` instance; persistence uses the normalized hidden-application helper and the existing live settings path.
- `tests/tst_dockmodel.qml`: added a focused settings-patch boundary test confirming hidden-ID persistence preserves pinned membership/order and does not mutate the source settings.

## TDD evidence

### RED

First added a real component-level Qt Quick Test that instantiated `DockContextMenu`, found the `Hide from Dock` action in its live object tree, triggered it, and asserted signal emission plus menu dismissal. Before production changes, the existing `qmltestrunner` failed while compiling the component:

```text
Type DockContextMenu unavailable
module "Quickshell" plugin "quickshell-coreplugin" not found
```

This is a test-runner limitation: Quickshell's core plugin is available to the `qs` runtime but is statically linked and not loadable by the standalone Qt test runner. The component-level test was removed rather than leaving the suite red or adding a source-grep test. The closest supported behavioral boundary was then added to the existing `DockModel` Qt test harness.

### GREEN

The focused model-boundary test passed as part of the full Qt suite:

```text
Totals: 43 passed, 0 failed, 0 skipped, 0 blacklisted
```

The actual QML wiring was additionally validated with:

- `timeout 6s ./scripts/run --no-color` — runtime loaded successfully; only the existing unresolved standalone `Commons`/`Ui` scanner warnings were emitted.
- `/usr/lib/qt6/bin/qmllint ...` including `DockContextMenu.qml` — exit 0; only existing incomplete Omarchy composite/type warnings.
- `bash -n install.sh uninstall.sh scripts/smartdock scripts/run` — passed.
- All `tests/check_*.sh` scripts — passed.
- `omarchy plugin validate .` — passed.
- `git diff --check` — passed.

## Self-review

- Hide handling does not call `Hyprland.dispatch()` or any window operation; it only updates application settings.
- The action is visible only when `controlItem` is false, while `Remove from Dock` remains pinned-only.
- Both menu layouts (no running windows and running windows) expose the same hide behavior.
- Signal forwarding carries `root.desktopId` unchanged from the visible item model.
- Persistence uses a new array from `DockModel.addHiddenApplication`; existing settings and pinned order remain intact.
- Assigning updated settings follows the existing binding to `Dock.visibleItems`, preserving immediate live removal.
- No installed plugin, user config, or remote repository was modified.

## Commit

Implementation commit: `651865af2deb00cad58eadafc621e9cafa6f87d5`

## Concerns

- A direct component-level signal test cannot run in the repository's `qmltestrunner` because Quickshell's statically linked core plugin is unavailable there. Runtime smoke and QML lint cover syntax/loading, while the supported Qt test covers the persistence boundary. A future harness that runs QML tests inside `qs` could add direct menu-signal coverage.
