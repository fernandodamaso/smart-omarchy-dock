import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
function scan(directory) {
  return fs.readdirSync(path.join(root, directory), { withFileTypes: true }).flatMap(entry => {
    const name = path.posix.join(directory, entry.name);
    return entry.isDirectory() ? scan(name) : [name];
  });
}
const helpers = /hiddenApplicationRows|applicationActionOptions|scrollActionOptions|colorChannelHex|colorToHex|surfaceColorMode|surfaceColorPatch|centeredPopupAnchor|resetSettingsPatch/;
const sources = ['DockHost.qml', ...scan('components'), ...scan('tests')].filter(name =>
  /\.(qml|js|mjs|py|sh)$/.test(name) && !name.endsWith('/test_settings_helpers.mjs'));
const obsolete = sources.flatMap(name => fs.readFileSync(path.join(root, name), 'utf8')
  .split('\n').flatMap((line, index) => helpers.test(line) ? [`${name}:${index + 1}: ${line.trim()}`] : []));
if (obsolete.length) console.log('Obsolete editor helper audit:\n' + obsolete.join('\n'));
assert.deepEqual(obsolete, [], 'Editor-only helpers and their obsolete tests must not survive the cutover');

// Changelog, old implementation plans and the FDM-858 audit remain historical.
// Current operator guides must not direct users to the removed panel or controls.
const guides = ['README.md', 'AGENTS.md', 'docs/AGENT_CONFIGURATION.md',
  'docs/attention-badges.md', 'docs/launcher-badge-counts.md', 'docs/FOCUS_INDICATOR.md',
  'docs/UPDATING.md', 'docs/RELEASING.md', 'docs/DELIVERY.md'];
const stale = guides.flatMap(name => fs.readFileSync(path.join(root, name), 'utf8')
  .split('\n').flatMap((line, index) => /DockSettings|dockSettings|settingPreviews|DockSettingSlider|DockColorTokenDropdown|DockColorSwatch|DockActionDropdown|DockHiddenApplicationRow|Dock Settings|graphical settings panel|graphical appearance settings|Settings →|Settings >/.test(line)
    ? [`${name}:${index + 1}: ${line.trim()}`] : []));
if (stale.length) console.log('Active guide cutover audit:\n' + stale.join('\n'));
assert.deepEqual(stale, [], 'Active instructions must use supported CLI workflows');
assert.match(fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8'), /## \[Unreleased\]/);
console.log('Obsolete editor helpers removed and active guides use CLI workflows: PASS');
