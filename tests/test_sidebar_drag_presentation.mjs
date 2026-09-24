import assert from 'node:assert/strict'
import {loadModel, plain, read} from './host_harness.mjs'
const m = loadModel('DockSidebarInteractionModel')
assert.equal(typeof m.formatDragDestination, 'function', 'ghost uses source-kind-aware production formatter')
const cases = [
  ['window', {identity:'id:3'}, null, '', '→ Workspace 3', 'accent'],
  ['window', {identity:'name:Design work'}, null, '', '→ Workspace Design work', 'accent'],
  ['window', {kind:'monitor',identity:'id:3',monitor:'id:0'}, null, 'DP-1', '→ DP-1 · workspace 3', 'accent'],
  ['window', {kind:'new-workspace',monitor:'id:0'}, null, 'DP-1', '→ New workspace on DP-1', 'accent'],
  ['workspace', {monitor:'id:0'}, null, 'DP-1', '→ DP-1', 'accent'],
  ['window', null, {reason:'same-workspace',identity:'id:3'}, '', 'Already in workspace 3', 'muted'],
  ['window', null, {reason:'pinned',identity:'name:Work'}, '', 'Pinned to workspace Work', 'urgent'],
  ['workspace', null, {reason:'same-monitor'}, '', 'Already on this monitor', 'muted'],
  ['workspace', null, {reason:'workspace-pinned',monitor:'id:1'}, 'HDMI-A-1', 'Workspace pinned to HDMI-A-1', 'urgent'],
  ['window', null, {reason:'unknown-location'}, '', 'Destination unavailable', 'muted'],
  ['workspace', null, {reason:'unknown-location'}, '', 'Destination unavailable', 'muted'],
  ['window', null, {reason:'stale'}, '', 'Destination changed', 'muted'],
  ['workspace', null, {reason:'stale'}, '', 'Destination changed', 'muted'],
  ['window', null, {reason:'owner-mismatch'}, '', 'Workspace no longer on this monitor', 'muted'],
  ['window', null, null, '', '', 'muted'],
  ['workspace', null, null, '', '', 'muted'],
  ['window', {kind:'new-workspace',monitor:'id:9'}, null, '', 'Destination unavailable', 'muted'],
]
for (const [kind, target, rejection, monitor, text, tone] of cases) {
  const result = m.formatDragDestination(kind, target, rejection, monitor)
  assert.equal(result.text, text)
  assert.equal(result.tone, tone)
  assert.equal(result.blocked, tone === 'urgent')
}
const windowSession = {target:{kind:'window',key:'w1'},location:{identity:'id:3'}}
const workspaceSession = {target:{kind:'workspace',key:'ws3'},location:{identity:'id:3'}}
const rows = [{kind:'workspace',key:'ws3',workspaceIdentity:'id:3'},
  {kind:'window',key:'w1',workspaceIdentity:'id:3'},
  {kind:'application',key:'a1',workspaceIdentity:'id:3'},
  {kind:'herdr-agent',key:'h1',workspaceIdentity:'id:3'},
  {kind:'monitor',key:'mon'}, {kind:'window',key:'other',workspaceIdentity:'id:5'}]
assert.deepEqual(rows.map(r=>m.dragSourceOpacity(r,windowSession)), [1,0.4,1,1,1,1])
assert.deepEqual(rows.map(r=>m.dragSourceOpacity(r,workspaceSession)), [0.4,0.4,0.4,0.4,1,1])
assert.equal(m.dragSourceOpacity(rows[1],null),1)
assert.equal(m.dragGhostWidth(252,false),168)
assert.equal(m.dragGhostWidth(140,false),124)
assert.equal(m.dragGhostWidth(52,true),32)
assert.equal(m.dragGhostWidth(8,false),0)
assert.equal(m.dragProxyOffset(250,252,m.dragGhostWidth(252,false)),84)
assert.equal(m.dragProxyOffset(50,52,m.dragGhostWidth(52,true)),20)
assert.match(read('components/DockSidebarRow.qml'), /InteractionModel\.dragSourceOpacity\(/)
assert.match(read('components/DockSidebarViewport.qml'), /clip: true/)
assert.match(read('components/DockSidebarRowInput.qml'), /cursorShape: root\.dragOwned \? Qt\.ClosedHandCursor/)
console.log('R1 ghost labels, source opacity and bounded expanded/rail geometry: PASS')
