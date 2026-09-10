import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const rootPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(rootPath, name), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
const defaults = JSON.parse(read('config/dock.json'));
const metadata = JSON.parse(read('config/settings-schema.json'));

function loadModel(name) {
  const source = read('components/' + name);
  const context = vm.createContext({ console });
  for (const match of source.matchAll(/^\.import "([^"]+)" as (\w+)$/gm))
    context[match[2]] = loadModel(match[1]);
  vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ''), context, { filename: name });
  return context;
}

// Execute the actual host/controller functions. Only Quickshell services are
// substituted; this is not a second config/read implementation or a QML loader.
function functions(name, state) {
  const context = vm.createContext(state);
  context.root = context;
  const blocks = read(name).match(/^  function [\s\S]*?^  }/gm);
  assert.ok(blocks?.length, name);
  vm.runInContext(blocks.join('\n'), context, { filename: name });
  return context;
}

const shared = {
  console: { warn() {} },
  DockModel: loadModel('DockModel.js'),
  DockWindowModel: loadModel('DockWindowModel.js'),
  TrashModel: loadModel('DockTrashModel.js'),
};
let deferred = 0;
const host = functions('DockHost.qml', {
  ...shared, dockControl: { defaults }, Qt: { callLater() { deferred++; } },
  runtimeMode: 'plugin', configPath: '/actual host/dock.json',
  settings: plain(defaults), settingsRevision: 0, settingsLoaded: false,
  settingsLoadState: 'missing', settingsLoadError: '', settingsReloadPending: false,
  settingsWriteState: 'idle', settingsWriteError: '', settingsPersisted: false,
  settingsDefaultsInUse: true, showTrashSetting: true, showTrash: true,
  settingsLoadedText: '',
});
const control = functions('components/DockControl.qml', {
  ...shared, host, defaults, metadata, Quickshell: { processId: 123 },
});
function request(command, arguments_ = {}) {
  return plain(control.handle(JSON.stringify({ apiVersion: 1, command, arguments: arguments_ })));
}

assert.deepEqual(Object.keys(metadata.settings).sort(), Object.keys(defaults).sort());
const initial = request('status');
assert.equal(initial.ok, true);
assert.equal(initial.data.runtime.instanceId, '123');
assert.equal(initial.data.runtime.mode, 'plugin');
assert.equal(initial.data.configPath, '/actual host/dock.json');
assert.equal(initial.data.loadState, 'missing');
assert.equal(initial.data.persisted, false);
assert.equal(initial.data.defaultsInUse, true);

const persisted = { ...defaults, hoverGlowOpacity: .72, clickAction: 'launch',
  pinned: ['code', 'Unavailable.App'], extensionData: { keep: ['unchanged'] } };
host.loadSettings(JSON.stringify(persisted));
assert.deepEqual(plain(host.settings), persisted);
assert.equal(host.settingsRevision, 1);
assert.equal(host.settingsPersisted, true);
assert.equal(host.settingsDefaultsInUse, false);
assert.equal(deferred, 1);
host.loadSettings(JSON.stringify(persisted));
assert.equal(host.settingsRevision, 1, 'Identical reload is not a new revision');

const keyed = request('config.get', { key: 'hoverGlowOpacity' });
assert.deepEqual(keyed.data.settings, { hoverGlowOpacity: .72 });
const effective = request('config.get', { effective: true });
assert.equal(effective.data.settings.hoverGlowOpacity, .70);
assert.equal(effective.data.settings.clickAction, 'focus-or-launch');
assert.equal(effective.data.settings.borderWidth, null);
assert.equal(effective.data.settings.backgroundColor, null);
assert.ok(effective.warnings.length);
assert.equal(host.settings.clickAction, 'launch', 'Reads must not normalize requested state in place');

const proposal = { ...defaults, autoHide: true, reserveSpace: true,
  position: 'left', workspaceLayout: 'grouped', workspaceMonitorScope: 'current-monitor',
  backgroundColorEnabled: true, backgroundColor: '@accent' };
const projection = plain(control.effectiveSettings(proposal));
assert.equal(projection.reserveSpace, false);
assert.equal(projection.workspaceLayout, 'flat');
assert.equal(projection.workspaceMonitorScope, 'all');
assert.equal(projection.backgroundColor, null);
assert.equal(proposal.workspaceLayout, 'grouped');
assert.equal(proposal.reserveSpace, true);
proposal.backgroundColor = '#80112233';
assert.equal(control.effectiveSettings(proposal).backgroundColor, '#80112233');
proposal.position = 'bottom';
assert.equal(control.effectiveSettings(proposal).workspaceLayout, 'grouped');
assert.equal(control.effectiveSettings(proposal).workspaceMonitorScope, 'current-monitor');

const schema = request('config.schema');
assert.equal(schema.data.source, 'runtime');
for (const key of Object.keys(defaults))
  assert.deepEqual(schema.data.settings[key].default, defaults[key], key);
assert.deepEqual(Object.keys(request('config.schema', { key: 'iconSize' }).data.settings), ['iconSize']);
assert.equal(request('config.schema', { key: '__proto__' }).error.code, 'E_VALIDATION');
assert.equal(request('config.get', { key: 'notAKey' }).error.code, 'E_VALIDATION');
assert.equal(request('config.get', { effective: 'true' }).error.code, 'E_USAGE');
assert.equal(request('status', { key: 'iconSize' }).error.code, 'E_USAGE');
assert.equal(control.handle('[]').error.code, 'E_PROTOCOL');
assert.equal(control.handle('{bad').error.code, 'E_USAGE');

for (const invalid of ['{broken', 'null', '[]', '{"pinned":false}']) {
  host.loadSettings(invalid);
  assert.equal(host.settingsLoadState, 'invalid');
  assert.equal(host.settingsPersisted, false);
  assert.deepEqual(plain(host.settings), persisted);
  assert.ok(host.settingsLoadError);
  assert.ok(request('config.get').warnings.some(value => value.includes('last-good')));
}
host.loadSettings(JSON.stringify(persisted));
assert.equal(host.settingsLoadState, 'loaded');
assert.equal(host.settingsLoadError, '');
assert.equal(host.settingsPersisted, true);

const source = read('DockHost.qml');
assert.equal((source.match(/\bDockControl\s*\{/g) || []).length, 1);
assert.ok(source.indexOf('DockControl {') < source.indexOf('Variants {'));
assert.match(source, /property var settings: dockControl\.defaults/);
assert.match(read('components/DockControl.qml'), /function request\(payload: string\): string/);
assert.match(read('Overlay.qml'), /runtimeMode: "plugin"/);
assert.match(read('shell.qml'), /runtimeMode: "standalone"/);
console.log('CLI host reads, metadata, last-good state and effective projections: PASS');
