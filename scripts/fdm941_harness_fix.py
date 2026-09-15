#!/usr/bin/env python3
from pathlib import Path


def replace_one(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    p.write_text(text.replace(old, new, 1))

replace_one(
    'tests/test_cli_host.mjs',
'''  DockModel: loadModel('DockModel.js'),
  DockWindowModel: loadModel('DockWindowModel.js'),
  TrashModel: loadModel('DockTrashModel.js'),''',
'''  DockModel: loadModel('DockModel.js'),
  DockWindowModel: loadModel('DockWindowModel.js'),
  WorkspaceGroupModel: loadModel('DockWorkspaceGroupModel.js'),
  TrashModel: loadModel('DockTrashModel.js'),''',
    'CLI host workspace-group model injection')

replace_one(
    'tests/test_config_model.mjs',
'''const shared = { console: { warn() {} }, ConfigModel: model,
  DockModel: loadModel('DockModel.js'), DockWindowModel: loadModel('DockWindowModel.js'),
  TrashModel: loadModel('DockTrashModel.js') };''',
'''const shared = { console: { warn() {} }, ConfigModel: model,
  DockModel: loadModel('DockModel.js'), DockWindowModel: loadModel('DockWindowModel.js'),
  WorkspaceGroupModel: loadModel('DockWorkspaceGroupModel.js'),
  TrashModel: loadModel('DockTrashModel.js') };''',
    'config model host workspace-group injection')

replace_one(
    'tests/test_config_model.mjs',
'''assert.equal(request('config.get').data.source, 'requested');
assert.equal(request('config.get', { effective: true }).data.source, 'effective');

deferWrite = true;''',
'''assert.equal(request('config.get').data.source, 'requested');
assert.equal(request('config.get', { effective: true }).data.source, 'effective');

// Legacy global grouping is a stored compatibility value only: loading it
// performs no migration/write, requested readback preserves it, effective
// readback disables it, new enables reject, and unrelated writes keep it.
const legacyLoadWrites = writes;
disk = JSON.stringify({ ...host.settings, groupWindows: true, workspaceGroups: [] });
cached = disk;
host.settingsFileLoaded(disk);
assert.equal(writes, legacyLoadWrites,
  'loading stored legacy grouping must not rewrite configuration');
assert.equal(request('config.get', { key: 'groupWindows' }).data.settings.groupWindows, true);
assert.equal(request('config.get', { key: 'groupWindows', effective: true }).data.settings.groupWindows, false);
const legacyEnableWrites = writes;
result = apply({ groupWindows: true });
assert.equal(result.error.code, 'E_VALIDATION');
assert.match(result.error.message, /workspaceGroups|Group Windows/i);
assert.equal(writes, legacyEnableWrites);
const legacyIconSize = host.settings.iconSize === 53 ? 54 : 53;
assert.equal(apply({ iconSize: legacyIconSize }).ok, true);
assert.equal(host.settings.groupWindows, true);
assert.equal(JSON.parse(disk).groupWindows, true);
assert.deepEqual(JSON.parse(disk).workspaceGroups, []);

deferWrite = true;''',
    'legacy grouping host lifecycle evidence')

print('FDM-941 standalone harnesses and legacy lifecycle tests updated')
