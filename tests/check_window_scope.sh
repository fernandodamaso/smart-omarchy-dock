#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'window-scope structural check failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Fq -- "$pattern" "$file" || fail "$label"
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  shift 2
  local actual
  actual=$(grep -Fh -- "$pattern" "$@" | wc -l | tr -d ' ')
  [[ "$actual" == "$expected" ]] \
    || fail "expected $expected occurrence(s) of '$pattern', found $actual"
}

assert_contains config/dock.json '"windowScope": "all"' \
  'default windowScope must be all'
assert_contains config/dock.json '"showUrgentOutsideScope": true' \
  'urgent-outside-scope must default true'
assert_contains README.md '### Window scope filtering' \
  'README must document window scope behavior'
assert_contains config/settings-schema.json '"windowScope"' \
  'CLI schema must expose window scope'
assert_contains config/settings-schema.json '"showUrgentOutsideScope"' \
  'CLI schema must expose the urgent exception'

assert_contains DockHost.qml \
  'property int scopeRevision: scopeRefreshController.revision' \
  'DockHost must expose the shared controller revision'
assert_contains DockHost.qml 'id: scopeRefreshController' \
  'DockHost must own the shared scope refresh controller'
assert_contains DockHost.qml 'scopeRevision: root.scopeRevision' \
  'DockHost must pass one shared scope revision to each Dock'
assert_contains DockHost.qml 'DockWindowModel.shouldRefreshWindowScope' \
  'DockHost must route relevant Hyprland events to scope refresh'
assert_contains components/DockScopeRefreshController.qml 'interval: 80' \
  'scope controller must debounce refresh requests'
assert_contains components/DockScopeRefreshController.qml 'onTriggered: root.refresh()' \
  'scope controller must own refresh execution'
assert_contains components/DockScopeRefreshController.qml \
  'function onWorkspaceChanged()' \
  'scope controller must observe per-toplevel workspace changes'
assert_contains components/DockScopeRefreshController.qml \
  'function onWaylandHandleChanged()' \
  'scope controller must observe late Wayland mappings'

assert_contains components/Dock.qml 'import "DockWindowModel.js" as DockWindowModel' \
  'Dock must import the pure scope model'
assert_contains components/Dock.qml 'required property int scopeRevision' \
  'Dock must consume the shared host scope revision'
assert_contains components/Dock.qml 'Hyprland.monitorFor(screen)' \
  'each Dock must resolve its Hyprland monitor from PanelWindow.screen'
assert_contains components/Dock.qml 'readonly property var filteredToplevels' \
  'Dock must build a filtered per-window set'
assert_contains components/Dock.qml \
  'DockWindowModel.filterToplevelsByScope(' \
  'Dock must use the pure scope filter'
assert_contains components/Dock.qml \
  'pinned, filteredToplevels, applications' \
  'visible-item composition must consume filtered windows'
assert_contains components/Dock.qml 'property var visibleItems: []' \
  'PR #18 imperative visible-item snapshot must remain intact'
assert_contains components/Dock.qml 'function refreshVisibleItems()' \
  'PR #18 visible-item refresh helper must remain intact'
assert_contains components/Dock.qml \
  'pinned, filteredToplevels, applications, hyprToplevels' \
  'deferred visible-item refresh must use filtered windows'

scope_handler="$(sed -n '/onScopeRevisionChanged:/,/^  }/p' components/Dock.qml)"
grep -Fxq '    if (windowPreview) windowPreview.dismissImmediately()' <<<"$scope_handler" \
  || fail 'scope change must guard the preview QML ID during initialization'
grep -Fxq '    root.scheduleVisibleItemsRefresh()' <<<"$scope_handler" \
  || fail 'scope revisions must unconditionally schedule the deferred visible-item snapshot'

assert_contains components/DockWindowActions.qml 'minimizedOriginsSnapshot' \
  'host-owned controller must expose its origin snapshot'
assert_contains components/DockWindowActions.qml \
  'DockWindowModel.pruneOriginSnapshot' \
  'stale minimized origins must use the pure pruning path'

assert_count 1 'DockWindowActions {' DockHost.qml components/*.qml
assert_count 1 'DockScopeRefreshController {' DockHost.qml
if grep -Fq 'Hyprland.refresh' DockHost.qml components/Dock.qml; then
  fail 'refresh calls must stay behind the shared scope controller'
fi

if grep -Fq 'id: scopeRefreshTimer' components/Dock.qml; then
  fail 'scope refresh timer must not be duplicated per monitor'
fi
if grep -Fq 'Hyprland.refresh' components/Dock.qml; then
  fail 'Dock must consume host refresh state instead of refreshing Hyprland per monitor'
fi
if grep -Fq 'hyprctl' components/DockWindowModel.js; then
  fail 'scope model must not poll hyprctl'
fi

printf 'window-scope structural checks passed\n'
