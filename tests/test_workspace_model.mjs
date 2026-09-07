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
const context = { monitor: 'id:0', activeWorkspace: 'id:1', groupWindows: true }
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

console.log('workspace model: PASS')
