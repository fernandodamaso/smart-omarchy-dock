import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const rootPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(rootPath, name), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
const defaults = JSON.parse(read('config/dock.json'));
const schema = JSON.parse(read('config/settings-schema.json'));
function loadModel(name) {
  const source = read('components/' + name);
  const context = vm.createContext({ console });
  for (const match of source.matchAll(/^\.import "([^"]+)" as (\w+)$/gm))
    context[match[2]] = loadModel(match[1]);
  vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ''), context, { filename: name });
  return context;
}
function freeze(value) {
  if (value && typeof value === 'object') {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}
const model = loadModel('DockConfigModel.js');
const current = freeze({ ...defaults, pinned: ['code', 'Unavailable.App'],
  hiddenApplications: ['Unavailable.App'], margin: -7, clickAction: 'launch',
  extensionData: { keep: [1, 'unchanged'] } });
const changed = model.applyPatch(current, freeze({ showTrash: false }), schema);
assert.equal(changed.ok, true);
assert.equal(changed.settings.showTrash, false);
assert.equal(current.showTrash, true);
assert.deepEqual(plain(changed.settings.pinned), ['code', 'Unavailable.App']);
assert.deepEqual(plain(changed.settings.extensionData), { keep: [1, 'unchanged'] });
assert.equal(changed.settings.clickAction, 'launch');
assert.equal(changed.settings.margin, -7, 'Untouched legacy values must survive');
assert.deepEqual(plain(changed.changedKeys), ['showTrash']);
assert.deepEqual(plain(model.applyPatch(current, {}, schema).changedKeys), []);

for (const patch of [null, [], false, { madeUpPreference: 1 },
  { iconSize: 48, autoHide: 'false' }, { iconSize: 23 }, { iconSize: 96.1 },
  { iconSize: null }, { magnification: Infinity }, { magnification: NaN },
  { margin: -1 }, { margin: 1.2 }, { clickAction: 'launch' },
  { position: 'diagonal' }, { controlCommand: '  ' },
  { backgroundColor: 'red' }, { backgroundColor: '#123' },
  { backgroundColor: 'https://example.test/x.png' },
  { pinned: ['code', 'CODE.desktop'] }, { hiddenApplications: ['unknown-application'] },
  { pinned: ['__proto__'] }, { pinned: ['a/b'] }, { pinned: [42] },
  JSON.parse('{"__proto__":{"polluted":true}}'),
  JSON.parse('{"constructor":{"prototype":{"polluted":true}}}')]) {
  const before = JSON.stringify(current);
  const result = model.applyPatch(current, patch, schema);
  assert.equal(result.ok, false, JSON.stringify(patch));
  assert.ok(result.errors.length);
  assert.deepEqual(plain(result.changedKeys), []);
  assert.equal(JSON.stringify(current), before);
}
assert.equal({}.polluted, undefined);
for (const patch of [{ hoverGlowOpacity: .72 }, { margin: 1000000 },
  { backgroundColor: '#80112233', backgroundColorEnabled: true },
  { backgroundColor: '@menu.background' }, { backgroundColor: '' },
  { pinned: ['Code.desktop', 'Unavailable App'] },
  { controlCommand: 'literal $(not-executed); command' }])
  assert.equal(model.validatePatch(patch, schema).ok, true, JSON.stringify(patch));

const preferences = model.preferenceResetPatch(defaults, schema);
for (const key of ['pinned', 'hiddenApplications', 'margin', 'iconOverrides', 'extensionData'])
  assert.equal(Object.hasOwn(preferences, key), false, key);
const reset = model.applyPatch(current, preferences, schema);
assert.equal(reset.ok, true);
assert.equal(reset.settings.clickAction, defaults.clickAction);
assert.equal(reset.settings.controlCommand, defaults.controlCommand);
assert.equal(reset.settings.margin, -7);
assert.deepEqual(plain(reset.settings.pinned), plain(current.pinned));
assert.deepEqual(plain(reset.settings.extensionData), plain(current.extensionData));
const unsafeExisting = JSON.parse('{"__proto__":{"keep":true},"iconSize":42}');
const preserved = model.applyPatch(unsafeExisting, { iconSize: 48 }, schema);
assert.equal(preserved.ok, true);
assert.deepEqual(plain(preserved.settings).__proto__, { keep: true });
assert.equal({}.keep, undefined);

// Exercise actual host/controller functions; only the unavailable FileView and
// Quickshell services are substituted. No duplicate mutation/writer algorithm.
function functions(name, state) {
  const context = vm.createContext(state);
  context.root = context;
  const blocks = read(name).match(/^  function [\s\S]*?^  }/gm);
  assert.ok(blocks?.length, name);
  vm.runInContext(blocks.join('\n'), context, { filename: name });
  return context;
}
const shared = { console: { warn() {} }, ConfigModel: model,
  DockModel: loadModel('DockModel.js'), DockWindowModel: loadModel('DockWindowModel.js'),
  TrashModel: loadModel('DockTrashModel.js') };
let disk = null, cached = '', writes = 0, failWrite = false, deferWrite = false;
let host;
const fileView = {
  get cachedText() { return cached; },
  setText(text) {
    writes++;
    cached = text;
    if (deferWrite) return;
    if (failWrite) host.settingsSaveFailed(3);
    else { disk = text; host.settingsSaved(); }
  },
  reload() {
    if (disk === null) host.settingsLoadFailed(2);
    else host.settingsFileLoaded(disk);
  },
};
host = functions('DockHost.qml', { ...shared, configFile: fileView,
  Qt: { callLater() {} }, FileViewError: { FileNotFound: 2, toString: value => 'File error ' + value },
  runtimeMode: 'plugin', configPath: '/missing parent/dock.json',
  settings: plain(defaults), settingsLoaded: false, settingsRevision: 0,
  settingsLoadState: 'missing', settingsLoadError: '', settingsReloadPending: false,
  settingsWriteState: 'idle', settingsWriteError: '', settingsPersisted: false,
  settingsDefaultsInUse: true, showTrash: true, showTrashSetting: true,
  settingsLoadedText: '', settingsWriteBaseText: '', settingsWriteText: '',
});
const control = functions('components/DockControl.qml', {
  ...shared, host, defaults, metadata: schema, Quickshell: { processId: 123 },
});
host.dockControl = control;
function request(command, arguments_ = {}) {
  return plain(control.handle(JSON.stringify({ apiVersion: 1, command, arguments: arguments_ })));
}
const apply = (patch, dryRun = false) => request('config.apply', { patch, dryRun });
assert.equal(apply({ iconSize: 48 }).error.code, 'E_BUSY');
host.settingsLoadFailed(2);
assert.equal(writes, 0, 'Missing config/read must not ask FileView to create a parent');
assert.equal(request('status').data.persisted, false);
let result = apply({ iconSize: 48 });
assert.equal(result.ok, true);
assert.equal(result.data.applied, true);
assert.equal(result.data.persisted, true);
assert.equal(result.data.writeState, 'saved');
assert.equal(writes, 1);
assert.equal(JSON.parse(disk).iconSize, 48);

// Preservation and dry-run behavior against the actual writer boundary.
disk = JSON.stringify({ ...current, hoverGlowOpacity: .4 });
cached = disk;
host.settingsFileLoaded(disk);
const snapshot = JSON.stringify(host.settings);
const beforeDryWrites = writes;
result = apply({ hoverGlowOpacity: .72 }, true);
assert.equal(result.ok, true);
assert.equal(result.data.dryRun, true);
assert.equal(result.data.applied, false);
assert.equal(result.data.persisted, false);
assert.equal(result.data.requested.hoverGlowOpacity, .72);
assert.equal(result.data.effective.hoverGlowOpacity, .70);
assert.equal(result.data.diff.hoverGlowOpacity.from, .4);
assert.equal(result.data.diff.hoverGlowOpacity.to, .72);
assert.equal(JSON.stringify(host.settings), snapshot);
assert.equal(writes, beforeDryWrites);
result = apply({ iconSize: 64, autoHide: 'false' });
assert.equal(result.error.code, 'E_VALIDATION');
assert.equal(writes, beforeDryWrites);
assert.equal(JSON.stringify(host.settings), snapshot);

// Cooperating CLI and existing menu intents share the latest host state.
assert.equal(apply({ showTrash: false }).ok, true);
host.saveSetting('iconSize', 50);
assert.equal(host.settings.showTrash, false);
assert.equal(host.settings.iconSize, 50);
assert.deepEqual(plain(host.settings.pinned), plain(current.pinned));
assert.deepEqual(plain(host.settings.extensionData), plain(current.extensionData));
assert.equal(apply({ iconSize: 52 }).ok, true);
assert.equal(host.settings.iconSize, 52, 'Serialized same-key intents are last-writer-wins');
const noOpWrites = writes;
result = apply({ iconSize: 52 });
assert.equal(result.ok, true);
assert.equal(result.data.noop, true);
assert.deepEqual(result.data.changedKeys, []);
assert.equal(writes, noOpWrites);

host.settingsReloadPending = true;
assert.equal(apply({ showTrash: true }).error.code, 'E_BUSY');
assert.equal(request('status').data.persisted, false, 'Known reload makes disk/live parity unconfirmed');
host.settingsReloadPending = false;
failWrite = true;
const oldDisk = disk;
result = apply({ showTrash: true, magnification: 1.3 });
assert.equal(result.error.code, 'E_PERSISTENCE');
assert.equal(result.data.applied, true);
assert.equal(result.data.persisted, false);
assert.equal(host.settings.showTrash, true);
assert.equal(disk, oldDisk);
const errorRevision = host.settingsRevision;
const errorWrites = writes;
result = apply({ showTrash: true });
assert.equal(result.error.code, 'E_PERSISTENCE');
assert.equal(result.data.noop, true);
assert.equal(writes, errorWrites);

// Failed-write echoes must not discard the live delta or erase its error.
host.settingsReloadPending = true;
host.settingsFileLoaded(oldDisk);
assert.equal(host.settingsWriteState, 'error');
assert.equal(host.settings.showTrash, true);
assert.equal(host.settingsRevision, errorRevision);
result = request('config.retry');
assert.equal(result.error.code, 'E_PERSISTENCE');
assert.ok(cached.length <= JSON.stringify(host.settings, null, 2).length + 2);
failWrite = false;
result = request('config.retry');
assert.equal(result.ok, true);
assert.equal(result.data.persisted, true);
assert.equal(result.data.writeState, 'saved');
assert.equal(host.settingsRevision, errorRevision, 'Retry is not another setting revision');
assert.deepEqual(JSON.parse(disk), plain(host.settings));
assert.deepEqual(JSON.parse(disk).extensionData, plain(current.extensionData));

// A genuine external rollback after a successful save is NOT a failed echo.
host.settingsReloadPending = true;
disk = oldDisk;
host.settingsFileLoaded(disk);
assert.equal(host.settings.showTrash, false);
assert.equal(host.settingsPersisted, true);
const lastGood = JSON.stringify(host.settings);
disk = '{broken JSON';
host.settingsFileLoaded(disk);
assert.equal(host.settingsLoadState, 'invalid');
assert.equal(apply({ iconSize: 48 }).error.code, 'E_CONFIG_INVALID');
assert.equal(request('config.retry').error.code, 'E_CONFIG_INVALID');
assert.equal(JSON.stringify(host.settings), lastGood);
assert.equal(disk, '{broken JSON');
disk = lastGood;
host.settingsFileLoaded(disk);
assert.equal(request('config.reset', { preferences: true }).ok, true);
assert.equal(host.settings.margin, -7);
assert.deepEqual(plain(host.settings.pinned), plain(current.pinned));
assert.deepEqual(plain(host.settings.hiddenApplications), plain(current.hiddenApplications));
assert.deepEqual(plain(host.settings.extensionData), plain(current.extensionData));
assert.equal(request('config.reset', { key: 'margin' }).ok, true);
assert.equal(host.settings.margin, defaults.margin);
assert.equal(request('config.reset', { key: 'margin', preferences: true }).error.code, 'E_USAGE');
assert.equal(request('config.apply', { patch: {}, dryRun: 'true' }).error.code, 'E_USAGE');
assert.equal(request('config.get').data.source, 'requested');
assert.equal(request('config.get', { effective: true }).data.source, 'effective');

deferWrite = true;
result = apply({ iconSize: 60 });
assert.equal(result.ok, false, 'An unresolved save must never claim success');
assert.equal(result.error.code, 'E_BUSY');
assert.equal(result.data.applied, true);
assert.equal(result.data.persisted, false);
const pendingWrites = writes;
assert.equal(apply({ margin: 5 }).error.code, 'E_BUSY');
assert.equal(request('config.retry').error.code, 'E_BUSY');
assert.equal(writes, pendingWrites);

const hostSource = read('DockHost.qml');
assert.match(hostSource, /onSaved: root\.settingsSaved\(\)/);
assert.match(hostSource, /onSaveFailed: error => root\.settingsSaveFailed\(error\)/);
assert.match(hostSource, /onLoaded: root\.settingsFileLoaded\(text\(\)\)/);
assert.match(hostSource, /blockWrites: true/);
assert.match(hostSource, /atomicWrites: true/);
assert.equal((hostSource.match(/configFile\.setText\(/g) || []).length, 1);
console.log('Config validation, atomic latest-state patches and actual host writer lifecycle: PASS');
