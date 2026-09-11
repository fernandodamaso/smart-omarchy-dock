import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../DockHost.qml', import.meta.url), 'utf8');
const body = source.match(/^  function settingsSaved\(\) \{[\s\S]*?^  }/m)?.[0];
assert.ok(body, 'Exercise the actual FileView completion handler');
const host = vm.createContext({
  settingsWriteError: 'old failure', settingsWriteState: 'saving',
  settingsLoadedText: '', settingsWriteText: '{"pinned":[]}\n',
  settingsLoadState: 'missing', settingsLoadError: '',
  settingsPersisted: false, settingsDefaultsInUse: true,
  reloadSettingsIfPending() {},
});
vm.runInContext(body, host);
host.settingsSaved();
assert.equal(host.settingsLoadState, 'loaded');
assert.equal(host.settingsWriteState, 'saved');
assert.equal(host.settingsPersisted, true);
assert.equal(host.settingsWriteError, '');
assert.equal(host.settingsLoadedText, host.settingsWriteText);
assert.equal(host.settingsDefaultsInUse, false,
  'Successful first retry created the file; state must no longer mean bundled-only defaults');
console.log('First successful save clears bundled-only load state: PASS');
