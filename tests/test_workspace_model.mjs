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
const DockWindowModel = load('DockWindowModel')
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
assert.equal(result.renderedItems.length, 2, 'closed launcher plus expanded W1')
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
console.log('workspace model: PASS')
