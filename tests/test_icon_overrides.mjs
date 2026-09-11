// Model assertions retained from PR #42 @27f3599; host assertions now exercise
// the CLI-02 shared writer rather than substituting a second save implementation.
import assert from 'node:assert/strict';
import { loadModel, hostHarness, plain, read } from './host_harness.mjs';
const icons = loadModel('DockIconModel');
const DockModel = loadModel('DockModel');
assert.equal(icons.normalizeKey(' ChatGPT.desktop '), 'chatgpt');
assert.equal(icons.normalizeKey('Org.Example.desktop'), DockModel.normalizedId('Org.Example.desktop'));
for (const key of ['', ' ', 'unknown-application', 'Unknown-Application.desktop', '__proto__', 'constructor', 'prototype', 'toString', null, 42])
  assert.equal(icons.normalizeKey(key), '');
const encoded = 'file:///tmp/My%20Icons/%C3%8Dcone%20%231%25.svg';
assert.equal(icons.normalizeSource('/tmp/My Icons/Ícone #1%.svg'), encoded);
assert.equal(icons.normalizeSource(encoded), encoded);
assert.equal(icons.normalizeSource('/tmp/What?%23.PNG'), 'file:///tmp/What%3F%2523.PNG');
assert.equal(icons.normalizeSource('file:///tmp/What%3F%2523.PNG'), 'file:///tmp/What%3F%2523.PNG');
assert.equal(icons.localFileUrl('file://localhost/tmp/a.svg'), 'file:///tmp/a.svg');
assert.equal(icons.localFileUrl('/tmp/a.xpm'), 'file:///tmp/a.xpm');
assert.equal(icons.localFileUrl('/tmp/a/../b.svg'), 'file:///tmp/b.svg');
for (const value of ['', null, {}, 12, 'relative.svg', '~/a.svg', '$HOME/a.svg', 'https://a/a.svg', 'data:image/png,x', 'qrc:/a.svg', 'image://provider/a.svg', 'file://server/a.svg', 'file:relative.svg', 'file:///tmp/a%ZZ.svg', 'file:///tmp/a.svg?query', 'file:///tmp/a.svg#fragment', '/tmp/a.gif', '/tmp/a.svg\0'])
  assert.equal(icons.normalizeSource(value), '', String(value));
for (const value of [null, undefined, [], 'bad', 4])
  assert.deepEqual(plain(icons.normalizeOverrides(value)), {});
const inherited = Object.assign(Object.create({ inherited: '/tmp/a.svg' }), {
  Code: '/tmp/first.png', ' code.desktop ': '/tmp/last.svg', 'CODE.desktop': 'bad',
  unknown: null, constructor: '/tmp/a.svg', prototype: '/tmp/a.svg'
});
assert.deepEqual(plain(icons.normalizeOverrides(inherited)), { code: 'file:///tmp/last.svg' });
assert.deepEqual(plain(icons.normalizeOverrides(JSON.parse('{"__proto__":"/tmp/a.svg"}'))), {});
const original = Object.freeze({ code: 'file:///tmp/code.png' });
const set = icons.applyOverride(original, 'ChatGPT.desktop', '/tmp/chatgpt.svg');
assert.equal(set.ok, true);
assert.equal(set.changed, true);
assert.deepEqual(plain(set.overrides), { ...original, chatgpt: 'file:///tmp/chatgpt.svg' });
assert.deepEqual(original, { code: 'file:///tmp/code.png' });
assert.equal(icons.applyOverride(set.overrides, 'chatgpt', '/tmp/chatgpt.svg').changed, false);
for (const source of ['', undefined, 'bad']) {
  const result = icons.applyOverride(set.overrides, 'chatgpt', source);
  assert.equal(result.ok, false);
  assert.equal(result.changed, false);
  assert.ok(result.error);
  assert.deepEqual(plain(result.overrides), plain(set.overrides));
}
assert.equal(icons.applyOverride(original, 'unknown-application', null).ok, false);
assert.deepEqual(plain(icons.applyOverride(set.overrides, 'chatgpt', null).overrides), original);
assert.equal(icons.applyOverride(original, 'chatgpt', null).changed, false);
assert.deepEqual(plain(icons.candidates('custom', 'desktop', 'generic')), ['custom', 'desktop', 'generic']);
assert.deepEqual(plain(icons.candidates('', 'same', 'same')), ['same']);
assert.deepEqual(plain(icons.candidates(null, '', undefined)), []);

const { host, writes, request } = hostHarness({ pinned: ['code'], iconOverrides: original, customSetting: 'retained' });
const initialRevision = host.iconReloadRevision;
assert.equal(host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg').ok, true);
assert.equal(host.iconReloadRevision, initialRevision + 1);
host.saveIconOverride('code', '/tmp/new.png');
host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg');
assert.equal(host.iconReloadRevision, initialRevision + 3);
assert.equal(host.settings.iconOverrides.code, 'file:///tmp/new.png');
assert.equal(host.settings.customSetting, 'retained');
const beforeInvalid = writes.length;
assert.equal(host.saveIconOverride('chatgpt', 'bad').ok, false);
assert.equal(writes.length, beforeInvalid);
assert.equal(host.iconReloadRevision, initialRevision + 3);
host.saveSetting('iconSize', 64);
assert.equal(request('config.reset', { preferences: true }).ok, true);
assert.equal(host.settings.iconSize, JSON.parse(read('config/dock.json')).iconSize);
assert.equal(host.iconReloadRevision, initialRevision + 3);
assert.equal(host.settings.iconOverrides.chatgpt, 'file:///tmp/chatgpt.svg');
host.loadSettings(JSON.stringify({ ...plain(host.settings), iconOverrides: { 'CHATGPT.desktop': '/tmp/chatgpt.svg', code: '/tmp/new.png' } }));
assert.equal(host.iconReloadRevision, initialRevision + 3);
host.loadSettings(JSON.stringify({ ...plain(host.settings), iconOverrides: { code: '/tmp/external.png' } }));
assert.equal(host.iconReloadRevision, initialRevision + 4);
host.saveIconOverride('code', '');
assert.equal(host.iconReloadRevision, initialRevision + 5);
host.saveIconOverride('code', '');
assert.equal(host.iconReloadRevision, initialRevision + 5);
for (const iconOverrides of [null, [], 'bad', { code: 'bad' }]) {
  host.loadSettings(JSON.stringify({ pinned: ['code'], iconSize: 57, iconOverrides }));
  // The CLI-02 requested snapshot is lossless; only the effective renderer view
  // normalizes old malformed mappings. Unrelated writes must not silently prune them.
  assert.deepEqual(plain(host.settings.iconOverrides), iconOverrides);
  assert.deepEqual(plain(icons.normalizeOverrides(host.settings.iconOverrides)), {});
  assert.equal(host.settings.iconSize, 57);
  assert.equal(host.iconReloadRevision, initialRevision + 5);
}
assert.deepEqual(JSON.parse(read('config/dock.json')).iconOverrides, {});
console.log('Retained icon model and shared host writer behavior: PASS');
