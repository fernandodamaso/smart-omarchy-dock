// Review regressions: production host/model methods with FileView substituted.
// Source-path checks use a private filesystem; no Quickshell host is launched.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { hostHarness, loadModel, plain, read } from './host_harness.mjs';

let failures = 0;
function check(name, run) {
  try {
    run();
    console.log('PASS: ' + name);
  } catch (error) {
    failures++;
    console.error('FAIL: ' + name + '\n' + error.stack);
  }
}

function sourceConfigPath(sourceDir, environment) {
  const expression = read('shell.qml').match(/configPath:\s*([\s\S]*?)\n  }/)?.[1];
  assert.ok(expression, 'Read the actual standalone configPath binding');
  return vm.runInNewContext('(' + expression + ')', {
    Quickshell: { shellDir: sourceDir, env: name => environment[name] || '' },
  });
}

check('source launches preserve factory defaults across save and restart', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'smartdock defaults '));
  try {
    const sourceDir = path.join(temporary, 'source');
    const home = path.join(temporary, 'home');
    const configHome = path.join(temporary, 'xdg config');
    const defaultsPath = path.join(sourceDir, 'config/dock.json');
    const originalBytes = read('config/dock.json');
    const defaults = JSON.parse(originalBytes);
    fs.mkdirSync(path.dirname(defaultsPath), { recursive: true });
    fs.writeFileSync(defaultsPath, originalBytes);
    const configPath = sourceConfigPath(sourceDir, { HOME: home, XDG_CONFIG_HOME: configHome });
    const customPath = path.join(temporary, 'explicit.json');
    assert.equal(sourceConfigPath(sourceDir, {
      HOME: home, XDG_CONFIG_HOME: configHome, SMARTDOCK_CONFIG: customPath,
    }), customPath, 'Explicit isolated configuration retains precedence');

    function openHost() {
      const initial = fs.existsSync(configPath)
        ? JSON.parse(fs.readFileSync(configPath, 'utf8')) : {};
      const h = hostHarness(initial);
      h.control.defaults = JSON.parse(fs.readFileSync(defaultsPath, 'utf8'));
      h.host.configPath = configPath;
      h.host.configFile.setText = text => {
        fs.mkdirSync(path.dirname(configPath), { recursive: true });
        fs.writeFileSync(configPath, text);
        h.host.settingsSaved();
      };
      return h;
    }
    const first = openHost();
    assert.equal(first.request('config.apply', { patch: { iconSize: 64, magnification: 1.5 } }).ok, true);
    const restarted = openHost();
    assert.equal(restarted.host.settings.iconSize, 64, 'Read saved user customization after restart');
    assert.equal(restarted.request('config.reset', { key: 'iconSize' }).ok, true);
    assert.equal(restarted.host.settings.iconSize, defaults.iconSize, 'Key reset must restore factory defaults');
    assert.equal(restarted.request('config.reset', { preferences: true }).ok, true);
    assert.equal(restarted.host.settings.magnification, defaults.magnification, 'Preference reset uses factory defaults');
    assert.equal(fs.readFileSync(defaultsPath, 'utf8'), originalBytes, 'No user write changes bundled bytes');
    assert.equal(configPath, path.join(configHome, 'smartdock/dock.json'));
    assert.equal(sourceConfigPath(sourceDir, { HOME: home }), path.join(home, '.config/smartdock/dock.json'));
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

check('new bulk IDs reject surrounding whitespace without touching state', () => {
  for (const field of ['pinned', 'hiddenApplications']) {
    for (const id of [' org.gnome.Nautilus ', '\tcode', 'code\u00a0']) {
      const h = hostHarness({ pinned: ['code'], extensionData: { keep: true } });
      const before = plain(h.host.settings);
      const response = h.request('config.apply', { patch: { [field]: [id], iconSize: 64 } });
      assert.equal(response.ok, false, field + ':' + JSON.stringify(id));
      assert.equal(response.error.code, 'E_VALIDATION');
      assert.deepEqual(plain(h.host.settings), before);
      assert.equal(h.writes.length, 0);
    }
  }
  const h = hostHarness({ pinned: [' Legacy.App '], extensionData: { keep: true } });
  assert.equal(h.request('config.apply', { patch: { iconSize: 48 } }).ok, true);
  assert.deepEqual(plain(h.host.settings.pinned), [' Legacy.App '], 'Do not normalize untouched legacy values');
  assert.equal(h.request('config.apply', { patch: { pinned: ['Code.desktop', 'Unavailable App'] } }).ok, true);
});

check('drag reordering preserves legacy pins and both drop directions', () => {
  const model = loadModel('DockModel');
  for (const legacy of ['CODE.desktop', 'unknown-application', 'legacy/invalid']) {
    const pinned = ['code', legacy, 'Hidden.App', 'org.gnome.Nautilus', 'Missing.App'];
    for (const [source, target] of [['code', 'org.gnome.Nautilus'], ['org.gnome.Nautilus', 'code']]) {
      const h = hostHarness({ pinned, hiddenApplications: ['Hidden.App'],
        iconOverrides: { code: '/tmp/keep.png' }, extensionData: { keep: 7 } });
      const expected = plain(model.reorderPinnedById(pinned, source, target));
      const response = plain(h.host.reorderPinned(source, target));
      assert.equal(response.ok, true, JSON.stringify({ legacy, source, target, response }));
      assert.deepEqual(plain(h.host.settings.pinned), expected);
      assert.deepEqual(JSON.parse(h.writes.at(-1)).pinned, expected);
      assert.deepEqual(plain(h.host.settings.hiddenApplications), ['Hidden.App']);
      assert.deepEqual(plain(h.host.settings.iconOverrides), { code: '/tmp/keep.png' });
      assert.deepEqual(plain(h.host.settings.extensionData), { keep: 7 });
      assert.equal(h.request('config.apply', { patch: { pinned } }).error.code, 'E_VALIDATION',
        'The drag fix must not weaken arbitrary bulk replacement validation');
    }
  }
  const h = hostHarness({ pinned: ['code', 'CODE.desktop', 'other'] });
  h.host.settingsReloadPending = true;
  assert.equal(h.host.reorderPinned('code', 'other').error.code, 'E_BUSY');
  assert.equal(h.writes.length, 0);
  h.host.settingsReloadPending = false;
  h.fault.save = true;
  const failure = h.host.reorderPinned('code', 'other');
  assert.equal(failure.error.code, 'E_PERSISTENCE');
  assert.equal(failure.data.applied, true);
  assert.equal(failure.data.persisted, false);
  assert.deepEqual(plain(h.host.settings.pinned), ['CODE.desktop', 'other', 'code']);
});

check('local QML fixtures reference existing components and are audited', () => {
  const directory = new URL('../local-tests/', import.meta.url);
  if (fs.existsSync(directory)) {
    for (const file of fs.readdirSync(directory).filter(name => name.endsWith('.qml'))) {
      const text = fs.readFileSync(new URL(file, directory), 'utf8');
      for (const match of text.matchAll(/\bComponents\.(\w+)\s*\{/g)) {
        assert.ok(fs.existsSync(new URL('../components/' + match[1] + '.qml', import.meta.url)),
          file + ' references missing component ' + match[1]);
      }
    }
  }
  for (const audit of ['tests/test_settings_cutover.mjs', 'tests/test_settings_helpers.mjs'])
    assert.ok(read(audit).includes("'local-tests'"), audit + ' must include local QML fixtures');
});

check('release notes document explicit launch and source config migration', () => {
  const notes = read('CHANGELOG.md').split('## 2.1.0')[0];
  assert.ok(notes.includes('smartdock launch --no-color'), 'Document replacement for old passthrough');
  assert.ok(notes.includes('SMARTDOCK_CONFIG'), 'Document explicit source config override');
  const audit = read('docs/FDM-858-native-ui-audit.md');
  assert.match(audit, /superseded/i, 'Historical UI audit must not present its deleted runner as current');
});

assert.equal(failures, 0, failures + ' PR #44 regression group(s) failed');
console.log('PR #44 source/default/identity/drag/removal migration regressions: PASS');
