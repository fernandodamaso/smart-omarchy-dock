import assert from 'node:assert/strict';
import { hostHarness, plain, read, loadModel } from './host_harness.mjs';

const h = hostHarness({ pinned: ['Code', 'Hidden.App', 'Missing.App', 'Other'],
  hiddenApplications: ['Hidden.App', 'Missing.App'], iconOverrides: {},
  extensionData: { keep: 1 } }, [
  { id: 'code', name: 'Editor', icon: 'code' }, { id: 'Hidden.App', name: 'Hidden' },
  { id: 'Other', name: 'Other app' }, { id: 'New.App', name: 'Ícone Editor' }]);
const { host, request, writes } = h;
let result = request('apps.list', { pinned: true });
assert.equal(result.ok, true, 'apps.list must be implemented by the selected host');
assert.deepEqual(result.data.applications, [
  { id: 'Code', name: 'Editor', available: true, pinned: true, hidden: false, pinnedIndex: 0 },
  { id: 'Hidden.App', name: 'Hidden', available: true, pinned: true, hidden: true, pinnedIndex: 1 },
  { id: 'Missing.App', name: 'Missing.App', available: false, pinned: true, hidden: true, pinnedIndex: 2 },
  { id: 'Other', name: 'Other app', available: true, pinned: true, hidden: false, pinnedIndex: 3 }]);
assert.deepEqual(request('apps.list', { hidden: true }).data.applications.map(a => a.id), ['Hidden.App', 'Missing.App']);
assert.deepEqual(request('apps.list', { query: 'ícone' }).data.applications.map(a => a.id), ['New.App']);
assert.equal(writes.length, 0, 'Discovery writes nothing');

const pins = plain(host.settings.pinned);
for (let i = 0; i < 2; i++) {
  result = request('apps.hide', { id: 'CODE.desktop' });
  assert.equal(result.ok, true);
  assert.deepEqual(plain(host.settings.pinned), pins);
}
assert.equal(writes.length, 1);
assert.deepEqual(plain(host.settings.hiddenApplications), ['Hidden.App', 'Missing.App', 'Code']);
assert.equal(request('apps.pin', { id: 'code.desktop' }).data.noop, true);
assert.equal(writes.length, 1, 'Pin neither duplicates nor unhides');
assert.equal(request('apps.list', { pinned: true }).data.applications[0].hidden, true);
for (let i = 0; i < 2; i++) assert.equal(request('apps.show', { id: 'code.desktop' }).ok, true);
assert.equal(writes.length, 2);
for (let i = 0; i < 2; i++) assert.equal(request('apps.unpin', { id: 'code.desktop' }).ok, true);
assert.equal(writes.length, 3);
assert.deepEqual(plain(host.settings.hiddenApplications), ['Hidden.App', 'Missing.App']);
assert.equal(request('apps.list', { query: 'code' }).data.applications[0].pinned, false);
assert.equal(request('apps.pin', { id: 'CODE.desktop' }).ok, true);
assert.equal(host.settings.pinned.at(-1), 'code', 'New pin uses exact catalog ID, not its display name');
assert.equal(request('apps.pin', { id: 'Offline.App.desktop' }).ok, true);
assert.equal(host.settings.pinned.at(-1), 'Offline.App');
assert.equal(request('apps.list', { pinned: true }).data.applications.at(-1).available, false);

host.settingsFileLoaded(JSON.stringify({ ...plain(host.settings), pinned: pins }));
result = request('apps.move', { id: 'Other.desktop', before: 'CODE' });
assert.equal(result.ok, true);
assert.deepEqual(plain(host.settings.pinned), ['Other', 'Code', 'Hidden.App', 'Missing.App']);
result = request('apps.move', { id: 'CODE.desktop', after: 'Missing.App' });
assert.equal(result.ok, true);
assert.deepEqual(plain(host.settings.pinned), ['Other', 'Hidden.App', 'Missing.App', 'Code']);
let count = writes.length;
assert.equal(request('apps.move', { id: 'Code', after: 'Missing.App' }).data.noop, true);
assert.equal(writes.length, count);
for (const args of [{ id: 'none', before: 'Code' }, { id: 'Code', after: 'none' },
  { id: 'Code', before: 'CODE.desktop' }, { id: 'Code', before: 'Other', after: 'Other' },
  { id: 'Code' }]) {
  const before = JSON.stringify(host.settings);
  assert.equal(request('apps.move', args).ok, false);
  assert.equal(JSON.stringify(host.settings), before);
  assert.equal(writes.length, count);
}
for (const id of ['', ' ', '__proto__', 'constructor', 'prototype', 'toString',
  'unknown-application', 'Unknown-Application.desktop', 'a/b', 'a\\b', 'a\n', 12, null]) {
  for (const action of ['pin', 'unpin', 'hide', 'show']) {
    assert.equal(request('apps.' + action, { id }).ok, false, action + ':' + id);
    assert.equal(writes.length, count);
  }
}
for (const args of [{ pinned: true, hidden: true }, { query: 'x', pinned: true },
  { query: 5 }, { pinned: 'true' }, { hidden: false }, { other: true }])
  assert.equal(request('apps.list', args).error.code, 'E_USAGE');
for (const args of [{}, { id: 'Code', all: true }, { all: false }])
  assert.equal(request('apps.show', args).error.code, 'E_USAGE');
assert.equal(request('apps.show', { all: true }).ok, true);
assert.deepEqual(plain(host.settings.hiddenApplications), []);
count = writes.length;
assert.equal(request('apps.show', { all: true }).data.noop, true);
assert.equal(writes.length, count);
assert.deepEqual(plain(host.settings.extensionData), { keep: 1 });

// Legacy/unknown requested values are not sanitized by unrelated one-app edits.
const icons = hostHarness({ pinned: ['code'], hiddenApplications: [],
  iconOverrides: { other: '/tmp/Ícone original.png', legacy: 'not-a-valid-source' },
  extensionData: { keep: 2 } });
const call = icons.request;
result = call('icons.set', { id: 'CODE.desktop', source: '/tmp/My Icons/Ícone #1%.svg' });
assert.equal(result.ok, true);
assert.equal(result.data.renderVerified, false);
assert.equal(result.data.persisted, true);
assert.equal(result.data.reloaded, true);
const url = 'file:///tmp/My%20Icons/%C3%8Dcone%20%231%25.svg';
assert.equal(icons.host.settings.iconOverrides.code, url);
assert.equal(icons.host.settings.iconOverrides.other, '/tmp/Ícone original.png');
assert.equal(icons.host.settings.iconOverrides.legacy, 'not-a-valid-source');
assert.deepEqual(plain(icons.host.settings.pinned), ['code']);
assert.deepEqual(plain(icons.host.settings.extensionData), { keep: 2 });
let revision = icons.host.iconReloadRevision;
count = icons.writes.length;
result = call('icons.set', { id: 'code', source: url });
assert.equal(result.ok, true);
assert.equal(result.data.noop, true);
assert.equal(result.data.reloaded, true);
assert.equal(icons.writes.length, count, 'Same-source refresh must not create a redundant settings write');
assert.equal(icons.host.iconReloadRevision, ++revision);
result = call('icons.reload', { id: 'Code.desktop' });
assert.equal(result.ok, true);
assert.equal(result.data.applied, false, 'Reload does not apply a settings change');
assert.equal(result.data.reloaded, true);
assert.equal(result.data.renderVerified, false);
assert.equal(icons.host.iconReloadRevision, ++revision);
assert.equal(icons.writes.length, count);
assert.equal(call('icons.reload', { id: 'absent' }).error.code, 'E_VALIDATION');
assert.equal(icons.host.iconReloadRevision, revision);
for (const source of ['', 'relative.svg', 'https://host/a.svg', 'data:image/png,bad',
  'file://remote/a.png', '/tmp/a.gif', '/tmp/a.svg\0', 'file:///tmp/a.svg?query']) {
  assert.equal(call('icons.set', { id: 'code', source }).ok, false, source);
  assert.equal(icons.writes.length, count);
  assert.equal(icons.host.iconReloadRevision, revision);
}
for (const id of ['a/b', 'toString', 'unknown-application', '', '__proto__'])
  assert.equal(call('icons.set', { id, source: '/tmp/a.png' }).ok, false);
assert.equal(call('icons.set', { id: 'code', source: '/missing/corrupt.png' }).ok, true);
assert.equal(call('icons.list').data.overrides.code, 'file:///missing/corrupt.png');
assert.equal(call('icons.list').data.renderVerified, false);
assert.equal(call('icons.reset', { id: 'CODE.desktop' }).ok, true);
count = icons.writes.length;
revision = icons.host.iconReloadRevision;
assert.equal(call('icons.reset', { id: 'code' }).data.noop, true);
assert.equal(icons.writes.length, count);
assert.equal(icons.host.iconReloadRevision, revision);
assert.equal(icons.host.settings.iconOverrides.other, '/tmp/Ícone original.png');

// Config bulk replacement is fully validated; per-app intents preserve untouched legacy data.
for (const map of [{ code: 'https://host/a.svg' }, { code: '/tmp/a.gif' },
  { code: '/tmp/a.png', 'CODE.desktop': '/tmp/b.png' },
  JSON.parse('{"__proto__":"/tmp/a.png"}'), { 'a/b': '/tmp/a.png' }])
  assert.equal(call('config.apply', { patch: { iconOverrides: map } }).error.code, 'E_VALIDATION');
assert.equal(call('config.reset', { preferences: true }).ok, true);
assert.equal(icons.host.settings.iconOverrides.other, '/tmp/Ícone original.png');

icons.host.settingsReloadPending = true;
count = icons.writes.length;
revision = icons.host.iconReloadRevision;
for (const [command, args] of [['apps.pin', { id: 'new' }],
  ['icons.set', { id: 'code', source: '/tmp/a.png' }], ['icons.reload', { id: 'other' }]])
  assert.equal(call(command, args).error.code, 'E_BUSY');
assert.equal(icons.writes.length, count);
assert.equal(icons.host.iconReloadRevision, revision);
icons.host.settingsReloadPending = false;
icons.fault.save = true;
result = call('icons.set', { id: 'code', source: '/tmp/a.png' });
assert.equal(result.error.code, 'E_PERSISTENCE');
assert.equal(result.data.applied, true);
assert.equal(result.data.persisted, false);
assert.equal(result.data.renderVerified, false);
count = icons.writes.length;
assert.equal(call('icons.set', { id: 'code', source: '/tmp/a.png' }).error.code, 'E_PERSISTENCE');
assert.equal(icons.writes.length, count);
icons.fault.save = false;
assert.equal(call('config.retry').data.persisted, true);
assert.equal(JSON.parse(icons.writes.at(-1)).iconOverrides.code, 'file:///tmp/a.png');
icons.host.settingsFileLoaded('{bad');
assert.equal(call('apps.show', { all: true }).error.code, 'E_CONFIG_INVALID');
assert.equal(call('icons.reset', { id: 'code' }).error.code, 'E_CONFIG_INVALID');

assert.match(read('DockHost.qml'), /DesktopEntries\.applications\.values/);
assert.equal((read('DockHost.qml').match(/configFile\.setText\(/g) || []).length, 1);
const model = loadModel('DockConfigModel');
assert.equal(model.canonicalApplicationId('Code.desktop'), loadModel('DockModel').normalizedId('Code.desktop'));
console.log('App catalog, primitive membership/move intents, icon persistence/reload and error contracts: PASS');
