import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function loadComponent(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(
    fs.readFileSync(path.join(root, 'components', name), 'utf8')
      .replace(/^\.(pragma|import).*$/gm, ''),
    scope)
  return scope
}

function loadPreviewModel(imports = {}) {
  const file = path.join(root, 'tests/runtime/workspace-drag-preview/PreviewModel.js')
  assert.ok(fs.existsSync(file), 'PreviewModel.js exists')
  const scope = vm.createContext(imports)
  vm.runInContext(
    fs.readFileSync(file, 'utf8').replace(/^\.(pragma|import).*$/gm, ''),
    scope)
  return scope
}

const DockModel = loadComponent('DockModel.js')
const DockWindowModel = loadComponent('DockWindowModel.js', { DockModel })
const DockWorkspaceModel = loadComponent('DockWorkspaceModel.js', {
  DockModel,
  DockWindowModel
})
const PreviewModel = loadPreviewModel({ DockWorkspaceModel })

assert.equal(typeof PreviewModel.workspaceCompare, 'function')
assert.equal(typeof PreviewModel.project, 'function')
assert.equal(typeof PreviewModel.commit, 'function')

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

function fixtures() {
  return {
    monitors: [
      {
        identity: 'id:0',
        connector: 'DP-1',
        label: 'Monitor A',
        activeWorkspace: 'id:1',
        pinnedWorkspaces: []
      },
      {
        identity: 'id:1',
        connector: 'HDMI-A-1',
        label: 'Monitor B',
        activeWorkspace: 'id:4',
        pinnedWorkspaces: ['name:Work']
      }
    ],
    workspaces: [
      { identity: 'id:2', owner: 'id:0', label: '2', showFullLabel: false, count: 3 },
      { identity: 'id:1', owner: 'id:0', label: '1', showFullLabel: false, count: 1 },
      { identity: 'name:Work', owner: 'id:1', label: 'Work', showFullLabel: true, count: 1 },
      { identity: 'id:4', owner: 'id:1', label: '4', showFullLabel: false, count: 2 },
      { identity: 'id:3', owner: 'id:0', label: '3', showFullLabel: false, count: 0 }
    ]
  }
}

function ownersOf(presentation) {
  const owners = {}
  for (const monitor of presentation.monitors) {
    for (const workspace of monitor.workspaces)
      owners[workspace.identity] = monitor.identity
  }
  return owners
}

const baseline = fixtures()
const baselineJson = JSON.stringify(baseline)

const idle = PreviewModel.project(baseline, null)
assert.equal(JSON.stringify(baseline), baselineJson, 'project leaves fixtures unchanged')
assert.notEqual(idle.monitors, baseline.monitors)
assert.deepEqual(Array.from(idle.monitors, m => m.identity), ['id:0', 'id:1'])
assert.deepEqual(Array.from(idle.monitors[0].workspaces, w => w.identity),
  ['id:1', 'id:2', 'id:3'], 'numeric sort within monitor A')
assert.deepEqual(Array.from(idle.monitors[1].workspaces, w => w.identity),
  ['id:4', 'name:Work'], 'numeric before named on monitor B')
assert.deepEqual(plain(idle.workspaceOwners), {
  'id:1': 'id:0',
  'id:2': 'id:0',
  'id:3': 'id:0',
  'id:4': 'id:1',
  'name:Work': 'id:1'
})

const hover = PreviewModel.project(baseline, {
  workspaceIdentity: 'id:2',
  targetMonitor: 'id:1'
})
assert.equal(JSON.stringify(baseline), baselineJson, 'hover projection is non-mutating')
assert.deepEqual(plain(ownersOf(hover)), {
  'id:1': 'id:0',
  'id:3': 'id:0',
  'id:2': 'id:1',
  'id:4': 'id:1',
  'name:Work': 'id:1'
})
assert.deepEqual(Array.from(hover.monitors[1].workspaces, w => w.identity),
  ['id:2', 'id:4', 'name:Work'], 'destination uses DockWorkspaceModel sort')
assert.equal(PreviewModel.workspaceCompare('id:2', 'id:4'),
  DockWorkspaceModel.workspaceCompare('id:2', 'id:4'))

const sameOwner = PreviewModel.project(baseline, {
  workspaceIdentity: 'id:2',
  targetMonitor: 'id:0'
})
assert.deepEqual(plain(ownersOf(sameOwner)), plain(idle.workspaceOwners),
  'current owner is not a hover destination')

const pinned = PreviewModel.project(baseline, {
  workspaceIdentity: 'name:Work',
  targetMonitor: 'id:0'
})
assert.deepEqual(plain(ownersOf(pinned)), plain(idle.workspaceOwners),
  'pinned destinations are rejected')

const committed = PreviewModel.commit(baseline, 'id:2', 'id:1')
assert.equal(JSON.stringify(baseline), baselineJson, 'commit leaves input fixtures unchanged')
assert.notEqual(committed, baseline)
assert.deepEqual(
  plain(Object.fromEntries(committed.workspaces.map(w => [w.identity, w.owner]))),
  {
    'id:1': 'id:0',
    'id:2': 'id:1',
    'id:3': 'id:0',
    'id:4': 'id:1',
    'name:Work': 'id:1'
  })

const rejectedOwner = PreviewModel.commit(baseline, 'id:2', 'id:0')
assert.deepEqual(plain(rejectedOwner), JSON.parse(baselineJson),
  'commit rejects current owner')

const rejectedPin = PreviewModel.commit(baseline, 'name:Work', 'id:0')
assert.deepEqual(plain(rejectedPin), JSON.parse(baselineJson),
  'commit rejects pinned workspace moves')

const once = PreviewModel.commit(committed, 'id:2', 'id:1')
assert.deepEqual(plain(once), plain(committed), 'second identical commit is a no-op')

const emptied = PreviewModel.project(baseline, {
  workspaceIdentity: 'id:4',
  targetMonitor: 'id:0'
})
assert.deepEqual(Array.from(emptied.monitors, m => m.identity), ['id:0', 'id:1'],
  'monitor order stays fixed during hover')
assert.equal(emptied.monitors[1].workspaces.length, 1,
  'destination keeps remaining cards')
assert.ok(emptied.monitors.some(m => m.identity === 'id:1'),
  'emptyable destination section remains addressable')

const emptyFixtures = {
  monitors: [
    {
      identity: 'id:0',
      connector: 'DP-1',
      label: 'Monitor A',
      activeWorkspace: 'id:1',
      pinnedWorkspaces: []
    },
    {
      identity: 'id:1',
      connector: 'HDMI-A-1',
      label: 'Monitor B',
      activeWorkspace: '',
      pinnedWorkspaces: []
    }
  ],
  workspaces: [
    { identity: 'id:1', owner: 'id:0', label: '1', count: 1 }
  ]
}
const intoEmpty = PreviewModel.project(emptyFixtures, {
  workspaceIdentity: 'id:1',
  targetMonitor: 'id:1'
})
assert.deepEqual(Array.from(intoEmpty.monitors[1].workspaces, w => w.identity), ['id:1'])
assert.deepEqual(Array.from(intoEmpty.monitors[0].workspaces, w => w.identity), [])
assert.equal(intoEmpty.monitors.length, 2, 'empty source section retained during gesture')

console.log('workspace drag preview projection model: PASS')
