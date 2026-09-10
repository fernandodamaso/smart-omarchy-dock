import assert from 'node:assert/strict';
import { hostHarness, read, plain } from './host_harness.mjs';

// The native catalog can be an array-like QObject list, not a JavaScript Array.
const catalog = { 0: { id: 'Exact.App', name: 'Friendly Editor' }, length: 1 };
const h = hostHarness({ pinned: [], hiddenApplications: [], iconOverrides: {} }, catalog);
assert.equal(h.request('apps.pin', { id: 'EXACT.APP.desktop' }).ok, true);
assert.deepEqual(plain(h.host.settings.pinned), ['Exact.App']);
assert.deepEqual(h.request('apps.list', { query: 'friendly' }).data.applications.map(a => a.id), ['Exact.App']);
assert.equal(h.request('apps.pin', { id: 'Friendly Editor' }).ok, true);
assert.deepEqual(plain(h.host.settings.pinned), ['Exact.App', 'Friendly Editor'], 'No display-name alias may select another application');
assert.equal(h.request('apps.list', { pinned: true }).data.applications[1].available, false);
h.host.pinApplication('exact.app');
h.host.hideApplication('EXACT.APP.desktop');
h.host.unpinApplication('EXACT.APP');
assert.deepEqual(plain(h.host.settings.pinned), ['Friendly Editor']);
assert.deepEqual(plain(h.host.settings.hiddenApplications), ['Exact.App'], 'Menu and CLI intents share canonical identities');
assert.deepEqual(h.request('apps.list', { pinned: true }).data.applications.map(a => a.pinnedIndex), [0]);

// Guard artwork-only forwarding in both dock layouts, preview metadata and picker rows.
for (const file of ['DockItem.qml', 'DockWindowPreviewTile.qml', 'DockAppPicker.qml']) {
  const source = read('components/' + file);
  assert.match(source, /DockAppIcon\s*\{/, file);
  assert.match(source, /property var iconOverrides: \(\{\}\)/, file);
  assert.match(source, /property int iconReloadRevision: 0/, file);
  assert.match(source, /reloadRevision: root\.iconReloadRevision/, file);
}
assert.match(read('DockHost.qml'), /iconOverrides: root\.settings\.iconOverrides/);
assert.match(read('DockHost.qml'), /iconReloadRevision: root\.iconReloadRevision/);
assert.match(read('components/Dock.qml'), /iconOverrides: root\.iconOverrides/);
assert.match(read('components/DockWindowPreview.qml'), /iconOverrides: root\.iconOverrides/);
const schema = JSON.parse(read('config/settings-schema.json'));
const guide = read('docs/AGENT_CONFIGURATION.md');
const client = read('scripts/smartdock_cli.py');
for (const command of ['apps.list', 'apps.pin', 'apps.unpin', 'apps.hide', 'apps.show', 'apps.move', 'icons.list', 'icons.set', 'icons.reset', 'icons.reload']) {
  assert.ok(schema.commands.includes(command), command);
  assert.ok(guide.includes(command.replace('.', ' ')), command);
}
assert.match(guide, /renderVerified: false/);
assert.match(client, /icons reload ID/);
assert.equal(schema.settings.iconOverrides.resetWithPreferences, false);
console.log('Native catalog shape, exact identities, shared artwork forwarding and discoverability: PASS');
