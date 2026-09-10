import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const base = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(base, name), 'utf8');
const removed = ['DockSettings', 'DockSettingSlider', 'DockSettingsSection',
  'DockSettingsToggleRow', 'DockColorTokenDropdown', 'DockColorSwatch',
  'DockActionDropdown', 'DockHiddenApplicationRow'];
const obsolete = /DockSettings|dockSettings|settingPreviews|SettingsRequested|settingsRequested|smartdock-settings|openIconEditor|DockSettingSlider|DockColorTokenDropdown|DockColorSwatch|DockActionDropdown|DockHiddenApplicationRow/;
function files(directory) {
  return fs.readdirSync(path.join(base, directory), { withFileTypes: true }).flatMap(entry => {
    const name = path.posix.join(directory, entry.name);
    return entry.isDirectory() ? files(name) : [name];
  });
}
// Audit executable sources, including mixed tests and runtime fixtures. This
// guard excludes itself (it must name removed components) and historical docs.
const active = ['DockHost.qml', 'shell.qml', 'Overlay.qml', ...files('components'),
  ...files('scripts'), ...files('tests')].filter(name =>
  /\.(qml|js|mjs|py|sh)$/.test(name) && !name.endsWith('/test_settings_cutover.mjs'));
const references = active.flatMap(name => read(name).split('\n').flatMap((line, index) =>
  obsolete.test(line) ? [`${name}:${index + 1}: ${line.trim()}`] : []));
if (references.length) console.log('Settings cutover reference audit:\n' + references.join('\n'));
assert.deepEqual(references, [], 'No active Settings routes, dependencies, or removed-component imports remain');
for (const name of removed)
  assert.equal(fs.existsSync(path.join(base, 'components', name + '.qml')), false, name);
assert.equal(fs.existsSync(path.join(base, 'tests/run_action_dropdown_settings.sh')), false);

const dock = read('components/Dock.qml');
const host = read('DockHost.qml');
const menu = read('components/DockContextMenu.qml');
const controlItem = read('components/DockControlItem.qml');
assert.doesNotMatch(dock, /previewSetting|clearSettingPreview|signal settingChanged|signal settingsPatchRequested|signal resetSettingsRequested/);
assert.doesNotMatch(host, /onSettingChanged|onSettingsPatchRequested|onResetSettingsRequested|function resetSettings\(/);
assert.match(dock, /onSettingsChanged: root\.scheduleVisibleItemsRefresh\(\)/);
assert.match(dock, /onApplicationSelected: desktopId => root\.pinRequested\(desktopId\)/);
for (const component of ['DockWindowPreview', 'DockAppPicker', 'DockTrashItem', 'DockWorkspaceStrip'])
  assert.match(dock, new RegExp('\\b' + component + '\\s*\\{'));
for (const token of ['"accent": Color.accent', '"menu.background": Color.menu.background',
  '"menu.border": Color.menu.border']) assert.ok(dock.includes(token), token);
for (const action of ['launcher', 'add', 'auto-hide'])
  assert.ok(menu.includes('"' + action + '"'), action);
assert.match(controlItem, /onAddApplicationRequested:/);
assert.match(controlItem, /onAutoHideToggled:/);
assert.match(host, /onAutoHideRequested: enabled => root\.saveSetting\("autoHide", enabled\)/);
assert.equal((host.match(/configFile\.setText\(/g) || []).length, 1, 'Keep the single host writer');

// Execute the actual auto-hide expression and method without a Settings object.
// This is a model/signal-routing check, not real compositor scheduling evidence.
const expression = dock.match(/readonly property bool keepAutoHideOpen: ([\s\S]*?)(?=\n  readonly property)/)?.[1];
const update = dock.match(/^  function updateAutoHideState\(\) \{[\s\S]*?^  }/m)?.[0];
assert.ok(expression && update);
let stops = 0, restarts = 0;
const scope = vm.createContext({
  windowPointer: { hovered: false }, appPicker: { visible: false },
  windowPreview: { interactionActive: false }, openMenuCount: 0, dragSource: -1,
  autoHide: true, autoHideRevealed: false,
  hideTimer: { stop() { stops++; }, restart() { restarts++; } },
});
scope.root = scope;
Object.defineProperty(scope, 'keepAutoHideOpen', { get: () => vm.runInContext('(' + expression + ')', scope) });
vm.runInContext(update, scope);
assert.equal(scope.keepAutoHideOpen, false);
for (const [object, key, value] of [[scope.windowPointer, 'hovered', true],
  [scope.appPicker, 'visible', true], [scope.windowPreview, 'interactionActive', true],
  [scope, 'openMenuCount', 1], [scope, 'dragSource', 0]]) {
  const old = object[key];
  object[key] = value;
  scope.updateAutoHideState();
  assert.equal(scope.keepAutoHideOpen, true, key);
  assert.equal(scope.autoHideRevealed, true, key);
  object[key] = old;
  scope.updateAutoHideState();
  assert.equal(scope.keepAutoHideOpen, false, key);
}
assert.equal(stops, 5);
assert.equal(restarts, 5);
scope.autoHide = false;
scope.updateAutoHideState();
assert.equal(scope.autoHideRevealed, false);
assert.equal(stops, 6);

const schema = JSON.parse(read('config/settings-schema.json'));
for (const command of ['config.apply', 'config.reset', 'apps.show', 'apps.move', 'icons.set', 'icons.reload'])
  assert.ok(schema.commands.includes(command), command);
console.log('Settings cutover, live theme bindings, retained actions and auto-hide behavior: PASS');
