import assert from 'node:assert/strict';
import fs from 'node:fs';

function read(path) { return fs.readFileSync(new URL('../' + path, import.meta.url), 'utf8'); }

const host = read('DockHost.qml');
const view = read('components/DockSidebarWidgetView.qml');
const manager = read('components/DockSidebarWidgetManager.qml');
const model = read('components/DockSidebarWidgetModel.js');
const external = read('components/DockExternalWidgetRegistry.qml');
const launcher = read('scripts/dockrail');
const compatibilityLauncher = read('scripts/smartdock');
const packageManager = read('scripts/smartdock_widget.py');
const defaults = JSON.parse(read('config/dock.json'));
const schema = JSON.parse(read('config/settings-schema.json'));
const qmldir = read('SmartDock/WidgetKit/qmldir');

assert.match(host, /DockExternalWidgetRegistry\s*\{[\s\S]*?id:\s*externalWidgetRegistry[\s\S]*?dataRoot:\s*root\.dataRoot/,
  'the host must own external package discovery and pass the migration-selected data root');
assert.match(host, /externalWidgetRegistry\.descriptors/,
  'validated external descriptors must merge into the existing host registry');
assert.match(host, /"herdr\.agents"[\s\S]*?manageable:\s*false/,
  'Herdr remains source-owned and opts out of Add\/Manage');
assert.match(model, /function manageableRows\(registry\)/,
  'registry model must expose the manageable descriptor filter');
assert.match(manager, /WidgetModel\.manageableRows\(controller\.widgetRegistry\)/,
  'Add\/Manage must filter source-owned non-manageable descriptors');
assert.match(view, /presentation \+ "Source"/,
  'the existing Widget view loader must accept registry-owned package sources');
assert.match(view, /source:\s*root\.factory \? "" : root\.sourceUrl/,
  'external QML must flow through the existing Widget view rather than a second card system');
assert.match(external, /allowedEntryPrefix/);
assert.match(external, /StandardPaths\.writableLocation\(StandardPaths\.GenericDataLocation\)/,
  'external packages must resolve from the SmartDock-owned XDG data store');
assert.match(external, /property string dataRoot:\s*""/,
  'the registry accepts the host migration-selected data root');
assert.match(external, /root\.dataRoot !== ""/,
  'production hosts can select the canonical Dockrail package root');
assert.match(external, /GenericDataLocation\) \+ "\/smartdock"/,
  'legacy fallback remains available to isolated component tests and pre-cutover hosts');
assert.match(external, /if \(packageUrl\.indexOf\("file:"\) !== 0\) packageUrl = "file:\/\/" \+ packageUrl/,
  'runtime entry URLs must preserve StandardPaths file URLs without adding a second scheme');
assert.doesNotMatch(external, /return\s+"file:\/\/"\s*\+\s*root\.packageRoot/,
  'runtime entry URLs must never become file://file/// paths');
assert.match(external, /acquire:\s*function\(owner\)/,
  'external descriptors use the existing host-owned lease API');
assert.doesNotMatch(external, /dock\.json|sidebarWidgets/,
  'runtime package discovery may not turn settings paths into executable QML');
assert.match(launcher, /smartdock_widget\.py/,
  'the canonical dockrail launcher owns the Widget package CLI');
assert.doesNotMatch(packageManager, /\[\s*["']git["']\s*,\s*["']pull["']/,
  'Widget updates must never git-pull a deployment checkout');
assert.deepEqual(defaults.sidebarWidgets.every(id => typeof id === 'string'), true);
assert.equal(schema.settings.sidebarWidgets.format, 'sidebar-widget-ids');
assert.ok(!JSON.stringify(defaults.sidebarWidgets).match(/[\\/]|\.qml/i),
  'dock.json Widget selection stays ID-only');
for (const type of ['WidgetSection', 'WidgetText', 'WidgetButton', 'WidgetListItem', 'WidgetState']) {
  assert.match(qmldir, new RegExp('^' + type + ' 1\\.0 ', 'm'), `${type} must be exported by WidgetKit v1`);
}

console.log('External Widget package registry and ID-only runtime boundary: PASS');
