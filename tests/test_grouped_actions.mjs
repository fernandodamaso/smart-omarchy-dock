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
// Execute the real QML method bodies; only compositor transport is substituted.
function methods(file, properties) {
  const scope = vm.createContext(properties)
  scope.root = scope
  const bodies = read(file).match(/^  function [\s\S]*?^  }/gm) || []
  vm.runInContext(bodies.join('\n'), scope, { filename: file })
  return scope
}
const windows = [{}, {}]
const handles = windows.map((wayland, i) => ({ wayland, address: String(i + 1),
  lastIpcObject: { workspace: { name: 'special:smartdock-minimized' }, monitor: 0 } }))
const requests = []
const batches = []
const actions = methods('DockWindowActions.qml', {
  DockModel, DockWindowModel,
  minimizedOrigins: {}, minimizedWorkspace: 'special:smartdock-minimized',
  activeToplevel: windows[0],
  ToplevelManager: { toplevels: { values: windows } },
  Quickshell: { execDetached: command => batches.push(command) },
  Hyprland: { toplevels: { values: handles }, focusedWorkspace: { id: 3 },
    usingLua: false, dispatch: request => requests.push(request) }
})
const item = methods('DockItem.qml', { DockModel, DockWindowModel, windowActions: actions,
  originOnly: true, runningToplevels: windows, runningCount: 2, lastActivatedToplevel: -1 })

Object.assign(item, { entry: { name: 'Google Chrome' }, desktopId: 'google-chrome',
  browserProfileEntry: { name: 'Work' }, focused: false, runningCount: 1,
  sticky: false, minimizedCount: 0 })
assert.equal(item.tooltipLabel(), 'Google Chrome - Work — running application')
item.browserProfileEntry = { name: '' }
assert.equal(item.tooltipLabel(), 'Google Chrome — running application')
const preview = methods('DockWindowPreview.qml', { windowActions: actions, originOnly: true })
const menu = methods('DockContextMenu.qml', { windowActions: actions, originOnly: true,
  selectedToplevel: windows[0], selectedMinimized: true })
menu.dismiss = () => {}
for (const origin of [undefined, { workspace: 'name:bad,dispatch' }]) {
  actions.minimizedOrigins = origin ? { '0x1': origin, '0x2': origin } : {}
  requests.length = 0
  for (const run of [
    () => actions.activateToplevel(windows[0], true),
    () => actions.focusToplevels(windows, true),
    () => actions.cycleToplevels(windows, 1, windows[0], true),
    () => actions.minimizeRestoreToplevels(windows, true),
    () => item.dispatchApplicationAction('focus-or-launch'),
    () => item.dispatchApplicationAction('cycle-windows', { direction: 1 }),
    () => item.dispatchApplicationAction('minimize-restore'),
    () => preview.activateToplevel(windows[0]),
    () => menu.minimizeRestoreSelected()
  ]) assert.equal(run(), false)
  assert.equal(requests.length, 0, 'grouped routes must never dispatch without a valid origin')
}
assert.equal(actions.activateToplevel(windows[0]), false, 'invalid flat origin remains rejected')
assert.equal(requests.length, 0)
actions.minimizedOrigins = {}
assert.equal(actions.activateToplevel(windows[0]), true)
assert.equal(requests.pop(), 'movetoworkspace 3,address:0x1')
actions.minimizedOrigins = { '0x1': { workspace: 'name:Design work', monitor: '0' } }
assert.equal(actions.restoreToplevel(windows[0], true), true)
assert.equal(requests.pop(), 'movetoworkspace name:Design work,address:0x1')
handles[0].lastIpcObject.workspace = {}
requests.length = 0
assert.equal(actions.minimizeToplevel(windows[0], true), false)
assert.equal(requests.length, 0)
assert.equal(Object.keys(actions.minimizedOrigins).length, 0, 'no guessed minimize origin')
assert.equal(actions.minimizeToplevel(windows[0]), true)
assert.equal(actions.minimizedOrigins['0x1'].workspace, '3')

const dropCards = [{ id: 'drop-1' }, { id: 'drop-3' }]
const cards = [
  { active: true, present: true, workspaceIdentity: 'id:1', headerWidth: 30,
    dropCard: dropCards[0] },
  { active: true, present: true, workspaceIdentity: 'id:3', headerWidth: 45,
    dropCard: dropCards[1] }
]
const revealed = []
const hyprland = actions.Hyprland
const dock = methods('Dock.qml', {
  grouped: true, activeCardIdentity: 'id:3',
  workspaceCards: { count: cards.length, itemAt: i => cards[i] },
  groupedLayout: { ensureVisible: (card, width) => revealed.push([card, width]) },
  DockModel, DockWindowModel, Hyprland: hyprland, windowActions: actions,
  dockHyprMonitor: { id: 0, name: 'DP-1' }
})
dock.revealActiveWorkspace()
assert.deepEqual(revealed, [[dropCards[1], 45]],
  'workspace switch reveals only the globally focused actual card header when multiple cards are active')

// Unmodified clicks focus in place; Ctrl+click keeps workspace-to-monitor pull.
preview.dismissImmediately = () => {}
item.applicationActions = DockModel.normalizeApplicationActionConfig({
  clickAction: 'focus-or-launch', middleClickAction: 'focus-or-launch',
  scrollAction: 'cycle-windows' })
item.activationMonitor = 'id:0'
preview.activationMonitor = 'id:0'
item.runningToplevels = [windows[0]]
item.runningCount = 1
actions.minimizedOrigins = {}
function expectRequests(actual, expected, label) {
  assert.deepEqual(actual, expected, label)
}
function clearSubmissions() {
  requests.length = 0
  batches.length = 0
}
function expectSequence(steps, usingLua, label) {
  if (usingLua) {
    expectRequests(requests, [
      `function() ${steps.map(step => `hl.dispatch(${step})`).join('; ')} end`
    ], label)
    expectRequests(batches, [], `${label} does not spawn hyprctl`)
  } else {
    expectRequests(requests, [], `${label} does not race IPC sockets`)
    expectRequests(batches.map(command => Array.from(command)), [[
      'hyprctl', '--batch', steps.map(step => `dispatch ${step}`).join('; ')
    ]], label)
  }
}
hyprland.usingLua = true
handles[0].lastIpcObject = { workspace: { id: 9 }, monitor: 1 }
clearSubmissions()
assert.equal(item.dispatchPointerAction('left', {}), true)
expectRequests(requests, [
  'hl.dsp.focus({ window = "address:0x1" })'
], 'unmodified icon activation focuses in place')
clearSubmissions()
assert.equal(item.dispatchPointerAction('left', { control: true }), true)
expectRequests(requests, [
  'function() hl.dispatch(hl.dsp.focus({ workspace = "9" })); '
    + 'hl.dispatch(hl.dsp.workspace.move({ workspace = "9", monitor = "0" })); '
    + 'hl.dispatch(hl.dsp.focus({ workspace = "9" })); '
    + 'hl.dispatch(hl.dsp.focus({ window = "address:0x1" })) end'
], 'Ctrl+click cross-monitor activation is one ordered compositor submission')
for (const usingLua of [false, true]) {
  hyprland.usingLua = usingLua
  const moveWorkspace = target => usingLua
    ? `hl.dsp.workspace.move({ workspace = "${target}", monitor = "0" })`
    : `moveworkspacetomonitor ${target} 0`
  const focusWorkspace = target => usingLua
    ? `hl.dsp.focus({ workspace = "${target}" })`
    : `workspace ${target}`
  const moveCurrentWorkspace = usingLua
    ? 'hl.dsp.workspace.move({ monitor = "0" })'
    : 'movecurrentworkspacetomonitor 0'
  handles[0].lastIpcObject = { workspace: { id: 9 }, monitor: 1 }
  clearSubmissions()
  assert.equal(actions.activateToplevel(windows[0], true, 'id:0'), true)
  expectSequence([
    focusWorkspace('9'), moveWorkspace('9'), focusWorkspace('9'),
    usingLua
      ? 'hl.dsp.focus({ window = "address:0x1" })'
      : 'focuswindow address:0x1'
  ], usingLua, 'grouped Ctrl+click pulls workspace then focuses exact window')
  handles[0].lastIpcObject = { workspace: { id: 9 }, monitor: 0 }
  clearSubmissions()
  assert.equal(actions.activateToplevel(windows[0], true, 'id:0'), true)
  expectSequence([
    usingLua
      ? 'hl.dsp.focus({ window = "address:0x1" })'
      : 'focuswindow address:0x1'
  ], usingLua, 'same-monitor grouped activation focuses only')
  clearSubmissions()
  assert.equal(actions.workspaceOnMonitorRequests('9', 'id:0').length, 3)
  expectRequests(requests, [], 'building grouped workspace request sequence is pure')
  expectRequests(batches, [], 'building grouped workspace request sequence spawns nothing')
  const workspaceSteps = actions.workspaceOnMonitorRequests('9', 'id:0')
  assert.deepEqual(Array.from(workspaceSteps), [
    focusWorkspace('9'), moveWorkspace('9'), focusWorkspace('9')
  ])
  clearSubmissions()
  assert.equal(actions.currentWorkspaceOnMonitorRequests('id:0').length, 2)
  assert.deepEqual(Array.from(actions.currentWorkspaceOnMonitorRequests('id:0')), [
    moveCurrentWorkspace, usingLua ? 'hl.dsp.focus({ monitor = "0" })' : 'focusmonitor 0'
  ])
}

console.log('grouped action routes and compact geometry: PASS')
