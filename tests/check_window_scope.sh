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
  [[ "$actual" == "$expected" ]] || fail "expected $expected occurrence(s) of '$pattern', found $actual"
}

assert_contains config/dock.json '"windowScope": "all"' 'default windowScope must be all'
assert_contains config/dock.json '"showUrgentOutsideScope": true' 'urgent-outside-scope must default true'
assert_contains components/DockSettings.qml 'label: "Window scope"' 'Dock Settings must expose window scope'
assert_contains components/DockSettings.qml 'label: "Show urgent outside scope"' 'Dock Settings must expose urgent exception toggle'
assert_contains components/DockSettings.qml 'enabled: root.current("windowScope") !== "all"' 'urgent exception must explainably disable for all scope'
assert_contains components/Dock.qml 'Hyprland.monitorFor(screen)' 'each Dock must resolve its Hyprland monitor from PanelWindow.screen'
assert_contains components/Dock.qml 'filteredToplevels' 'Dock must filter individual windows before composing visible items'
assert_contains DockHost.qml 'scopeRevision' 'DockHost must own shared scope revision state'
assert_contains DockHost.qml 'scopeRefreshTimer' 'DockHost must own the debounced scope refresh timer'
assert_contains DockHost.qml 'scopeRevision: root.scopeRevision' 'DockHost must pass one shared scope revision to each Dock'
assert_contains components/DockWindowActions.qml 'minimizedOriginsSnapshot' 'host-owned controller must expose a read-only origin snapshot'
assert_contains components/DockWindowActions.qml 'DockWindowModel.pruneOriginSnapshot' 'stale minimized origins must use the pure pruning path'

assert_count 1 'DockWindowActions {' DockHost.qml components/*.qml
assert_count 1 'id: scopeRefreshTimer' DockHost.qml components/*.qml
assert_count 1 'Hyprland.refreshMonitors()' DockHost.qml components/Dock.qml
assert_count 1 'Hyprland.refreshWorkspaces()' DockHost.qml components/Dock.qml
assert_count 1 'Hyprland.refreshToplevels()' DockHost.qml components/Dock.qml

if grep -Fq 'id: scopeRefreshTimer' components/Dock.qml; then
  fail 'scope refresh timer must not be duplicated per monitor'
fi
if grep -Fq 'Hyprland.refresh' components/Dock.qml; then
  fail 'Dock must consume the host scope revision instead of refreshing Hyprland per monitor'
fi
if grep -Fq 'hyprctl' components/DockWindowModel.js; then
  fail 'scope model must not poll hyprctl'
fi

printf 'window-scope structural checks passed\n'
