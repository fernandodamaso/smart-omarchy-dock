import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const item = fs.readFileSync(new URL('../components/DockItem.qml', import.meta.url), 'utf8');
const dock = fs.readFileSync(new URL('../components/Dock.qml', import.meta.url), 'utf8');
const coordinator = fs.readFileSync(new URL('../components/DockWorkspaceDrag.qml', import.meta.url), 'utf8');

// Execute the production threshold helper, not a copy of its behavior.
const handler = item.slice(item.indexOf('    id: workspaceDragHandler'));
assert.ok(handler.startsWith('    id: workspaceDragHandler'));
const helper = item.slice(item.indexOf('  function updateWorkspaceGesture('),
  item.indexOf('  DragHandler {', item.indexOf('  function updateWorkspaceGesture(')));
const point = { x: 150, y: 30 };
const pressPoint = { x: 100, y: 30 };
const members = [{ address: '0x1' }];
let received;
const root = {
  runningToplevels: members,
  workspaceGestureOwned: false,
  workspaceGestureConsumed: false,
  dismissPopups() {},
  previewDismissRequested() {},
  workspaceDrag: { begin(...args) { received = args; } },
};
const artwork = { renderedSource: 'file:///icons/Criação.svg' };
const context = vm.createContext({ root, Application: {
  styleHints: { startDragDistance: 8 }
}, applicationArtwork: artwork });
const updateWorkspaceGesture = vm.runInContext('(' + helper + ')', context);
updateWorkspaceGesture.call(root, point, pressPoint);
assert.equal(received[0], root);
assert.equal(received[1], members);
assert.equal(received[2], point);
assert.equal(received[3], artwork.renderedSource,
  'workspace drag must read DockAppIcon.renderedSource, not the removed IconImage.source API');
assert.equal(root.workspaceGestureOwned, true);
assert.equal(root.workspaceGestureConsumed, true);

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
