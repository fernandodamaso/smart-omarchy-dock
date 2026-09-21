import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const rootPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(rootPath, name), 'utf8');

function loadModel(name) {
  const source = read('components/' + name);
  const context = vm.createContext({ console });
  for (const match of source.matchAll(/^\.import "([^"]+)" as (\w+)$/gm))
    context[match[2]] = loadModel(match[1]);
  vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ''), context, { filename: name });
  return context;
}

const dock = loadModel('DockModel.js');
const config = loadModel('DockConfigModel.js');
const schema = JSON.parse(read('config/settings-schema.json'));

assert.deepEqual(schema.settings.position.enum, ['bottom', 'left']);
assert.equal(config.validatePatch({ position: 'bottom' }, schema).ok, true);
assert.equal(config.validatePatch({ position: 'left' }, schema).ok, true);
assert.equal(config.validatePatch({ position: 'top' }, schema).ok, false);
assert.equal(config.validatePatch({ position: 'right' }, schema).ok, false);

assert.equal(dock.normalizeSetting('position', 'bottom'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'left'), 'left');
assert.equal(dock.normalizeSetting('position', 'top'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'right'), 'left');
assert.equal(dock.normalizeSetting('position', 'diagonal'), 'bottom');

assert.equal(dock.dockPositionDragTarget('bottom', -47, 0, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('bottom', -48, 0, 48), 'left');
assert.equal(dock.dockPositionDragTarget('bottom', 120, 80, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('left', 0, 47, 48), 'left');
assert.equal(dock.dockPositionDragTarget('left', 0, 48, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('left', 80, -120, 48), 'left');
assert.equal(dock.dockPositionDragTarget('right', 0, 48, 48), 'bottom');

console.log('dock position model tests passed');
