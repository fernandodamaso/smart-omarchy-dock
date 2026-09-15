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

function app(desktopId, ...toplevels) {
  return { desktopId, pinned: false, toplevels }
}

function record(toplevel, workspace, monitor, extra = {}) {
  return {
    toplevel,
    address: extra.address || '',
    workspace,
    monitor,
    workspaceKnown: workspace !== '',
    monitorKnown: monitor !== '',
    minimized: extra.minimized === true,
    originValid: extra.originValid,
    sticky: extra.sticky === true,
    urgent: extra.urgent === true
  }
}

function monitorIdentitySummary(presentation) {
  return Array.from(presentation.groups, group => [
    group.identity, group.monitorIdentity || '', group.active === true
  ])
}

function monitorGroupSummary(presentation) {
  return Array.from(presentation.monitorGroups || [], group => [
    group.identity || '', group.connector || '', group.label || '',
    group.focused === true, group.activeWorkspace || '',
    group.firstWorkspaceIdentity || ''
  ])
}

const left = {
  id: 0,
  name: 'DP-1',
  description: 'Built-in panel',
  focused: false,
  activeWorkspace: { id: 1, name: '1' }
}
const right = {
  id: 1,
  name: 'HDMI-A-1',
  lastIpcObject: {
    id: 1,
    name: 'HDMI-A-1',
    description: 'Desk display',
    focused: true,
    activeWorkspace: { id: 3, name: '3' }
  }
}
const monitors = [left, right]
const descriptors = [
  { id: 10, name: 'Work', monitorID: 0 },
  { id: 1, monitorID: 0 },
  { id: 2, monitorID: 1 },
  { id: 3, monitorID: 1 },
  { name: 'Design', monitorID: 1 }
]
const one = { appId: 'one' }
const three = { appId: 'three' }
const ten = { appId: 'ten' }
const records = [
  record(one, 'id:1', 'id:0'),
  record(three, 'id:3', 'id:1'),
  record(ten, 'id:10', 'id:0')
]
const apps = [
  { desktopId: 'closed', pinned: true, toplevels: [] },
  app('one', one), app('three', three), app('ten', ten)
]

function buildAll(overrides = {}) {
  const activeWorkspace = DockWindowModel.focusedWorkspaceIdentity(
    overrides.monitors || monitors, null)
  return WorkspaceModel.buildWorkspacePresentation(
    overrides.apps || apps,
    overrides.records || records,
    overrides.workspaces || descriptors,
    {
      monitorScope: 'all',
      monitor: 'id:0',
      activeWorkspace,
      monitors: overrides.monitors || monitors,
      groupWindows: true
    })
}

const initial = buildAll()
assert.equal(initial.primaryWorkspaceIdentity, 'id:3',
  'global focus is retained separately from per-monitor active styling')
assert.deepEqual(monitorIdentitySummary(initial), [
  ['id:1', 'id:0', true],
  ['id:10', 'id:0', false],
  ['id:2', 'id:1', false],
  ['id:3', 'id:1', true],
  ['name:Design', 'id:1', false]
], 'each workspace appears once under one canonical monitor owner')
assert.deepEqual(monitorGroupSummary(initial), [
  ['id:0', 'DP-1', 'Built-in panel', false, 'id:1', 'id:1'],
  ['id:1', 'HDMI-A-1', 'Desk display', true, 'id:3', 'id:2']
], 'monitor metadata carries active/focus state and section boundaries')
assert.deepEqual(Array.from(initial.groups.filter(group => group.active), group => group.identity),
  ['id:1', 'id:3'], 'each monitor active workspace gets active card styling')
assert.equal(initial.globalLaunchers.length, 1, 'closed global launchers remain singleton')
assert.deepEqual(Array.from(initial.renderedItems, item => item.presentationId),
  ['id:3/three', 'id:1/one', 'id:10/ten', 'global/closed'],
  'badge traversal stays primary-focus first and otherwise uses old workspace order')

left.focused = true
right.lastIpcObject.focused = false
const focusTransferred = buildAll()
assert.equal(focusTransferred.primaryWorkspaceIdentity, 'id:1')
assert.deepEqual(Array.from(focusTransferred.groups.filter(group => group.active), group => group.identity),
  ['id:1', 'id:3'], 'focus transfer does not change per-monitor active cards')
assert.equal(WorkspaceModel.presentationsEqual(initial, focusTransferred), false,
  'focus-only transfer refreshes presentation metadata')
assert.deepEqual(Array.from(focusTransferred.renderedItems, item => item.presentationId),
  ['id:1/one', 'id:3/three', 'id:10/ten', 'global/closed'])

const reordered = buildAll({
  monitors: [right, left],
  workspaces: descriptors.slice().reverse(),
  records: records.slice().reverse()
})
assert.equal(WorkspaceModel.presentationsEqual(focusTransferred, reordered), true,
  'inventory order alone does not change semantic presentation')

const beforeDescription = focusTransferred
left.description = 'Renamed built-in panel'
const afterDescription = buildAll()
assert.equal(WorkspaceModel.presentationsEqual(beforeDescription, afterDescription), false,
  'same-object monitor description changes refresh metadata')
assert.equal((afterDescription.monitorGroups || [])[0]?.label, 'Renamed built-in panel')

const movingWindow = { appId: 'moving' }
const movingWorkspace = { id: 5, name: 'Five', monitorID: 0 }
const movingApps = [app('moving', movingWindow)]
const movingRecords = [record(movingWindow, 'id:5', 'id:0')]
function buildMoving(workspaces = [movingWorkspace], currentMonitors = monitors) {
  return WorkspaceModel.buildWorkspacePresentation(
    movingApps, movingRecords, workspaces, {
      monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
      monitors: currentMonitors, groupWindows: true
    })
}
const beforeMove = buildMoving()
assert.equal(beforeMove.groups.find(group => group.identity === 'id:5')?.monitorIdentity, 'id:0')
movingWorkspace.monitorID = 1
const afterMove = buildMoving()
assert.equal(afterMove.groups.find(group => group.identity === 'id:5')?.monitorIdentity, 'id:1',
  'authoritative workspace descriptor overrides stale client monitor')
assert.equal(WorkspaceModel.presentationsEqual(beforeMove, afterMove), false)

movingWorkspace.monitorID = 99
const unresolved = buildMoving()
assert.equal(unresolved.groups.find(group => group.identity === 'id:5')?.monitorIdentity, '',
  'unresolved authoritative descriptor is never replaced by stale client ownership')
assert.deepEqual(monitorGroupSummary(unresolved).slice(-1), [
  ['', '', 'Unknown monitor', false, '', 'id:5']
], 'known workspace with unresolved owner gets a temporary unknown monitor section')

const conflictA = { appId: 'conflict-a' }
const conflictB = { appId: 'conflict-b' }
const conflicted = WorkspaceModel.buildWorkspacePresentation(
  [app('conflict-a', conflictA), app('conflict-b', conflictB)],
  [record(conflictA, 'id:7', 'id:0'), record(conflictB, 'id:7', 'id:1')],
  [], {
    monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
    monitors, groupWindows: true
  })
assert.equal(conflicted.groups.find(group => group.identity === 'id:7')?.monitorIdentity, '',
  'conflicting live window owners remain unresolved instead of first-record wins')

const unknownWindow = { appId: 'unknown' }
const unknownLive = WorkspaceModel.buildWorkspacePresentation(
  [app('unknown', unknownWindow)],
  [record(unknownWindow, 'id:9', 'MISSING-CONNECTOR')],
  [], {
    monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
    monitors, groupWindows: true
  })
assert.equal(unknownLive.groups.find(group => group.identity === 'id:9')?.monitorIdentity, '',
  'known live workspace remains present when monitor ownership is temporarily unknown')
assert.equal(unknownLive.groups.find(group => group.identity === 'id:9')?.count, 1)
assert.equal(unknownLive.fallbackItems.length, 0,
  'known workspace with unknown monitor does not fall into Other windows')
assert.deepEqual(monitorGroupSummary(unknownLive).slice(-1), [
  ['', '', 'Unknown monitor', false, '', 'id:9']
])

const partialA = { appId: 'partial-a' }
const partialB = { appId: 'partial-b' }
const partiallyUnresolved = WorkspaceModel.buildWorkspacePresentation(
  [app('partial-a', partialA), app('partial-b', partialB)],
  [record(partialA, 'id:11', 'id:0'), record(partialB, 'id:11', 'MISSING-CONNECTOR')],
  [], {
    monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
    monitors, groupWindows: true
  })
assert.equal(partiallyUnresolved.groups.find(group => group.identity === 'id:11')?.monitorIdentity, '',
  'mixed known and unknown live owners stay unresolved rather than guessing the known owner')
assert.equal(partiallyUnresolved.groups.find(group => group.identity === 'id:11')?.count, 2)
assert.equal(partiallyUnresolved.fallbackItems.length, 0)

const minimizedWindow = { appId: 'minimized' }
const liveOwned = WorkspaceModel.buildWorkspacePresentation(
  [app('minimized', minimizedWindow)],
  [record(minimizedWindow, 'id:6', 'id:0', { minimized: true, originValid: true })],
  [{ id: 6, monitorID: 1 }], {
    monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
    monitors, groupWindows: true
  })
assert.equal(liveOwned.groups.find(group => group.identity === 'id:6')?.monitorIdentity, 'id:1',
  'live workspace ownership wins over minimized origin connector')

const reconnectWorkspace = { id: 8, monitor: 'HDMI-A-1' }
const connected = WorkspaceModel.buildWorkspacePresentation([], [], [reconnectWorkspace], {
  monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1', monitors, groupWindows: true
})
assert.equal(connected.groups.find(group => group.identity === 'id:8')?.monitorIdentity, 'id:1')
const disconnected = WorkspaceModel.buildWorkspacePresentation([], [], [reconnectWorkspace], {
  monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1', monitors: [left], groupWindows: true
})
assert.equal(disconnected.groups.find(group => group.identity === 'id:8')?.monitorIdentity, '')
const reconnectedMonitor = {
  id: 7, name: 'HDMI-A-1', focused: false,
  activeWorkspace: { id: 8, name: '8' }
}
const reconnected = WorkspaceModel.buildWorkspacePresentation([], [], [reconnectWorkspace], {
  monitorScope: 'all', monitor: 'id:0', activeWorkspace: 'id:1',
  monitors: [left, reconnectedMonitor], groupWindows: true
})
assert.equal(reconnected.groups.find(group => group.identity === 'id:8')?.monitorIdentity, 'id:7')
assert.equal(reconnected.groups.find(group => group.identity === 'id:8')?.identity, 'id:8',
  'reconnect changes monitor identity without changing workspace identity')

const currentMonitor = WorkspaceModel.buildWorkspacePresentation(apps, records, descriptors, {
  monitorScope: 'current-monitor', monitor: 'id:0', activeWorkspace: 'id:1',
  monitors, groupWindows: true
})
assert.equal(currentMonitor.primaryWorkspaceIdentity, 'id:1')
assert.deepEqual(Array.from(currentMonitor.monitorGroups || []), [],
  'current-monitor scope keeps the existing flat grouped appearance')
assert.deepEqual(Array.from(currentMonitor.groups, group => group.identity), ['id:1', 'id:10'])
assert.deepEqual(Array.from(currentMonitor.groups.filter(group => group.active), group => group.identity), ['id:1'])

console.log('workspace monitor model: PASS')
