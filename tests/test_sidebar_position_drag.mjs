import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(rootPath, name), 'utf8');

// The mode-switch gesture is a two-mode contract: the classic dock renders on
// the bottom edge only, the sidebar is the left vertical presentation, and the
// empty-background drag switches presentationMode between them.
const dock = read('components/Dock.qml');
const host = read('DockHost.qml');
const sidebar = read('components/DockSidebar.qml');
const surface = read('components/DockPositionDragSurface.qml');
const model = read('components/DockModel.js');

// Classic dock keeps an empty-background drag surface wired to the host.
assert.match(dock, /DockPositionDragSurface\s*\{\s*id:\s*positionDragSurface/,
  'classic dock owns a position drag surface');
assert.match(dock, /onPositionRequested:\s*\(position, expectedPosition\)\s*=>/,
  'classic dock forwards position requests');

// The host translates a leftward dock drag into presentationMode: sidebar and
// never writes a vertical classic position.
assert.match(host, /onPositionRequested:[\s\S]*?saveSettingIntent\("presentationMode", "sidebar",/,
  'host maps a left drag to the sidebar mode');
assert.match(host, /saveSettingIntent\("position", position, expectedPosition\)/,
  'host keeps the stale-protected writer for residual position requests');

// The sidebar owns the reverse gesture: drag empty background down to return
// to the bottom dock mode through the same host writer.
assert.match(sidebar, /DockPositionDragSurface\s*\{\s*id:\s*positionDragSurface/,
  'sidebar owns a position drag surface');
assert.match(sidebar, /dockPosition:\s*"left"/,
  'sidebar drag surface starts from the left gesture edge');
assert.match(sidebar, /saveSettingIntent\("presentationMode", "classic",/,
  'sidebar maps a downward drag back to the dock mode');
assert.match(sidebar, /interactionAllowed:\s*!root\.controller\.interactionBusy/,
  'sidebar gesture yields to menus, popups, resize and row drags');

// The shared surface resolves gesture edges through dockGestureEdge, not the
// bottom-only classic position normalizer.
assert.match(surface, /DockModel\.dockGestureEdge\(dockPosition\)/,
  'drag surface uses the gesture edge helper');
assert.doesNotMatch(surface, /normalizeSetting\("position"/,
  'drag surface no longer depends on the classic position normalizer');
assert.match(model, /function dockGestureEdge\(value\)/,
  'model exposes the gesture edge helper');
assert.match(model, /function classicDockPosition\(value\) \{\n(?:.*\n)*?\s*return "bottom"\n\}/,
  'classic dock position always resolves to bottom');

console.log('sidebar position drag wiring tests passed');
