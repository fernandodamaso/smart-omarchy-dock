import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const item = fs.readFileSync(new URL('../components/DockItem.qml', import.meta.url), 'utf8');
const dock = fs.readFileSync(new URL('../components/Dock.qml', import.meta.url), 'utf8');
const coordinator = fs.readFileSync(new URL('../components/DockWorkspaceDrag.qml', import.meta.url), 'utf8');

// Execute the production activation callback, not a copy of its behavior.
const handler = item.slice(item.indexOf('    id: workspaceDragHandler'));
assert.ok(handler.startsWith('    id: workspaceDragHandler'));
const activation = handler.slice(handler.indexOf('    onActiveChanged: {') + '    onActiveChanged: {'.length,
  handler.indexOf('    onActiveTranslationChanged:')).replace(/\}\s*$/, '');
const point = { x: 150, y: 30 };
const members = [{ address: '0x1' }];
let received;
const root = {
  runningToplevels: members,
  dismissPopups() {},
  previewDismissRequested() {},
  workspaceDrag: { begin(...args) { received = args; } },
};
const artwork = { renderedSource: 'file:///icons/Criação.svg' };
vm.runInNewContext(activation, {
  active: true, root, centroid: { scenePosition: point }, applicationArtwork: artwork,
  workspaceReleaseCleanup: { stop() {} },
});
assert.equal(received[0], root);
assert.equal(received[1], members);
assert.equal(received[2], point);
assert.equal(received[3], artwork.renderedSource,
  'workspace drag must read DockAppIcon.renderedSource, not the removed IconImage.source API');
assert.equal(root.workspaceGestureOwned, true);

// The host injects the actual retained renderer; the coordinator stays pure Qt.
assert.match(item, /DockAppIcon\s*\{\s*id: applicationArtwork/);
assert.doesNotMatch(item, /applicationArtwork\.source\b/);
assert.match(dock, /artworkDelegate:\s*Component\s*\{\s*DockAppIcon\s*\{/);
assert.match(dock, /desktopId:\s*workspaceDrag\.sourceItem\s*\?\s*workspaceDrag\.sourceItem\.desktopId/);
const delegate = dock.slice(dock.indexOf('    artworkDelegate:'), dock.indexOf('    onAboutToBegin:'));
assert.match(delegate, /desktopIcon:[\s\S]*workspaceDrag\.sourceItem\.entry\.icon/);
assert.match(delegate, /iconOverrides:\s*root\.iconOverrides/);
assert.match(delegate, /reloadRevision:\s*root\.iconReloadRevision/);
assert.match(coordinator, /property Component artworkDelegate: null/);
assert.match(coordinator, /active:\s*root\.active && root\.artworkDelegate !== null/);
assert.match(coordinator, /sourceComponent:\s*root\.artworkDelegate/);
assert.doesNotMatch(coordinator, /^import (Quickshell|qs\.)/m);
// The existing cutover audit owns the complete removed-component check.
console.log('Workspace drag CLI/renderer integration passed');
