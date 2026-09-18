import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const read = name => fs.readFileSync(new URL(`../components/${name}`, import.meta.url), 'utf8')
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(read(name).replace(/^\.(pragma|import).*$/gm, ''), scope, { filename: name })
  return scope
}
function methods(name, properties) {
  const scope = vm.createContext(properties)
  scope.root = scope
  vm.runInContext((read(name).match(/^  function [\s\S]*?^  }/gm) || []).join('\n'), scope,
    { filename: name })
  return scope
}

const DockModel = model('DockModel.js')
const DockWindowModel = model('DockWindowModel.js', { DockModel })
const DockMenuModel = model('DockMenuModel.js')
const FullscreenModel = model('DockFullscreenModel.js')
const WorkspaceGroupModel = model('DockWorkspaceGroupModel.js', { DockModel })

function fixture(usingLua = false) {
  const A = { appId: 'editor', title: 'A' }
  const B = { appId: 'editor', title: 'B' }
  const windows = [A, B]
  const handles = windows.map((wayland, index) => ({
    wayland, address: index === 0 ? 'a1' : 'b2',
    lastIpcObject: { workspace: { id: 3, name: '3' }, monitor: 0, pinned: false }
  }))
  const monitors = [{ id: 0, name: 'DP-1' }, { id: 1, name: 'DP-2' }]
  const workspaces = [
    { id: 3, name: '3', monitorID: 0 },
    { id: 4, name: '4', monitorID: 1 },
    { id: -1337, name: 'project', monitorID: 1 }
  ]
  const requests = []
  const detached = []
  const Hyprland = {
    toplevels: { values: handles }, monitors: { values: monitors },
    workspaces: { values: workspaces }, focusedWorkspace: workspaces[0],
    usingLua, dispatch: request => requests.push(request)
  }
  const actions = methods('DockWindowActions.qml', {
    DockModel, DockWindowModel, Hyprland,
    ToplevelManager: { toplevels: { values: windows }, activeToplevel: null },
    Quickshell: { execDetached: args => detached.push(args) },
    minimizedWorkspace: 'special:smartdock-minimized', minimizedOrigins: {},
    windowWorkspacePins: {}, workspaceMonitorPins: {}
  })
  const groups = [{ desktopId: 'editor', workspace: 'id:3' }]
  const controller = { settings: { workspaceGroups: groups } }
  const contextActions = methods('DockContextActionController.qml', {
    FullscreenModel, Hyprland, windowActions: actions,
    applicationMutationController: controller, runtimeMode: 'plugin', instanceId: '42'
  })
  const menu = methods('DockContextMenu.qml', {
    DockModel, DockMenuModel, FullscreenModel, WorkspaceGroupModel,
    Hyprland, windowActions: actions, contextActions,
    DesktopEntries: { applications: { values: [{ id: 'editor', name: 'Editor' }] } },
    Qt: { callLater() {} }, menuSurface: { forceActiveFocus() {} },
    applicationMutationController: controller, desktopId: 'editor', applicationName: 'Editor',
    workspaceGroups: groups, anchorItem: {}, runningToplevels: windows.slice(),
    pinnedItem: false, controlItem: false, originOnly: true,
    interfaceAnimationsEnabled: false, visible: false, openGeneration: 0,
    page: 'app', pageStack: [], targetContexts: [], pageTarget: null,
    activeMenuIndex: -1, groupCandidateSnapshot: [], openedWorkspaceGroupsSignature: '',
    feedbackTitle: '', feedbackText: '', pendingMutationAction: '', pendingMutationLabel: '',
    copyProfileDirectory: ''
  })
  // Model-only fixtures mirror the QML bindings without replacing action logic.
  Object.defineProperties(menu, {
    pageActions: { get() { return menu.decorateWithFeedback(menu.buildPageActions()) } },
    visibleWindowCount: { get() { return DockModel.windowStateCounts(menu.buildWindowStates()).visible } },
    minimizedCount: { get() { return DockModel.windowStateCounts(menu.buildWindowStates()).minimized } }
  })
  return { A, B, windows, handles, monitors, workspaces, requests, detached, actions, menu, groups }
}

function choose(menu, command) {
  const records = menu.pageActions
  const index = records.findIndex(record => record.kind === 'action' && record.command === command)
  assert.notEqual(index, -1, `${menu.page} page must expose ${command}`)
  assert.notEqual(records[index].enabled, false, `${command} must be enabled`)
  assert.equal(menu.dispatchAction(records[index], index), true)
}

for (const departure of ['close', 'move']) {
  test(`saved group keeps exact window actions after a sibling ${departure}`, () => {
    const f = fixture()
    const { A, B, menu, handles, windows, groups } = f
    menu.open()
    assert.equal(menu.page, 'app')
    assert.equal(menu.targetContexts.length, 2)
    menu.dismiss()
    if (departure === 'close') {
      windows.splice(windows.indexOf(B), 1)
      handles.splice(1, 1)
    } else {
      handles[1].lastIpcObject.workspace = { id: 4, name: '4' }
      handles[1].lastIpcObject.monitor = 1
    }
    menu.runningToplevels = [A]
    menu.open()
    assert.equal(menu.page, 'app', 'saved single-member groups retain their group identity')
    assert.ok(menu.pageActions.some(record => record.command === 'ungroup-windows'))
    choose(menu, 'open-chooser-page')
    assert.equal(menu.page, 'chooser')
    const choices = menu.pageActions.filter(record => record.command === 'open-window-page')
    assert.equal(choices.length, 1)
    assert.equal(choices[0].targetContext.toplevel, A)
    assert.equal(choices[0].targetContext.address, '0xa1')
    choose(menu, 'open-window-page')
    assert.equal(menu.page, 'window')
    for (const command of [
      'minimize-restore', 'open-workspaces-page', 'pin-window-workspace',
      'fullscreen-keep-bars', 'fullscreen-hide-bars', 'close-window'
    ]) {
      const record = menu.pageActions.find(value => value.command === command)
      assert.ok(record, `remaining window exposes ${command}`)
      assert.equal(record.enabled, true)
      assert.equal(record.targetContext.toplevel, A)
      assert.equal(record.targetContext.address, '0xa1')
    }
    assert.ok(menu.pageActions.some(record => record.command === 'ungroup-windows'))
    assert.equal(menu.goBack(), true)
    assert.equal(menu.page, 'chooser')
    assert.equal(menu.goBack(), true)
    assert.equal(menu.page, 'app')
    assert.deepEqual(groups, [{ desktopId: 'editor', workspace: 'id:3' }])
    assert.deepEqual(f.requests, [], 'navigation never activates or moves a window')
    assert.deepEqual(f.detached, [])
  })
}

test('empty launchers and ungrouped single windows retain their initial pages', () => {
  const { menu, A } = fixture()
  menu.runningToplevels = []
  menu.open()
  assert.equal(menu.page, 'app')
  assert.equal(menu.pageActions.some(record => record.command === 'open-chooser-page'), false)
  menu.dismiss()
  menu.workspaceGroups = []
  menu.runningToplevels = [A]
  menu.open()
  assert.equal(menu.page, 'window')
})

test('single-member chooser rejects an address replacement before activation', () => {
  const { menu, A, handles, requests } = fixture()
  menu.runningToplevels = [A]
  menu.open()
  choose(menu, 'open-chooser-page')
  const records = menu.pageActions
  const index = records.findIndex(record => record.command === 'open-window-page')
  assert.notEqual(index, -1)
  handles[0].address = 'c3'
  assert.equal(menu.dispatchAction(records[index], index), false)
  assert.equal(menu.visible, false)
  assert.deepEqual(requests, [])
})

function minimizeFirst(f) {
  assert.equal(f.actions.minimizeToplevel(f.A, true), true)
  f.handles[0].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
  f.requests.length = 0
  f.menu.runningToplevels = [f.A]
  f.menu.open()
}

for (const usingLua of [false, true]) {
  for (const destination of [4, 'name:project']) {
    test(`minimized menu move tracks destination monitor (${destination}, Lua=${usingLua})`, () => {
      const f = fixture(usingLua)
      minimizeFirst(f)
      const target = f.menu.targetContexts[0]
      assert.equal(f.menu.moveTargetToWorkspace(target, destination), true)
      const origin = f.actions.originFor(f.A)
      assert.equal(origin.workspace, String(destination))
      assert.equal(origin.monitor, 'id:1', 'record the destination monitor, never the source')
      assert.equal(f.actions.isMinimized(f.A), true)
      assert.deepEqual(f.requests, [], 'moving a minimized window only updates its origin')
      assert.deepEqual(f.detached, [])
      for (const scope of ['monitor', 'workspace-monitor']) {
        const source = DockWindowModel.windowScopeContext(scope, destination, f.monitors[0], false)
        const targetScope = DockWindowModel.windowScopeContext(scope, destination, f.monitors[1], false)
        assert.deepEqual(Array.from(DockWindowModel.filterToplevelsByScope(
          [f.A], f.handles, f.actions.minimizedOrigins, source)), [])
        assert.deepEqual(Array.from(DockWindowModel.filterToplevelsByScope(
          [f.A], f.handles, f.actions.minimizedOrigins, targetScope)), [f.A])
      }
      assert.equal(f.actions.restoreToplevel(f.A, true), true)
      assert.deepEqual(f.requests, [DockModel.restoreWindowRequest('0xa1', destination, usingLua)])
    })
  }
}

for (const unavailable of ['workspace', 'monitor', 'conflicting-owner']) {
  test(`minimized menu move preserves origin when destination has unavailable ${unavailable}`, () => {
    const f = fixture()
    minimizeFirst(f)
    const before = JSON.stringify(f.actions.minimizedOrigins)
    if (unavailable === 'workspace') f.workspaces.splice(1, 1)
    else if (unavailable === 'monitor') f.monitors.splice(1, 1)
    else f.workspaces.push({ id: 4, name: '4', monitorID: 0 })
    assert.equal(f.menu.moveTargetToWorkspace(f.menu.targetContexts[0], 4), false)
    assert.equal(JSON.stringify(f.actions.minimizedOrigins), before)
    assert.deepEqual(f.requests, [])
    assert.deepEqual(f.detached, [])
  })
}

test('minimized window pins and same-workspace moves preserve the recorded origin', () => {
  const f = fixture()
  assert.equal(f.actions.pinWindowToWorkspace(f.A), true)
  minimizeFirst(f)
  const before = JSON.stringify(f.actions.minimizedOrigins)
  assert.equal(f.menu.moveTargetToWorkspace(f.menu.targetContexts[0], 4), false)
  assert.equal(f.menu.moveTargetToWorkspace(f.menu.targetContexts[0], 3), false)
  assert.equal(JSON.stringify(f.actions.minimizedOrigins), before)
  assert.equal(f.actions.windowWorkspacePin(f.A).workspace, 'id:3')
  assert.deepEqual(f.requests, [])
})

test('visible windows can still move to a not-yet-created numeric workspace', () => {
  const f = fixture()
  assert.equal(f.actions.moveToplevelToWorkspace(f.A, '0xa1', 9), true)
  assert.deepEqual(f.requests, [DockModel.moveWindowRequest('0xa1', 9, false)])
})

test('pin-strip menus keep Unpin enabled path and omit Hide App from Dock', () => {
  const f = fixture()
  f.menu.pinnedItem = true
  f.menu.anchorItem = { desktopId: 'editor', pinStripOwned: true }
  const strip = f.menu.applicationActionRecords('app', null)
  const unpin = strip.find(record => record.command === 'unpin-app')
  assert.ok(unpin, 'pin-strip menu must expose Unpin from Dock')
  assert.notEqual(unpin.enabled, false, 'Unpin must be enabled when desktopId is set')
  assert.ok(!strip.some(record => record.command === 'hide-app'),
    'pin-strip menu must not expose Hide App from Dock')

  f.menu.anchorItem = { desktopId: 'editor' }
  const hierarchy = f.menu.applicationActionRecords('app', null)
  assert.ok(hierarchy.some(record => record.command === 'hide-app'),
    'hierarchy app menus still expose Hide App from Dock')
})

test('successful unpin dismisses the context menu', () => {
  const f = fixture()
  f.menu.visible = true
  f.menu.pinnedItem = true
  f.menu.anchorItem = { desktopId: 'editor', pinStripOwned: true }
  f.menu.applicationMutationController.unpinApplication = () => ({
    ok: true,
    data: { applied: true, persisted: true, writeState: 'saved' }
  })
  assert.equal(f.menu.dispatchAction({
    kind: 'action', command: 'unpin-app', enabled: true, targetContext: null
  }, 0), true)
  assert.equal(f.menu.visible, false, 'menu must close after successful Unpin')
})

test('pin-strip shortcut menu omits window choose/minimize even if app would be running', () => {
  const f = fixture()
  f.menu.sidebarMode = true
  f.menu.pinnedItem = true
  f.menu.anchorItem = { desktopId: 'editor', pinStripOwned: true }
  // openContext clears members for pinStripOwned; menu must not grow window actions.
  f.menu.runningToplevels = []
  f.menu.open()
  const commands = f.menu.pageActions
    .filter(record => record.kind === 'action')
    .map(record => record.command)
  assert.ok(commands.includes('unpin-app'))
  assert.ok(commands.includes('open-new'))
  assert.ok(commands.includes('copy-icon-command'))
  assert.ok(!commands.includes('open-chooser-page'))
  assert.ok(!commands.includes('minimize-visible'))
  assert.ok(!commands.includes('close-represented'))
  assert.ok(!commands.includes('hide-app'))
  assert.ok(f.menu.pageActions.some(record =>
    record.kind === 'header' && String(record.subtitle || '').includes('No open windows')))
})
