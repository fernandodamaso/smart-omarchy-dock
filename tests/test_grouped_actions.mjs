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
const actions = methods('DockWindowActions.qml', {
  DockModel, DockWindowModel,
  minimizedOrigins: {}, minimizedWorkspace: 'special:smartdock-minimized',
  activeToplevel: windows[0],
  ToplevelManager: { toplevels: { values: windows } },
  Hyprland: { toplevels: { values: handles }, focusedWorkspace: { id: 3 },
    usingLua: false, dispatch: request => requests.push(request) }
})
const item = methods('DockItem.qml', { DockModel, DockWindowModel, windowActions: actions,
  originOnly: true, runningToplevels: windows, runningCount: 2, lastActivatedToplevel: -1 })
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

const cards = [{ active: false }, { active: true, headerWidth: 45 }]
const revealed = []
const dock = methods('Dock.qml', {
  grouped: true, workspaceCards: { count: cards.length, itemAt: i => cards[i] },
  groupedLayout: { ensureVisible: (card, width) => revealed.push([card, width]) }
})
dock.revealActiveWorkspace()
assert.deepEqual(revealed, [[cards[1], 45]], 'workspace switch reveals the active header')

// Mirrored header and app routes focus the remote target without relocating it.
preview.dismissImmediately = () => {}
item.runningToplevels = [windows[0]]
item.runningCount = 1
actions.minimizedOrigins = {}
const headerBody = read('Dock.qml').match(/onActivated: \{([\s\S]*?)\n            }/)[1]
for (const usingLua of [false, true]) {
  requests.length = 0
  vm.runInNewContext(headerBody, { DockModel,
    modelData: { activationTarget: 'name:Design work' },
    Hyprland: { usingLua, dispatch: request => requests.push(request) } })
  assert.equal(requests.pop(), usingLua
    ? 'hl.dsp.focus({ workspace = "name:Design work" })' : 'workspace name:Design work')
  actions.Hyprland.usingLua = usingLua
  handles[0].lastIpcObject = { workspace: { id: 9 }, monitor: 1 }
  requests.length = 0
  assert.equal(item.dispatchApplicationAction('focus-or-launch'), true)
  assert.equal(preview.activateToplevel(windows[0]), true)
  assert.equal(requests.length, 2)
  assert.equal(requests.every(request => request === (usingLua
    ? 'hl.dsp.focus({ window = "address:0x1" })' : 'focuswindow address:0x1')), true)
}
assert.equal(read('Dock.qml').includes('indexOf(modelData)'), false)
assert.equal(read('Dock.qml').includes('workspaceScopeKey(root.screen.name, modelData.presentationId)'), true)
// Evaluate the production marker bindings: grouped magnification must not push
// the focus underline outside the compact surface, even with zero edge margin.
const markerBlock = read('DockItem.qml').split('id: applicationStateIndicator')[1].split('\n    }')[0]
function markerBinding(name, fallback, scope) {
  const expression = markerBlock.match(new RegExp(`^      ${name}: (.+)$`, 'm'))?.[1]
  return expression ? vm.runInNewContext(expression, scope) : fallback
}
for (const iconSize of [24, 31, 64, 96]) for (const position of ['top', 'bottom']) {
  const slot = { originOnly: true }
  const iconContainer = { x: 7, y: 10, opacity: 0.4 }
  const geometry = DockModel.applicationStateIndicatorGeometry(position, iconSize, iconSize, true, true)
  const scope = { root: slot, iconContainer, indicatorGeometry: geometry }
  const markerParent = markerBinding('parent', iconContainer, scope)
  const markerY = markerBinding('y', geometry.y, scope)
  for (const magnification of [1, 2]) {
    const scale = markerParent === iconContainer ? magnification : 1
    const origin = position === 'bottom' ? iconSize : 0
    const top = markerParent === iconContainer
      ? iconContainer.y + origin + (markerY - origin) * scale : markerY
    // Actual source surface height; the item has six extra cross-axis pixels.
    const backgroundHeight = vm.runInNewContext(read('Dock.qml').split('id: dockBackground')[1].match(/height: root.vertical \? parent.height : (.+)/)[1],
      { root: { iconSize, grouped: true } })
    const itemHeight = iconSize + 20
    assert.ok(top + (backgroundHeight - itemHeight) / 2 >= 0, 'top marker fits compact surface')
    assert.ok(top + geometry.height * scale <= (backgroundHeight + itemHeight) / 2,
      'bottom marker fits compact surface')
  }
  assert.equal(markerBinding('opacity', 1, scope), 0.4, 'reparented marker retains fullscreen opacity')
}
// Trailing whitespace stays compact, while fullscreen emphasis still fits at
// maximum magnification. Evaluate the host binding rather than a copied formula.
const paddingExpression = read('Dock.qml').split('id: groupedLayout')[1]
  .match(/contentPadding: ([\s\S]*?)\n        foreground:/)[1]
const paddingFor = root => vm.runInNewContext(paddingExpression, { root, DockModel })
assert.ok(paddingFor({ iconSize: 24, magnification: 1.2, fullscreenModeActive: false }) <= 4,
  'default grouped spacing must not add redundant viewport padding')
assert.ok(paddingFor({ iconSize: 24, magnification: 2, fullscreenModeActive: false }) + 7 >= 12 + 8,
  'global launcher hover tile fits its slot inset plus viewport allowance')
const largeOwnerScale = DockModel.fullscreenIconPresentation(true, true, false).scale * 2
const largeOwnerOverhang = 96 * (largeOwnerScale - 1) / 2
assert.ok(paddingFor({ iconSize: 96, magnification: 2, fullscreenModeActive: true }) + 13 >= largeOwnerOverhang,
  'fullscreen artwork fits the trailing card inset plus viewport allowance')
console.log('grouped action routes and compact geometry: PASS')
