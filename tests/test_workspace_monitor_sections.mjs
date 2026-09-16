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

assert.equal(typeof WorkspaceModel.monitorGroupForWorkspace, 'function',
  'workspace model exposes the section-prefix lookup used by the retained card delegate')

function monitor(id, name, description, model, workspace, focused = false) {
  return { id, name, description, model, focused, x: id * 1000, y: 0,
    activeWorkspace: { id: workspace, name: String(workspace) } }
}

const longDescription = 'UltraWide Production Display With A Deliberately Long Descriptive Name'
const monitors = [
  monitor(0, 'DP-1', 'Shared display', 'ASUS VP249', 1, false),
  monitor(1, 'HDMI-A-1', 'Shared display', 'E2350', 3, true),
  monitor(2, '', '', '', 5, false),
  monitor(3, 'DP-4', longDescription, '', 7, false)
]
const workspaces = [
  { id: 1, monitorID: 0 }, { id: 2, monitorID: 0 },
  { id: 3, monitorID: 1 }, { id: 4, monitorID: 1 },
  { id: 5, monitorID: 2 }, { id: 7, monitorID: 3 }
]

function build(currentMonitors = monitors, currentWorkspaces = workspaces) {
  return WorkspaceModel.buildWorkspacePresentation([], [], currentWorkspaces, {
    monitorScope: 'all', monitor: 'id:0',
    activeWorkspace: DockWindowModel.focusedWorkspaceIdentity(currentMonitors, null),
    monitors: currentMonitors, groupWindows: true
  })
}

const initial = build()
const sections = Array.from(initial.monitorGroups)
assert.deepEqual(sections.map(section => section.label), [
  'ASUS VP249', 'E2350', 'Monitor 2', longDescription
], 'exact model names lead while blank model metadata falls back safely')
assert.deepEqual(sections.map(section => section.description), [
  'Shared display', 'Shared display', 'Monitor 2', longDescription
], 'full monitor descriptions remain available separately from compact labels')
assert.deepEqual(sections.map(section => section.identity), ['id:0', 'id:1', 'id:2', 'id:3'])
assert.deepEqual(sections.map(section => section.firstWorkspaceIdentity),
  ['id:1', 'id:3', 'id:5', 'id:7'])
assert.equal(sections.filter(section => section.focused).length, 1)
assert.equal(sections.find(section => section.focused)?.identity, 'id:1')

const first = WorkspaceModel.monitorGroupForWorkspace(initial.monitorGroups, 'id:1', true)
assert.equal(first?.identity, 'id:0')
assert.equal(WorkspaceModel.monitorGroupForWorkspace(initial.monitorGroups, 'id:2', true), null,
  'only the first present workspace in a section owns its prefix')
assert.equal(WorkspaceModel.monitorGroupForWorkspace(initial.monitorGroups, 'id:1', false), null,
  'an exiting first card immediately relinquishes its prefix')

const promotedMonitors = monitors.map(value => ({
  ...value, activeWorkspace: { ...value.activeWorkspace }
}))
promotedMonitors[0].activeWorkspace = { id: 2, name: '2' }
const withoutFirst = build(promotedMonitors,
  workspaces.filter(workspace => workspace.id !== 1))
const promoted = WorkspaceModel.monitorGroupForWorkspace(
  withoutFirst.monitorGroups, 'id:2', true)
assert.equal(promoted?.identity, 'id:0',
  'the next present workspace gains the section prefix when the old first card exits')
assert.equal(promoted?.firstWorkspaceIdentity, 'id:2')

const focusBefore = sections.map(section => [section.identity, section.focused])
monitors[0].focused = true
monitors[1].focused = false
const focusAfter = build()
assert.deepEqual(Array.from(focusAfter.monitorGroups, section => section.identity),
  sections.map(section => section.identity), 'focus-only changes never reorder sections')
assert.notDeepEqual(Array.from(focusAfter.monitorGroups, section => [section.identity, section.focused]),
  focusBefore, 'focus-only changes update informational label brightness metadata')
monitors[0].focused = false
monitors[1].focused = true

const state = PresentationModel.reconcile(null, initial.groups, 'identity', true)
const workspaceTokens = Object.fromEntries(state.entries.map(entry => [entry.key, entry.token]))
const movedWorkspaces = workspaces.map(workspace => ({ ...workspace }))
movedWorkspaces.find(workspace => workspace.id === 2).monitorID = 1
const moved = build(monitors, movedWorkspaces)
const reconciled = PresentationModel.reconcile(state, moved.groups, 'identity', true)
for (const entry of reconciled.entries) {
  assert.equal(entry.token, workspaceTokens[entry.key],
    `workspace ${entry.key} keeps its delegate token across section transfer`)
  assert.equal(entry.animateEntrance, false)
}
assert.equal(reconciled.entries.some(entry => !entry.present), false,
  'section transfer never creates an exiting duplicate card')

console.log('inline monitor section model contract: PASS')
