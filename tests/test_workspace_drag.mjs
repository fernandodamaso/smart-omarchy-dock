import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = name => fs.readFileSync(new URL(`../components/${name}`, import.meta.url), 'utf8')
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(read(name).replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}
const DockModel = model('DockModel.js')
const DockWindowModel = model('DockWindowModel.js', { DockModel })
function methods(file, properties) {
  const scope = vm.createContext(properties)
  scope.root = scope
  vm.runInContext((read(file).match(/^  function [\s\S]*?^  }/gm) || []).join('\n'), scope,
    { filename: file })
  return scope
}
function fixture(usingLua = false) {
  const windows = [{ appId: 'editor' }, { appId: 'editor' }, { appId: 'editor' }]
  const handles = windows.map((wayland, index) => ({ wayland, address: String(index + 1),
    lastIpcObject: { workspace: { id: index === 2 ? 9 : 1 }, monitor: 0, pinned: false } }))
  const requests = []
  const workspaces = [
    { id: 1, monitorID: 0 }, { id: 9, monitor: 'DP-1' }, { id: 12, monitor: 'DP-2' },
    { id: -1337, name: 'Design work', monitorID: 1 },
    { id: -1338, name: 'Criação', monitorID: 1 },
    { id: -1339, name: '*', monitorID: 0 },
    { id: -99, name: 'special:scratch', monitorID: 0 }
  ]
  const monitors = [{ id: 0, name: 'DP-1' }, { id: 1, name: 'DP-2' }]
  const actions = methods('DockWindowActions.qml', {
    DockModel, DockWindowModel,
    minimizedWorkspace: 'special:smartdock-minimized', minimizedOrigins: {},
    ToplevelManager: { toplevels: { values: windows } },
    Hyprland: { toplevels: { values: handles }, workspaces: { values: workspaces },
      monitors: { values: monitors }, usingLua, dispatch: request => requests.push(request) }
  })
  return { actions, windows, handles, requests, workspaces, monitors }
}

// Both production dispatch dialects, not a duplicate request builder.
for (const lua of [false, true]) {
  for (const target of [1, 2, 10, 12, 'name:Design work', 'name:Criação', 'name:*']) {
    assert.equal(DockModel.moveWindowRequest('ABC', target, lua), lua
      ? `hl.dsp.window.move({ window = "address:0xabc", workspace = "${target}", follow = false })`
      : `movetoworkspacesilent ${target},address:0xabc`)
  }
  for (const target of ['', 0, -1, 1.5, 'id:12', 'special:scratch', 'name:',
    'name:bad,dispatch', 'name:bad;dispatch', 'name:bad"', 'name:bad\\',
    'name:bad\n', 'name:bad\tname', 'name:bad\u0000name', 'name:bad\u001fname',
    'name:bad\u007fname', 'name:trailing ', ' name:leading'])
    assert.equal(DockModel.moveWindowRequest('abc', target, lua), '', String(target))
  assert.equal(DockModel.moveWindowRequest('0xabc;bad', 12, lua), '')

  const f = fixture(lua)
  const { actions: a, windows: w, handles: h, requests: r } = f
  const captured = a.captureWorkspaceMove([w[0], w[1], w[0]])
  assert.equal(captured.length, 2)
  assert.equal(captured[0].toplevel, w[0])
  assert.equal(captured[0].address, '0x1')
  assert.equal(a.moveCapturedToplevels(captured, 'id:12'), true)
  assert.equal(r.length, 2)
  assert.ok(r.every(request => !request.includes('address:0x3')),
    'same-app instance on a different card must not join the payload')
  assert.equal(r[0], DockModel.moveWindowRequest('1', 12, lua))
  assert.equal(a.resolveWorkspaceDropTarget('id:12').monitor, 'id:1')
  assert.equal(a.resolveWorkspaceDropTarget('name:Design work').target, 'name:Design work')
  assert.equal(a.resolveWorkspaceDropTarget('name:*').identity, 'name:*')
  r.length = 0
  assert.equal(a.moveCapturedToplevels(captured, 'id:1'), false)
  assert.equal(r.length, 0, 'same-workspace drop is a no-op')
  assert.equal(a.moveCapturedToplevels([captured[0]], 'name:Criação'), true)
  assert.equal(r.pop(), DockModel.moveWindowRequest('1', 'name:Criação', lua))

  // Only the physical IPC workspace proves minimization. A stale object-level
  // relationship or saved origin must not hide a currently visible member.
  h[0].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
  h[0].workspace = { id: 1 }
  h[1].workspace = { name: 'special:smartdock-minimized' }
  a.minimizedOrigins = { '0x1': { workspace: '1', monitor: '0' },
    '0x2': { workspace: '9', monitor: '0' } }
  r.length = 0
  assert.equal(a.moveCapturedToplevels(captured, 'id:12'), true)
  assert.equal(r.length, 1)
  assert.equal(r[0], DockModel.moveWindowRequest('2', 12, lua))
  assert.equal(a.minimizedOrigins['0x1'].workspace, '12')
  assert.equal(a.minimizedOrigins['0x1'].monitor, 'id:1')
  assert.equal(a.minimizedOrigins['0x2'], undefined)
  assert.equal(h[0].lastIpcObject.workspace.name, 'special:smartdock-minimized')
  r.length = 0
  assert.equal(a.moveCapturedToplevels([captured[0]], 'id:12'), false)
  assert.equal(r.length, 0)
  a.minimizedOrigins = {}
  assert.equal(a.moveCapturedToplevels([captured[0]], 'name:Design work'), true)
  assert.equal(a.minimizedOrigins['0x1'].monitor, 'id:1', 'explicit drop establishes missing origin')
  assert.equal(r.length, 0)
}

for (const invalid of ['other', '*', '12', 'id:999', 'id:0', 'id:01', 'special:scratch',
  'name:bad,dispatch', 'name:missing', 'id:12\n']) {
  const { actions: a, windows: w, requests: r } = fixture()
  assert.equal(a.resolveWorkspaceDropTarget(invalid), null)
  assert.equal(a.moveCapturedToplevels(a.captureWorkspaceMove([w[0]]), invalid), false)
  assert.equal(r.length, 0)
}
for (const mutate of [
  f => { f.handles[1].lastIpcObject.pinned = true },
  f => { f.handles[1].address = 'ff' },
  f => { f.handles[1].address = 'unsafe;' },
  f => { f.handles.splice(1, 1) },
  f => { f.workspaces.splice(2, 1) },
  f => { f.workspaces[2].monitor = 'missing-monitor' },
  f => { f.monitors.splice(1, 1) }
]) {
  const f = fixture()
  const captured = f.actions.captureWorkspaceMove(f.windows.slice(0, 2))
  mutate(f)
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), false)
  assert.equal(f.requests.length, 0, 'preflight rejects the whole unsafe surviving payload')
  assert.equal(Object.keys(f.actions.minimizedOrigins).length, 0)
}
{
  const f = fixture()
  f.handles[1].lastIpcObject.pinned = true
  assert.equal(f.actions.captureWorkspaceMove(f.windows.slice(0, 2)).length, 0)
  f.handles[1].lastIpcObject.pinned = false
  f.handles[1].address = f.handles[0].address
  assert.equal(f.actions.captureWorkspaceMove(f.windows.slice(0, 2)).length, 0,
    'ambiguous live address ownership is unsafe')
  assert.equal(f.actions.captureWorkspaceMove([]).length, 0)
  assert.equal(f.actions.captureWorkspaceMove([{}]).length, 0)
}
{
  const f = fixture()
  const captured = f.actions.captureWorkspaceMove(f.windows.slice(0, 2))
  const replacement = { appId: 'editor' }
  f.windows.splice(0, 1, replacement)
  f.handles[0].wayland = replacement
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), true)
  assert.deepEqual(f.requests, [DockModel.moveWindowRequest('2', 12, false)])
  f.windows.splice(1, 1)
  f.requests.length = 0
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), false)
  assert.equal(f.requests.length, 0)
}

// Exercise the production host methods with a bounded scene adapter: no copied
// hit-test or refresh algorithm, no Quickshell/QML module stubs.
{
  const f = fixture()
  let scheduled = 0
  let retargeted = 0
  const cards = [{ present: true, workspaceIdentity: 'id:12', dropCard: {
    visible: true, width: 150, height: 50,
    mapFromItem: (_item, x, y) => ({ x: x - 60, y: y - 20 }) } }]
  const dock = methods('Dock.qml', {
    DockWindowModel, windowActions: f.actions,
    grouped: true, workspaceDragActive: false, workspacePresentationDirty: false,
    workspaceMonitorScope: 'all', dockHyprMonitor: f.monitors[0], hyprMonitors: f.monitors,
    workspaceCards: { count: 1, itemAt: i => cards[i] },
    groupedLayout: { containsScenePoint: p => p.x >= 30 && p.x < 180 && p.y >= 0 && p.y < 100 },
    visibleItemsRefreshTimer: { restart: () => scheduled++ },
    workspaceDrag: { updatePointer: () => retargeted++, pointerScene: { x: 100, y: 30 } }
  })
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), 'id:12')
  assert.equal(dock.workspaceDropTargetAt({ x: 190, y: 30 }), '', 'clipped card region')
  assert.equal(dock.workspaceDropTargetAt({ x: 35, y: 30 }), '', 'gap')
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 80 }), '', 'outside card')
  dock.workspaceMonitorScope = 'current-monitor'
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'live monitor scope')
  dock.workspaceMonitorScope = 'all'
  cards[0].present = false
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'exiting card')
  cards[0].present = true
  f.workspaces.splice(2, 1)
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'frozen card is not live inventory')
  dock.workspaceDragActive = true
  for (let i = 0; i < 5; i++) dock.scheduleVisibleItemsRefresh()
  dock.refreshVisibleItems()
  assert.equal(scheduled, 0)
  assert.equal(retargeted, 5, 'inventory changes still retarget the stationary pointer')
  assert.equal(dock.workspacePresentationDirty, true)
  dock.workspaceDragActive = false
  dock.finishWorkspacePresentation()
  assert.equal(scheduled, 1, 'one queued refresh after session end')
  assert.equal(dock.workspacePresentationDirty, false)
}

// Evaluate the real handler binding through the release latch. Actual native
// pointer delivery/arbitration remains the explicitly separate local gate.
{
  const expression = read('DockItem.qml').match(
    /id: workspaceDragHandler\s+enabled:([\s\S]*?)\n    target:/)?.[1]
  assert.ok(expression, 'workspace gesture binding is present')
  const root = { workspaceDragEnabled: true, presentationActive: true,
    workspaceGestureOwned: false, presentationVisible: true, runningCount: 1,
    sticky: false, workspaceInputSuppressed: false }
  const enabled = (patch = {}, active = false) => vm.runInNewContext(
    `Boolean(${expression})`, { root: { ...root, ...patch }, active })
  assert.equal(enabled(), true)
  assert.equal(enabled({ presentationVisible: false }), false)
  assert.equal(enabled({ sticky: true }), false)
  assert.equal(enabled({ runningCount: 0 }), false)
  assert.equal(enabled({ workspaceDragEnabled: false }, true), false)
  assert.equal(enabled({ presentationActive: false }, true), false)
  assert.equal(enabled({ presentationVisible: false, workspaceInputSuppressed: true }, true), true)
  assert.equal(enabled({ workspaceGestureOwned: true, workspaceInputSuppressed: true }), true,
    'active=false must not disable the handler before the release transition is delivered')

  const transitions = { UngrabExclusive: 1, CancelGrabExclusive: 2, CancelGrabPassive: 3 }
  for (const [transition, state, expected] of [[1, 1, 'finish'], [1, 0, 'cancel'],
    [2, 1, 'cancel'], [3, 1, 'cancel']]) {
    const calls = []
    const item = methods('DockItem.qml', { PointerDevice: transitions,
      EventPoint: { Released: 1 }, workspaceDrag: {
        finish: point => { calls.push(['finish', point]); item.workspaceDrag.sourceItem = null },
        cancel: () => { calls.push(['cancel']); item.workspaceDrag.sourceItem = null }
      } })
    item.workspaceDrag.sourceItem = item
    const point = { state, scenePosition: { x: 91, y: 37 } }
    item.workspaceGrabChanged(transition, point)
    item.workspaceGrabChanged(transition, point)
    assert.equal(calls.length, 1)
    assert.equal(calls[0][0], expected)
    if (expected === 'finish') assert.equal(calls[0][1], point.scenePosition)
  }
}

// A known non-sticky fallback source is safe: the command uses its exact
// address and the destination is independently validated, never guessed.
for (const workspace of [{}, { id: -99, name: 'special:scratch' }]) {
  const f = fixture()
  f.handles[0].lastIpcObject.workspace = workspace
  const captured = f.actions.captureWorkspaceMove([f.windows[0]])
  assert.equal(captured.length, 1, 'resolvable Other windows source remains draggable')
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), true)
  assert.deepEqual(f.requests, [DockModel.moveWindowRequest('1', 12, false)])
}
console.log('workspace dragging production actions, targets and refresh: PASS')
