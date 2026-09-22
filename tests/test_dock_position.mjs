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

assert.deepEqual(schema.settings.position.enum, ['bottom']);
assert.equal(config.validatePatch({ position: 'bottom' }, schema).ok, true);
assert.equal(config.validatePatch({ position: 'left' }, schema).ok, false);
assert.equal(config.validatePatch({ position: 'top' }, schema).ok, false);
assert.equal(config.validatePatch({ position: 'right' }, schema).ok, false);

// The classic dock is bottom-only; the left vertical presentation is the
// sidebar mode. Legacy stored values keep reading as bottom.
assert.equal(dock.normalizeSetting('position', 'bottom'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'left'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'top'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'right'), 'bottom');
assert.equal(dock.normalizeSetting('position', 'diagonal'), 'bottom');

// The drag surface still maps between the bottom dock and the left sidebar
// edge; DockHost translates those edges into presentationMode writes.
assert.equal(dock.dockGestureEdge('bottom'), 'bottom');
assert.equal(dock.dockGestureEdge('left'), 'left');
assert.equal(dock.dockGestureEdge('right'), 'left');
assert.equal(dock.dockGestureEdge('top'), 'bottom');

assert.equal(dock.dockPositionDragTarget('bottom', -47, 0, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('bottom', -48, 0, 48), 'left');
assert.equal(dock.dockPositionDragTarget('bottom', 120, 80, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('left', 0, 47, 48), 'left');
assert.equal(dock.dockPositionDragTarget('left', 0, 48, 48), 'bottom');
assert.equal(dock.dockPositionDragTarget('left', 80, -120, 48), 'left');
assert.equal(dock.dockPositionDragTarget('right', 0, 48, 48), 'bottom');

// Gesture feedback copy names the destination it would commit to, for both
// gesture edges, and the silhouette always sits on the configured sidebar edge.
assert.equal(dock.modeDragHint('bottom'), 'Drag left to switch to sidebar');
assert.equal(dock.modeDragHint('left'), 'Drag down to switch to dock');
assert.equal(dock.modeDragHint('right'), 'Drag down to switch to dock');
assert.equal(dock.modeDragArmedLabel('bottom'), 'Release to switch to sidebar');
assert.equal(dock.modeDragArmedLabel('left'), 'Release to switch to dock');
assert.equal(dock.modeDragDestination('bottom'), 'sidebar');
assert.equal(dock.modeDragDestination('left'), 'classic');
assert.equal(dock.modeDragDestinationEdge('bottom', 'left'), 'left');
assert.equal(dock.modeDragDestinationEdge('bottom', 'right'), 'right');
assert.equal(dock.modeDragDestinationEdge('left', 'right'), 'bottom');
assert.equal(dock.modeDragDestinationEdge('right', 'left'), 'bottom');

// The hint only appears after real movement; wrong-direction movement can arm
// nothing, so this only gates the pill, never the commit.
assert.equal(dock.modeDragHintVisible(0, 0, 6), false);
assert.equal(dock.modeDragHintVisible(5, 0, 6), false);
assert.equal(dock.modeDragHintVisible(6, 0, 6), true);
assert.equal(dock.modeDragHintVisible(0, -6, 6), true);
assert.equal(dock.modeDragHintVisible(NaN, NaN, 6), false);

// Silhouette geometry mirrors the classic dock's own layout: a bottom band with
// the configured margin, flush full-height side panels.
assert.equal(JSON.stringify(dock.modeDragPreviewRect('bottom', 1920, 1080, 86, 10)),
  JSON.stringify({ edge: 'bottom', x: 0, y: 984, width: 1920, height: 86 }));
assert.equal(JSON.stringify(dock.modeDragPreviewRect('left', 1920, 1080, 64, 0)),
  JSON.stringify({ edge: 'left', x: 0, y: 0, width: 64, height: 1080 }));
assert.equal(JSON.stringify(dock.modeDragPreviewRect('right', 1920, 1080, 64, 0)),
  JSON.stringify({ edge: 'right', x: 1856, y: 0, width: 64, height: 1080 }));

// Classic band extent mirrors Dock.qml's dockBackground sizing.
assert.equal(dock.classicBandExtent(42, false), 86);
assert.equal(dock.classicBandExtent(42, true), 74);
assert.equal(dock.classicBandExtent(0, false), 86);

// The sidebar exposes exactly one background: the blank tail below its content.
assert.equal(
  JSON.stringify(dock.sidebarBlankRegion(300, 500, 0, 64)),
  JSON.stringify({ x: 0, y: 300, width: 64, height: 200 }));
assert.equal(
  JSON.stringify(dock.sidebarBlankRegion(600, 500, 0, 64)),
  JSON.stringify({ x: 0, y: 0, width: 0, height: 0 }),
  'overflow leaves no blank tail');
assert.equal(
  JSON.stringify(dock.sidebarBlankRegion(600, 500, 100, 64)),
  JSON.stringify({ x: 0, y: 0, width: 0, height: 0 }),
  'a scrolled list leaves no blank tail');

// The silhouette destination width follows the per-connector collapse lookup.
assert.equal(dock.sidebarCollapsedForScreen({ 'HDMI-A-1': true }, false, 'HDMI-A-1'), true);
assert.equal(dock.sidebarCollapsedForScreen({ 'HDMI-A-1': true }, false, 'DP-1'), false);
assert.equal(dock.sidebarCollapsedForScreen(undefined, true, 'DP-1'), true);

// Rejected and persistence-failed writes share one wording across renderers.
assert.match(dock.modeDragWriteError({ accepted: false,
  reply: { error: { code: 'E_STALE', message: 'Preference changed after the interaction started; refresh before retrying.' } } }),
/^Preferences were not saved: Preference changed/);
assert.equal(dock.modeDragWriteError({ accepted: true, reply: { ok: true } }), '',
  'an accepted write clears feedback');
assert.match(dock.persistenceFeedback('disk full'), /^Unsaved preferences: disk full$/);

console.log('dock position model tests passed');
