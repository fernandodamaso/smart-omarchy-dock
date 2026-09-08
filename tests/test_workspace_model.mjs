import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

function load(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(fs.readFileSync(new URL(`../components/${name}.js`, import.meta.url), 'utf8')
    .replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}
const DockModel = load('DockModel')
const DockWindowModel = load('DockWindowModel', { DockModel })
const file = new URL('../components/DockWorkspaceModel.js', import.meta.url)
const model = fs.existsSync(file) ? load('DockWorkspaceModel', { DockModel, DockWindowModel }) : {}
assert.equal(typeof model.buildWorkspacePresentation, 'function', 'workspace composer exists')
const windows = [1, 2, 3].map(id => ({ appId: 'chrome', id }))
const handles = windows.map((wayland, i) => ({ wayland, address: String(i + 1),
  lastIpcObject: { workspace: { id: i ? 2 : 1 }, monitor: 0 } }))
const workspaces = [2, 1].map(id => ({ id, monitorID: 0 }))
const context = { monitorScope: 'current-monitor', monitor: 'id:0', activeWorkspace: 'id:1', groupWindows: true }
function build(hidden = [], grouped = true) {
  const apps = DockModel.buildVisibleItems(['closed', 'chrome'], windows, [], handles, false, grouped, hidden)
  const records = windows.map(toplevel => ({ toplevel,
    ...DockWindowModel.locationForToplevel(toplevel, handles, {}) }))
  const before = JSON.stringify({ apps, records, workspaces })
  const result = model.buildWorkspacePresentation(apps, records, workspaces, { ...context, groupWindows: grouped })
  assert.equal(JSON.stringify({ apps, records, workspaces }), before, 'inputs immutable')
  return result
}
let result = build()
const movingRecords = windows.map((toplevel, i) => ({ toplevel,
  ...DockWindowModel.locationForToplevel(toplevel, handles, {}),
  workspace: i === 0 ? 'id:8' : 'id:2' }))
const movingPresentation = model.buildWorkspacePresentation(
  DockModel.buildVisibleItems([], windows, [], handles, false, true, []),
  movingRecords, workspaces, context)
assert.equal(movingPresentation.fallbackItems.length, 0,
  'known moved windows must not flash Other windows while workspace discovery catches up')
assert.equal(movingPresentation.groups.find(group => group.identity === 'id:8')?.count, 1)
assert.deepEqual(Array.from(result.groups, g => g.count), [1, 2])
assert.equal(result.groups[0].items[0].toplevels[0], windows[0])
assert.equal(result.groups[1].items[0].toplevels.length, 2)
assert.notEqual(result.groups[0].items[0].presentationId, result.groups[1].items[0].presentationId)
assert.equal(result.renderedItems.length, 3, 'both workspace apps plus closed launcher')
assert.deepEqual(Array.from(result.renderedItems, item => item.presentationId),
  ['id:1/chrome', 'id:2/chrome', 'global/closed'])
context.activeWorkspace = 'id:2'
assert.deepEqual(Array.from(build().renderedItems, item => item.presentationId),
  ['id:2/chrome', 'id:1/chrome', 'global/closed'], 'active owner precedes other visible workspaces')
context.activeWorkspace = 'id:1'
assert.deepEqual(Array.from(result.globalLaunchers, i => i.desktopId), ['closed'])
assert.equal(build(['chrome']).groups[0].count, 0)
result = build([], false)
assert.equal(result.groups[1].items.length, 2)
assert.equal(result.groups[0].items[0].pinned, true)
assert.equal(result.groups[1].items[0].pinned, true, 'pin state is application-wide on W2')
assert.equal(result.groups[1].items[1].pinned, true)
const firefox = { appId: 'firefox' }
const orderedApps = DockModel.buildVisibleItems(['chrome', 'firefox'],
  [windows[0], firefox, windows[1]], [], handles, false, false, [])
const orderedRecords = [
  ...windows.map(toplevel => ({ toplevel,
    ...DockWindowModel.locationForToplevel(toplevel, handles, {}) })),
  { toplevel: firefox, monitor: 'id:0', monitorKnown: true,
    workspace: 'id:2', workspaceKnown: true }
]
const ordered = model.buildWorkspacePresentation(orderedApps, orderedRecords, workspaces,
  { ...context, groupWindows: false })
assert.deepEqual(Array.from(ordered.groups[1].items, item => item.desktopId),
  ['chrome', 'firefox'], 'W2 preserves application pin order')
assert.notEqual(result.groups[1].items[0].presentationId, result.groups[1].items[1].presentationId)
handles[0].lastIpcObject.workspace.id = 2
assert.deepEqual(Array.from(build().groups, g => g.count), [0, 3], 'same-reference move')
handles[0].lastIpcObject.monitor = 1
assert.equal(build().groups[1].count, 2)
assert.equal(build().globalLaunchers.length, 1, 'running elsewhere is not a closed pin')
handles[1].lastIpcObject.monitor = undefined
handles[2].lastIpcObject.workspace = { name: 'special:scratch' }
result = build()
assert.equal(result.fallbackItems[0].toplevels.length, 2)
assert.deepEqual(Array.from(result.groups, g => g.count), [0, 0])
workspaces.push({ id: -1337, name: 'Design work', monitorID: 0 })
result = build()
assert.equal(result.groups[2].activationTarget, 'name:Design work')
// Origin snapshots feed the same location adapter, without another origin store.
handles[2].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
const originLocation = DockWindowModel.locationForToplevel(windows[2], handles,
  { '0x3': { workspace: 'name:Design work', monitor: '0' } })
const originResult = model.buildWorkspacePresentation(
  [{ desktopId: 'chrome', pinned: true, toplevels: [windows[2]] }],
  [{ toplevel: windows[2], ...originLocation }], workspaces, context)
assert.equal(originResult.groups[2].count, 1)
assert.equal(originResult.fallbackItems.length, 0)
assert.equal(model.presentationsEqual(originResult, originResult), true)
assert.equal(model.presentationsEqual(result, originResult), false)
for (const handle of handles) handle.lastIpcObject.monitor = 1
assert.deepEqual(Array.from(build().globalLaunchers, i => i.desktopId), ['closed'])
const otherMonitor = model.buildWorkspacePresentation([], [], [],
  { monitor: 'id:1', activeWorkspace: 'id:11' })
assert.equal(otherMonitor.groups[0].activationTarget, '11')
assert.equal(otherMonitor.groups[0].active, true)

// Alias joins, retained origins, and sticky placement use the complete inventory.
const monitors = [{ id: 0, name: 'DP-1' }, { id: 1, name: 'HDMI-A-1' }]
const scopedContext = { ...context, monitors }
const stickyWindow = { appId: 'chrome' }
const stickyHandle = { wayland: stickyWindow, address: 'abc', urgent: false,
  lastIpcObject: { monitor: 0, workspace: { id: 2 }, pinned: true, urgent: true } }
function stickyPresentation(origins = {}, descriptors = workspaces, ctx = scopedContext) {
  return model.buildWorkspacePresentation(
    [{ desktopId: 'chrome', pinned: true, toplevels: [stickyWindow] }],
    [{ toplevel: stickyWindow,
      ...DockWindowModel.locationForToplevel(stickyWindow, [stickyHandle], origins) }],
    descriptors, ctx)
}
assert.equal(DockWindowModel.monitorIdentity('id:0'), 'id:0')
assert.equal(DockWindowModel.canonicalMonitorIdentity('DP-1', monitors), 'id:0')
assert.equal(DockWindowModel.canonicalMonitorIdentity('name:DP-1', monitors), 'id:0')
assert.equal(DockWindowModel.canonicalMonitorIdentity(monitors[0], monitors), 'id:0')
let stickyResult = stickyPresentation()
assert.equal(stickyResult.groups[0].count, 1)
assert.equal(stickyResult.groups[0].items[0].sticky, true)
assert.equal(stickyResult.groups[0].urgent, false, 'live false beats stale IPC urgent true')
const calmResult = stickyResult
stickyHandle.urgent = true
stickyResult = stickyPresentation()
assert.equal(stickyResult.groups[0].urgent, true)
assert.equal(model.presentationsEqual(calmResult, stickyResult), false, 'urgency refreshes same-reference items')
assert.equal(stickyPresentation({}, workspaces, { ...scopedContext, activeWorkspace: 'id:2' })
  .groups[1].count, 1, 'sticky follows this monitor active workspace')
assert.equal(stickyPresentation({}, workspaces, { ...scopedContext, monitor: 'id:1', activeWorkspace: 'id:3' })
  .groups.reduce((n, g) => n + g.count, 0), 0, 'known other monitor excluded')
stickyHandle.lastIpcObject.monitor = undefined
assert.equal(stickyPresentation().fallbackItems[0].toplevels.length, 1, 'unknown monitor stays fallback')
stickyHandle.lastIpcObject.monitor = 0
stickyHandle.lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
const savedOrigin = { '0xabc': { workspace: 'name:Design work', monitor: 'DP-1' } }
let retained = stickyPresentation(savedOrigin, [])
assert.equal(retained.groups[1].activationTarget, 'name:Design work')
assert.equal(retained.groups[1].count, 1)
assert.equal(retained.groups[1].items[0].sticky, false, 'minimized origin wins over sticky')
retained = stickyPresentation(savedOrigin, [{ name: 'Design work', monitorID: 1 }])
assert.equal(retained.groups.length, 1, 'live workspace ownership overrides saved monitor')
assert.equal(retained.fallbackItems.length, 0)
for (const target of ['', '0', 'special:scratch', 'name:bad;dispatch']) {
  const invalid = stickyPresentation({ '0xabc': { workspace: target, monitor: 'DP-1' } }, [])
  assert.equal(invalid.groups.length, 1, 'invalid origins never invent a card')
  assert.equal(invalid.fallbackItems.length, 1)
}
assert.equal(stickyPresentation({}, []).fallbackItems.length, 1, 'missing origin is fallback')
const closed = model.buildWorkspacePresentation([], [], [], scopedContext)
assert.equal(closed.groups.length, 1, 'closing removes the retained origin card')
assert.equal(closed.groups[0].count, 0)

// Workspace urgency is local even when ungrouped badge ownership selects another member.
handles.forEach((handle, i) => {
  handle.urgent = i === 2
  handle.lastIpcObject = { workspace: { id: i ? 2 : 1 }, monitor: 0 }
})
result = build([], false)
assert.equal(result.groups[0].urgent, false)
assert.equal(result.groups[1].urgent, true)
assert.deepEqual(Array.from(result.groups[1].items, item => item.localUrgent), [false, true])
assert.equal(result.groups[1].count, 2)
assert.equal(build(['chrome']).groups[1].urgent, false, 'hiding removes local urgency')
const BadgeModel = load('DockBadgeModel')
assert.equal(BadgeModel.isPrimaryVisibleItem(result.groups[1].items, 0), true)
assert.equal(BadgeModel.isPrimaryVisibleItem(result.groups[1].items, 1), false)
assert.equal(result.renderedItems.some(item => item.localUrgent), true, 'inactive urgent windows remain rendered')
assert.equal(BadgeModel.isPrimaryVisibleItem(result.renderedItems, 0), true)
assert.equal(BadgeModel.isPrimaryVisibleItem(result.renderedItems, 1), false)
handles[2].lastIpcObject.monitor = 1
assert.equal(build().groups[1].urgent, false, 'move transfers urgency with the same window reference')

const specialOrigin = DockWindowModel.locationForToplevel(stickyWindow, [stickyHandle],
  { '0xabc': { workspace: 'special:notes', monitor: 'DP-1' } })
assert.equal(specialOrigin.workspace, 'special:notes', 'flat scope preserves special origin identity')
assert.equal(specialOrigin.workspaceKnown, true)
assert.equal(specialOrigin.originValid, false, 'grouped normal origin eligibility is separate')
assert.equal(DockWindowModel.monitorIdentity({ id: null }), '')
assert.equal(DockWindowModel.monitorIdentity(-1), '')
assert.equal(DockWindowModel.canonicalMonitorIdentity('DP-1', [monitors[1]]), '')
assert.equal(stickyPresentation(savedOrigin, [], { ...scopedContext, monitors: [monitors[1]] })
  .fallbackItems.length, 1, 'removed connector remains unresolved fallback')

// Blank workspace names alias Quickshell handles; per-client IPC ids and monitors win.
for (const sharedId of [1, 2]) {
  const sharedBlankWorkspace = { id: sharedId, name: '' }
  const sharedMonitor = { id: sharedId === 1 ? 1 : 0,
    name: sharedId === 1 ? 'HDMI-A-1' : 'DP-1' }
  const herdrWindow = { appId: 'herdr' }
  const gameWindow = { appId: 'game' }
  const blankHandles = [
    { wayland: herdrWindow, address: 'herdr', workspace: sharedBlankWorkspace,
      monitor: sharedMonitor,
      lastIpcObject: { workspace: { id: 2, name: '' }, monitor: 0 } },
    { wayland: gameWindow, address: 'game', workspace: sharedBlankWorkspace,
      monitor: sharedMonitor,
      lastIpcObject: { workspace: { id: 1, name: '' }, monitor: 1 } }
  ]
  const blankRecords = [herdrWindow, gameWindow].map(toplevel => ({ toplevel,
    ...DockWindowModel.locationForToplevel(toplevel, blankHandles, {}) }))
  assert.deepEqual(Array.from(blankRecords, record => [record.workspace, record.monitor]),
    [['id:2', 'id:0'], ['id:1', 'id:1']],
    'blank-name clients use per-client IPC location')
  const blankPresentation = model.buildWorkspacePresentation(
    [{ desktopId: 'herdr', pinned: false, toplevels: [herdrWindow] },
      { desktopId: 'game', pinned: false, toplevels: [gameWindow] }],
    blankRecords,
    [{ id: 1, name: '', monitorID: 1 }, { id: 2, name: '', monitorID: 0 }],
    { monitorScope: 'all', activeWorkspace: 'id:1', groupWindows: true,
      monitors: [{ id: 0, name: 'DP-1', activeWorkspace: { id: 2, name: '' } },
        { id: 1, name: 'HDMI-A-1', activeWorkspace: { id: 1, name: '' } }] })
  assert.equal(blankPresentation.groups.find(group => group.identity === 'id:1').items[0]
    .toplevels[0], gameWindow, 'game is placed in IPC workspace 1')
  assert.equal(blankPresentation.groups.find(group => group.identity === 'id:2').items[0]
    .toplevels[0], herdrWindow, 'Herdr is placed in IPC workspace 2')
  blankHandles[0].workspace = { name: 'special:smartdock-minimized' }
  const minimized = DockWindowModel.locationForToplevel(herdrWindow, blankHandles, {})
  assert.equal(minimized.minimized, true, 'live minimized workspace beats stale blank IPC data')
}


// Mirrored docks share membership and global active-first badge ownership.
monitors[0].focused = false
monitors[0].activeWorkspace = { id: 1 }
monitors[1].lastIpcObject = { id: 1, name: 'HDMI-A-1', activeWorkspace: { id: 3 }, focused: true }
const mirrorWindows = [0, 1, 2, 3, 4].map(id => ({ appId: 'chrome', id }))
const mirrorRecords = mirrorWindows.map((toplevel, i) => ({
  toplevel, address: String(i + 10), monitor: i === 0 ? 'DP-1' : 'id:1',
  workspace: i === 0 ? 'id:1' : 'id:3', monitorKnown: true, workspaceKnown: true
}))
mirrorRecords[1].sticky = true
mirrorRecords[1].workspace = 'id:2'
mirrorRecords[2] = { ...mirrorRecords[2], minimized: true, sticky: true,
  workspace: 'name:Retained', originValid: true }
mirrorRecords[3].workspace = 'special:scratch'
mirrorRecords[4].monitor = ''
const mirrorDescriptors = [{ id: 10, monitorID: 0 }, { name: 'Design', monitorID: 1 },
  { id: 2, monitorID: 1 }, { name: 'special:scratch', monitorID: 0 }]
function mirrored(monitor, scope = 'all', grouped = true, hidden = []) {
  const apps = DockModel.buildVisibleItems(['closed', 'chrome'], mirrorWindows, [], [], false, grouped, hidden)
  const owner = monitors.find(value => DockWindowModel.canonicalMonitorIdentity(value, monitors)
    === DockWindowModel.canonicalMonitorIdentity(monitor, monitors))
  return model.buildWorkspacePresentation(apps, mirrorRecords, mirrorDescriptors, {
    monitors, monitor, monitorScope: scope, groupWindows: grouped,
    activeWorkspace: scope === 'current-monitor'
      ? DockWindowModel.workspaceIdentity((owner.lastIpcObject || owner).activeWorkspace)
      : DockWindowModel.focusedWorkspaceIdentity(monitors, null)
  })
}
let left = mirrored('DP-1')
let right = mirrored('HDMI-A-1')
assert.equal(model.presentationsEqual(left, right), true)
assert.deepEqual(Array.from(left.groups, g => g.identity),
  ['id:1', 'id:2', 'id:3', 'id:10', 'name:Design', 'name:Retained'])
assert.equal(left.groups.find(g => g.identity === 'id:10').count, 0)
assert.equal(left.groups.find(g => g.identity === 'id:3').items[0].toplevels[0], mirrorWindows[1],
  'sticky follows owner active workspace, once')
assert.equal(left.groups.find(g => g.identity === 'name:Retained').items[0].sticky, false)
assert.equal(left.fallbackItems[0].toplevels.length, 2)
for (const scope of [undefined, null, '', 'invalid']) {
  const defaulted = scope === undefined
    ? model.buildWorkspacePresentation(
      DockModel.buildVisibleItems(['closed', 'chrome'], mirrorWindows, [], [], false, true, []),
      mirrorRecords, mirrorDescriptors, { monitors, monitor: 'DP-1', activeWorkspace: 'id:3' })
    : mirrored('DP-1', scope)
  assert.equal(model.presentationsEqual(left, defaulted), true, 'missing/invalid scope mirrors')
}
const local = mirrored('DP-1', 'current-monitor')
assert.equal(local.groups.find(g => g.active).identity, 'id:1')
assert.equal(local.groups.some(g => g.identity === 'id:3'), false, 'no empty remote active card')
assert.equal(local.groups.some(g => g.identity === 'name:Retained'), false)
assert.equal(local.renderedItems.some(item => item.toplevels.includes(mirrorWindows[1])), false)
assert.equal(left.renderedItems[0].presentationId, 'id:3/chrome')
monitors[0].focused = true
monitors[1].lastIpcObject.focused = false
right = mirrored('HDMI-A-1')
assert.equal(right.renderedItems[0].presentationId, 'id:1/chrome', 'global focus transfers badge owner')
assert.equal(right.groups.find(g => g.identity === 'id:3').count, 1,
  'global focus does not relocate sticky membership')
assert.equal(model.presentationsEqual(right, mirrored('DP-1')), true)
assert.equal(BadgeModel.isPrimaryVisibleItem(right.renderedItems, 0), true)
assert.equal(Array.from(right.renderedItems, (_, i) =>
  BadgeModel.isPrimaryVisibleItem(right.renderedItems, i)).filter(Boolean).length, 2,
  'one owner per app including closed pin')
assert.equal(mirrored('DP-1', 'all', true, ['chrome']).groups.every(g => g.count === 0), true)
assert.equal(model.presentationsEqual(mirrored('DP-1', 'all', false),
  mirrored('HDMI-A-1', 'all', false)), true)
mirrorRecords[0].workspace = 'id:2'
assert.equal(mirrored('DP-1').groups.find(g => g.identity === 'id:2').count, 1, 'live move updates card')
monitors[1].lastIpcObject.activeWorkspace = { id: 4 }
assert.equal(mirrored('DP-1').groups.find(g => g.identity === 'id:4').count, 1, 'topology updates sticky card')

console.log('workspace model: PASS')
