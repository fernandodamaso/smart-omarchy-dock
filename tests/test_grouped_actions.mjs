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

// Execute the geometry bindings from QML. This catches trimming the logical
// layout with the surface, which silently reintroduces the trailing gap.
function binding(block, name, scope) {
  const expression = block.match(new RegExp(`^( *)${name}: ([^\\n]*(?:\\n\\1 +[^\\n]+)*)`, 'm'))?.[2]
  assert.ok(expression, `missing binding ${name}`)
  return vm.runInNewContext(expression, scope)
}
const dockSource = read('Dock.qml')
const backgroundSource = dockSource.split('id: dockBackground')[1]
const layoutSource = dockSource.split('id: dockLayout')[1]
const groupedSource = dockSource.split('id: groupedLayout')[1]
function dockGeometry(options = {}) {
  const root = { iconSize: 24, magnification: 1.2, fullscreenModeActive: false,
    grouped: true, vertical: false, fullLength: false, showTrash: false,
    screen: { width: 1920 }, ...options }
  const groupedLayout = { contentPadding: paddingFor(root) }
  groupedLayout.desiredWidth = binding(read('DockWorkspaceLayout.qml'),
    'readonly property real desiredWidth', { content: { implicitWidth: 300 }, ...groupedLayout })
  Object.assign(root, { itemSize: root.iconSize + (root.grouped ? 14 : 22),
    mainPadding: root.grouped ? 8 : 16, appMainExtent: groupedLayout.desiredWidth,
    trailingMainExtent: root.showTrash ? 70 : root.grouped ? 0 : 90, crossExtent: 200 })
  const scope = { root, groupedLayout, ...root }
  root.compactMainExtent = binding(dockSource, 'readonly property int compactMainExtent', scope)
  // Bind any surface geometry properties in source order, as QML dependencies.
  for (const name of ['groupedSurfaceTrim', 'groupedSurfaceGutter', 'compactGroupedSurface', 'compactPanelExtent']) {
    const declaration = `readonly property ${name === 'compactGroupedSurface' ? 'bool' : 'int'} ${name}`
    if (dockSource.includes(declaration)) {
      root[name] = binding(dockSource, declaration, { ...scope, ...root })
    }
  }
  const panelWidth = root.fullLength ? root.screen.width
    : binding(dockSource, 'implicitWidth', { ...scope, ...root })
  const parent = { width: panelWidth }
  const surfaceWidth = binding(backgroundSource, 'width', { root, parent })
  const surfaceX = binding(backgroundSource, 'x', { root, parent, width: surfaceWidth })
  const layoutWidth = layoutSource.trimStart().startsWith('anchors.fill: parent') ? surfaceWidth
    : binding(layoutSource, 'width', { root, parent: { width: surfaceWidth } })
  const dockLayout = { width: layoutWidth, height: 200 }
  for (const name of ['leadingEnd', 'trailingStart', 'centeredAppStart', 'appStart'])
    dockLayout[name] = binding(layoutSource, `readonly property real ${name}`, { root, ...dockLayout })
  const viewportX = binding(groupedSource, 'x', { dockLayout })
  const viewportWidth = binding(groupedSource, 'width', { dockLayout, x: viewportX,
    desiredWidth: groupedLayout.desiredWidth })
  return { root, panelWidth, surfaceWidth, surfaceX, layoutWidth, viewportX, viewportWidth,
    visibleRight: surfaceX + viewportX + groupedLayout.contentPadding + 300,
    desiredWidth: groupedLayout.desiredWidth }
}
for (const iconSize of [24, 31, 64, 96]) for (const magnification of [1, 1.2, 2])
  for (const fullscreenModeActive of [false, true]) {
    const g = dockGeometry({ iconSize, magnification, fullscreenModeActive })
    assert.equal(g.surfaceX + g.surfaceWidth - g.visibleRight, 4, 'visible right inset is exactly 4px')
    assert.equal(g.surfaceX * 2 + g.surfaceWidth, g.panelWidth, 'visible surface is centered')
    assert.equal(g.layoutWidth, g.root.compactMainExtent, 'logical layout retains its original width')
    assert.equal(g.viewportWidth, g.desiredWidth, 'magnification viewport is not reduced')
    assert.ok(g.surfaceX >= 0 && g.surfaceX + g.surfaceWidth <= g.panelWidth)
    assert.ok(g.surfaceX + g.viewportX + g.viewportWidth <= g.panelWidth, 'viewport fits outer panel')
    if (g.root.groupedSurfaceGutter > 0) {
      const dockLayout = { x: g.surfaceX, width: g.layoutWidth }
      const dockBackground = { x: g.surfaceX, width: g.surfaceWidth }
      const pointerParent = binding(dockSource.split('id: pointer')[1], 'parent',
        { root: g.root, dockLayout, dockBackground })
      const pointX = g.viewportX + g.viewportWidth - 1
      const pointer = { hovered: pointX < pointerParent.width,
        point: { position: { x: pointX, y: 30 } } }
      assert.ok(pointer.hovered, 'tracking covers transparent magnification allowance')
      assert.equal(binding(dockSource, 'readonly property real pointerPosition',
        { pointer, vertical: false }), pointX, 'control pointer retains logical origin')
      const appParentX = g.surfaceX + g.viewportX + paddingFor(g.root)
      const parent = { mapFromItem: (source, x, y) => ({ x: source.x + x - appParentX, y }) }
      assert.equal(binding(dockSource.split('component AppIcon:')[1], 'pointerPosition',
        { pointer, root: g.root, parent, dockLayout, dockBackground }),
      g.viewportWidth - paddingFor(g.root) - 1, 'app pointer mapping includes gutter exactly once')
    }
  }
for (const options of [{ grouped: false }, { showTrash: true },
  { fullLength: true }, { screen: { width: 200 } },
  { iconSize: 96, magnification: 2, screen: { width: 540 } }]) {
  const g = dockGeometry(options)
  assert.equal(g.surfaceX, 0, 'legacy geometry remains for other modes and screen overflow')
  assert.equal(g.surfaceWidth, g.panelWidth)
  assert.ok(g.viewportWidth >= 0)
}

const verticalBackground = {}
assert.equal(binding(dockSource.split('id: pointer')[1], 'parent',
  { root: { vertical: true }, dockBackground: verticalBackground, dockLayout: {} }), verticalBackground,
'Vertical pointer parent is unchanged')
console.log('grouped visible surface and magnification bounds: PASS')
