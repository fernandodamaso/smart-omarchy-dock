import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { hostHarness } from './host_harness.mjs';
import { qmlMethods } from './sidebar_interaction_fixture.mjs';

// The background drag switches presentationMode between the classic bottom dock
// and the sidebar. Both renderers route their completed gesture through the one
// host-owned writer, so these tests exercise that behavior directly instead of
// matching source text: accepted writes happen exactly once, rejected intents
// (stale or busy) never write and surface readable feedback.

const rootPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = name => fs.readFileSync(path.join(rootPath, name), 'utf8');

const harness = hostHarness({});
const { host, writes } = harness;
const modeWrites = () => writes.filter(text => /"presentationMode"/.test(text));

// Accepted gesture: one presentationMode write, empty feedback.
assert.equal(host.handlePositionRequest('left', 'bottom', 'classic'), '',
  'an accepted mode gesture reports no failure');
assert.equal(modeWrites().length, 1, 'exactly one write per accepted gesture');
assert.match(modeWrites()[0], /"presentationMode":\s*"sidebar"/,
  'a leftward dock drag switches to the sidebar mode');
assert.equal(host.modeGestureFeedback, '',
  'an accepted write clears host feedback');

// A stale gesture (the mode changed after the press) is rejected without a write.
assert.match(host.handlePositionRequest('left', 'bottom', 'classic'),
  /Preferences were not saved/, 'a stale expected value is surfaced');
assert.equal(modeWrites().length, 1, 'a stale gesture never writes');

// A second stale gesture still adds no write: one intent per gesture, never a retry.
assert.match(host.handlePositionRequest('left', 'bottom', 'classic'),
  /Preferences were not saved/);
assert.equal(modeWrites().length, 1, 'repeated rejected gestures never write');
assert.notEqual(host.modeGestureFeedback, '', 'a rejected gesture leaves feedback');

// Busy preflight (a save already in flight) is rejected without a write.
host.settingsWriteState = 'saving';
assert.match(host.handlePositionRequest('left', 'bottom', 'sidebar'),
  /Preferences were not saved/, 'a busy writer is surfaced');
assert.equal(modeWrites().length, 1, 'a busy gesture never writes');
host.settingsWriteState = 'idle';

// A settings reload clears any host-owned gesture failure and restores the
// configured mode for the next gesture.
host.settingsFileLoaded(JSON.stringify(harness.defaults));
assert.equal(host.modeGestureFeedback, '',
  'a settings reload clears gesture feedback');

// Non-left residual requests keep the stale-protected position writer instead of
// committing a mode switch.
const positionReply = host.handlePositionRequest('bottom', 'bottom', 'classic');
assert.equal(typeof positionReply, 'object',
  'a position request answers with an intent result, not gesture feedback');
assert.equal(modeWrites().length, 1, 'a bottom request never writes a mode');

// --- sidebar renderer: commitModeSwitch ----------------------------------
const sidebar = qmlMethods('DockSidebar.qml', { host, DockModel: host.DockModel });
sidebar.modeDragError = 'stale text';

sidebar.commitModeSwitch('left', 'classic');
assert.equal(modeWrites().length, 1,
  'a non-bottom position request never commits a mode write');
assert.equal(sidebar.modeDragError, 'stale text',
  'an ignored position leaves local feedback untouched');

sidebar.commitModeSwitch('bottom', 'sidebar');
assert.match(sidebar.modeDragError, /Preferences were not saved/,
  'a rejected sidebar switch surfaces its reason');
assert.equal(modeWrites().length, 1, 'a rejected switch never writes');

assert.equal(host.handlePositionRequest('left', 'bottom', 'classic'), '',
  'the mode flips to the sidebar for the reverse gesture');
sidebar.commitModeSwitch('bottom', 'sidebar');
assert.equal(sidebar.modeDragError, '', 'an accepted switch clears local error');
assert.match(modeWrites().at(-1), /"presentationMode":\s*"classic"/,
  'a downward sidebar drag switches back to the classic mode');

// Persistence failures are reported by the surviving renderer from host state.
host.settingsSaveFailed(3);
assert.match(host.modeGestureFeedback,
  /^Unsaved preferences: Settings changed for this session, but could not be saved\./,
  'a persistence failure surfaces host-owned feedback');

// --- structural wiring that cannot be instantiated headless ---------------
const dockSource = read('components/Dock.qml');
const sidebarSource = read('components/DockSidebar.qml');
const surfaceSource = read('components/DockPositionDragSurface.qml');
const hostSource = read('DockHost.qml');

// The classic dock owns the panel-level surface and forwards its request with
// the press-time presentation for stale protection.
assert.match(dockSource, /DockPositionDragSurface\s*\{\s*id:\s*positionDragSurface/,
  'classic dock owns a position drag surface');
assert.match(dockSource, /root\.positionRequested\(position, expectedPosition, expectedPresentation\)/,
  'classic dock forwards position requests to the host handler');
assert.match(surfaceSource, /expectedPresentation/,
  'the surface captures the presentation seen at press time');
assert.match(surfaceSource, /gestureCancelled/,
  'the surface can cancel without writing');

// The sidebar owns the reverse gesture plus the blank-tail surface, and both
// yield to menus, popups, resize and row drags.
assert.match(sidebarSource, /DockPositionDragSurface\s*\{\s*id:\s*positionDragSurface/,
  'sidebar owns a position drag surface');
assert.match(sidebarSource, /DockPositionDragSurface\s*\{\s*id:\s*viewportDragSurface/,
  'sidebar owns a blank-tail drag surface');
assert.match(sidebarSource, /dockPosition:\s*root\.sidebarEdge/,
  'sidebar drag surface starts from its configured gesture edge');
assert.match(sidebarSource, /interactionAllowed:\s*!root\.controller\.interactionBusy/,
  'sidebar gesture yields to menus, popups, resize and row drags');

// The host owns the single write and its feedback.
assert.match(hostSource, /function commitModeGesture\(value, expectedValue\)/,
  'host owns the mode gesture writer');
assert.equal(
  (hostSource.match(/saveSettingIntent\("presentationMode"/g) || []).length, 1,
  'there is exactly one presentationMode writer in the host');
assert.match(dockSource, /presentationMode:\s*DockModel\.normalizeSetting\("presentationMode"/,
  'the surface tracks the live presentation it started from');

console.log('sidebar position drag wiring tests passed');
