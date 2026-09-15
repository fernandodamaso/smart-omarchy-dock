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
const WorkspaceModel = load('DockWorkspaceModel', { DockModel, DockWindowModel })
const PresentationModel = load('DockPresentationModel')

function monitor(id, name, x, y, workspace, focused = false) {
  const value = {
    id, name, focused,
    activeWorkspace: { id: workspace, name: String(workspace) }
  }
  if (x !== undefined) value.x = x
  if (y !== undefined) value.y = y
  return value
}
function workspace(id, monitorID) {
  return { id, name: String(id), monitorID }
}
function app(desktopId, toplevel) {
  return { desktopId, pinned: false, toplevels: [toplevel] }
}
function record(toplevel, workspaceIdentity, monitorIdentity) {
  return {
    toplevel, address: '', workspace: workspaceIdentity, monitor: monitorIdentity,
    workspaceKnown: true, monitorKnown: true, minimized: false,
    sticky: false, urgent: false
  }
}
function connectorOrder(presentation) {
  return Array.from(presentation.monitorGroups || [], group => group.connector)
}
function groupOrder(presentation) {
  return Array.from(presentation.groups || [], group => group.identity)
}

const monitors = [
  monitor(0, 'ZETA', 1920, 0, 10, false),
  monitor(1, 'ALPHA', -1280, 200, 1, true),
  monitor(2, 'BETA', 0, -200, 3, false),
  monitor(3, 'GAMMA', 0, 300, 4, false),
  monitor(5, 'DELTA', 0, 300, 6, false),
  monitor(4, 'MISSING', undefined, undefined, 5, false)
]
const workspaces = [
  workspace(10, 0), workspace(1, 1), workspace(2, 1), workspace(3, 2),
  workspace(4, 3), workspace(6, 5), workspace(5, 4)
]
const windows = {
  one: { appId: 'one' }, three: { appId: 'three' }, ten: { appId: 'ten' }
}
const apps = [app('one', windows.one), app('three', windows.three), app('ten', windows.ten)]
const records = [
  record(windows.one, 'id:1', 'id:1'),
  record(windows.three, 'id:3', 'id:2'),
  record(windows.ten, 'id:10', 'id:0')
]

function build(options = {}) {
  return WorkspaceModel.buildWorkspacePresentation(
    options.apps || apps,
    options.records || records,
    options.workspaces || workspaces,
    {
      monitorScope: options.monitorScope || 'all',
      monitor: options.monitor || 'id:1',
      activeWorkspace: options.activeWorkspace || 'id:1',
      monitors: options.monitors || monitors,
      monitorOrder: options.monitorOrder || [],
      groupWindows: true
    })
}

const automatic = build()
assert.deepEqual(connectorOrder(automatic),
  ['ALPHA', 'BETA', 'DELTA', 'GAMMA', 'ZETA', 'MISSING'],
  'automatic order is numeric x/y, connector tie-break, then unpositioned monitors')
assert.deepEqual(groupOrder(automatic),
  ['id:1', 'id:2', 'id:3', 'id:6', 'id:4', 'id:10', 'id:5'],
  'workspaces remain numeric/named sorted inside physical monitor sections')

const reversedInventory = build({ monitors: monitors.slice().reverse(), workspaces: workspaces.slice().reverse() })
assert.deepEqual(connectorOrder(reversedInventory), connectorOrder(automatic),
  'input inventory order does not affect automatic monitor order')
assert.equal(WorkspaceModel.presentationsEqual(automatic, reversedInventory), true)

monitors[0].focused = true
monitors[1].focused = false
const focusOnly = build({ activeWorkspace: 'id:10' })
assert.deepEqual(connectorOrder(focusOnly), connectorOrder(automatic),
  'focus changes never reorder monitor sections')
monitors[0].focused = false
monitors[1].focused = true

const configured = build({ monitorOrder: ['ZETA', 'GAMMA'] })
assert.deepEqual(connectorOrder(configured),
  ['ZETA', 'GAMMA', 'ALPHA', 'BETA', 'DELTA', 'MISSING'],
  'configured connected connectors lead; unlisted connectors append geometrically')
assert.deepEqual(Array.from(configured.renderedItems, item => item.presentationId),
  Array.from(automatic.renderedItems, item => item.presentationId),
  'visual monitor order never changes global badge/preview traversal')
assert.deepEqual(new Set(groupOrder(configured)), new Set(groupOrder(automatic)),
  'monitor ordering never changes workspace identity membership')
assert.equal(WorkspaceModel.presentationsEqual(automatic, configured), false,
  'changing visual section order refreshes presentation')

const initialState = PresentationModel.reconcile(null, automatic.groups, 'identity', true)
const tokens = Object.fromEntries(initialState.entries.map(entry => [entry.key, entry.token]))
const reorderedState = PresentationModel.reconcile(initialState, configured.groups, 'identity', true)
assert.equal(reorderedState.entries.every(entry => entry.present), true)
assert.equal(reorderedState.entries.every(entry => !entry.animateEntrance), true)
for (const entry of reorderedState.entries)
  assert.equal(entry.token, tokens[entry.key], 'workspace token survives monitor-order-only move: ' + entry.key)

const offlineSaved = build({ monitorOrder: ['OFFLINE', 'ZETA'] })
assert.deepEqual(connectorOrder(offlineSaved),
  ['ZETA', 'ALPHA', 'BETA', 'DELTA', 'GAMMA', 'MISSING'],
  'disconnected saved connector is retained conceptually but skipped in rendering')

const offlineMonitor = monitor(6, 'OFFLINE', 9999, 9999, 7, false)
const reconnected = build({
  monitorOrder: ['OFFLINE', 'ZETA'],
  monitors: monitors.concat([offlineMonitor]),
  workspaces: workspaces.concat([workspace(7, 6)])
})
assert.deepEqual(connectorOrder(reconnected).slice(0, 2), ['OFFLINE', 'ZETA'],
  'reconnected saved connector restores its configured position regardless of geometry')

const withNewUnlisted = build({
  monitorOrder: ['ZETA'],
  monitors: monitors.concat([monitor(7, 'NEW', -640, 0, 8, false)]),
  workspaces: workspaces.concat([workspace(8, 7)])
})
assert.deepEqual(connectorOrder(withNewUnlisted).slice(0, 4),
  ['ZETA', 'ALPHA', 'NEW', 'BETA'],
  'new unlisted connector appends after configured monitors using automatic geometry order')

const currentMonitorDefault = build({
  monitorScope: 'current-monitor', monitor: 'id:1', activeWorkspace: 'id:1', monitorOrder: []
})
const currentMonitorConfigured = build({
  monitorScope: 'current-monitor', monitor: 'id:1', activeWorkspace: 'id:1',
  monitorOrder: ['ZETA', 'GAMMA', 'ALPHA']
})
assert.deepEqual(Array.from(currentMonitorConfigured.monitorGroups || []), [],
  'current-monitor keeps the existing flat grouped presentation')
assert.deepEqual(groupOrder(currentMonitorConfigured), groupOrder(currentMonitorDefault),
  'saved physical order is visually inactive in current-monitor scope')
assert.equal(WorkspaceModel.presentationsEqual(currentMonitorDefault, currentMonitorConfigured), true)

console.log('workspace physical monitor ordering: PASS')
