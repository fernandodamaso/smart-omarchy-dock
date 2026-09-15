import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const componentText = name => fs.readFileSync(
  new URL(`../components/${name}`, import.meta.url), 'utf8')
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(componentText(name).replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}

const DockIconModel = model('DockIconModel.js')
const DockModel = model('DockModel.js')
const DockWindowModel = model('DockWindowModel.js', { DockModel })
const WorkspaceModel = model('DockWorkspaceModel.js', { DockModel, DockWindowModel })
const DockWorkspaceGroupModel = model('DockWorkspaceGroupModel.js', { DockModel })
const ConfigModel = model('DockConfigModel.js', {
  DockIconModel, DockWorkspaceGroupModel
})
const schema = JSON.parse(fs.readFileSync(
  new URL('../config/settings-schema.json', import.meta.url), 'utf8'))

assert.equal(typeof DockWorkspaceGroupModel.normalizeWorkspaceGroups, 'function',
  'CM-03 exposes strict runtime workspace-group normalization')
assert.equal(typeof DockWorkspaceGroupModel.workspaceGroupEnabled, 'function',
  'CM-03 exposes exact app/workspace policy lookup')
assert.equal(typeof DockWorkspaceGroupModel.buildFlatPresentation, 'function',
  'flat layout has the same local grouping policy as workspace cards')
assert.equal(typeof ConfigModel.workspaceGroupIntent, 'function',
  'host mutations use a latest-settings workspace-group intent')

const chrome = id => ({ id, appId: 'com.google.Chrome', title: `Chrome ${id}` })
const A = chrome('A')
const B = chrome('B')
const C = chrome('C')
const D = chrome('D')
let windows = [A, B, C, D]
const handles = [
  { wayland: A, address: '0xa1', lastIpcObject: { workspace: { id: 3 }, monitor: 0 } },
  { wayland: B, address: '0xb2', lastIpcObject: { workspace: { id: 3 }, monitor: 0 } },
  { wayland: C, address: '0xc3', lastIpcObject: { workspace: { id: 4 }, monitor: 0 } },
  { wayland: D, address: '0xd4', lastIpcObject: { workspace: { id: 4 }, monitor: 0 } }
]
const monitors = [{ id: 0, name: 'DP-1', lastIpcObject: {
  id: 0, name: 'DP-1', focused: true, activeWorkspace: { id: 3 }, x: 0, y: 0
} }]
const workspaces = [
  { id: 3, monitorID: 0 },
  { id: 4, monitorID: 0 }
]
const onlyWorkspace3 = [{ desktopId: 'com.google.Chrome', workspace: 'id:3' }]

function records(origins = {}) {
  return windows.map(toplevel => ({ toplevel,
    ...DockWindowModel.locationForToplevel(toplevel, handles, origins) }))
}
function individualBase() {
  return DockModel.buildVisibleItems(
    ['com.google.Chrome'], windows, [], handles, false, false, [])
}
function flat(groups = onlyWorkspace3, origins = {}) {
  return DockWorkspaceGroupModel.buildFlatPresentation(
    individualBase(), records(origins), groups, false)
}
function cards(groups = onlyWorkspace3, origins = {}) {
  const locations = records(origins)
  const localized = DockWorkspaceGroupModel.prepareWorkspaceItems(
    individualBase(), locations, groups)
  const presentation = WorkspaceModel.buildWorkspacePresentation(
    localized, locations, workspaces, {
      monitorScope: 'all', monitor: 'id:0', monitors,
      activeWorkspace: 'id:3', groupWindows: false
    })
  return DockWorkspaceGroupModel.decorateWorkspacePresentation(presentation, groups)
}
function matching(items, workspace) {
  return items.filter(item => String(item.presentationId || '').startsWith(`${workspace}/com.google.Chrome`))
}

let result = flat()
let w3 = matching(result, 'id:3')
let w4 = matching(result, 'id:4')
assert.equal(w3.length, 1, 'only Workspace 3 collapses into one Chrome presentation')
assert.deepEqual(Array.from(w3[0].toplevels), [A, B])
assert.equal(w3[0].identityToplevel, null, 'configured local group has group identity')
assert.equal(w4.length, 2, 'Workspace 4 remains individual when no pair is saved')
assert.deepEqual(Array.from(w4, item => item.toplevels.length), [1, 1])
assert.notEqual(w4[0].presentationId, w4[1].presentationId)

let grouped = cards()
const card3 = grouped.groups.find(group => group.identity === 'id:3')
const card4 = grouped.groups.find(group => group.identity === 'id:4')
assert.equal(card3.items.length, 1, 'workspace-card layout agrees with flat grouping')
assert.deepEqual(Array.from(card3.items[0].toplevels), [A, B])
assert.equal(card3.items[0].identityToplevel, null)
assert.equal(card4.items.length, 2)

const E = chrome('E')
windows = windows.concat([E])
handles.push({ wayland: E, address: '0xe5',
  lastIpcObject: { workspace: { id: 3 }, monitor: 0 } })
result = flat()
w3 = matching(result, 'id:3')
assert.equal(w3.length, 1)
assert.deepEqual(Array.from(w3[0].toplevels), [A, B, E])

handles[1].lastIpcObject.workspace = { id: 4 }
result = flat()
w3 = matching(result, 'id:3')
w4 = matching(result, 'id:4')
assert.equal(w3.length, 1, 'saved source pair keeps a stable local group identity')
assert.deepEqual(Array.from(w3[0].toplevels), [A, E])
assert.equal(w4.length, 3)
assert.deepEqual(Array.from(w4, item => item.toplevels.length), [1, 1, 1])
const bothWorkspaces = onlyWorkspace3.concat([
  { desktopId: 'com.google.Chrome', workspace: 'id:4' }
])
result = flat(bothWorkspaces)
w4 = matching(result, 'id:4')
assert.equal(w4.length, 1)
assert.deepEqual(Array.from(w4[0].toplevels), [B, C, D])

handles[1].lastIpcObject.workspace = { id: 3 }
assert.deepEqual(Array.from(matching(flat(), 'id:3')[0].toplevels), [A, B, E])

handles[1].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
const minimized = flat(onlyWorkspace3, {
  '0xb2': { workspace: '3', monitor: '0' }
})
assert.deepEqual(Array.from(matching(minimized, 'id:3')[0].toplevels), [A, B, E])

handles[3].lastIpcObject.workspace = { name: 'special:scratch' }
const unresolved = flat(bothWorkspaces)
const dItem = unresolved.find(item => item.toplevels.indexOf(D) >= 0)
assert.equal(dItem.toplevels.length, 1)
assert.equal(dItem.identityToplevel, D)

handles[1].lastIpcObject.workspace = { id: 3 }
A.browserProfileKey = 'Profile 1'
E.browserProfileKey = 'Profile 2'
const profileMixed = matching(flat(), 'id:3')[0]
assert.deepEqual(Array.from(profileMixed.toplevels), [A, B, E])

assert.equal(DockWorkspaceGroupModel.workspaceGroupEnabled(
  onlyWorkspace3, 'COM.GOOGLE.CHROME', 'id:3'), true)
assert.equal(DockWorkspaceGroupModel.workspaceGroupEnabled(
  onlyWorkspace3, 'com.google.Chrome', 'id:4'), false)
assert.equal(DockWorkspaceGroupModel.workspaceGroupEnabled(
  onlyWorkspace3, 'com.google.Chrome', 'special:x'), false)
assert.deepEqual(Array.from(DockWorkspaceGroupModel.normalizeWorkspaceGroups(onlyWorkspace3), entry =>
  [entry.desktopId, entry.workspace]), [['com.google.Chrome', 'id:3']])

const valid = ConfigModel.validatePatch({ workspaceGroups: bothWorkspaces }, schema)
assert.equal(valid.ok, true)
for (const invalidGroups of [
  {},
  [{ desktopId: 'com.google.Chrome', workspace: '3' }],
  [{ desktopId: 'com.google.Chrome.desktop', workspace: 'id:3' }],
  [{ desktopId: ' com.google.Chrome', workspace: 'id:3' }],
  [{ desktopId: 'com.google.Chrome', workspace: 'special:scratch' }],
  [{ desktopId: 'com.google.Chrome', workspace: 'name:' }],
  [{ desktopId: 'com.google.Chrome', workspace: 'name:bad;dispatch' }],
  [{ desktopId: 'com.google.Chrome', workspace: 'id:03' }],
  [{ desktopId: 'com.google.Chrome', workspace: 'id:3', extra: true }],
  [
    { desktopId: 'com.google.Chrome', workspace: 'id:3' },
    { desktopId: 'COM.GOOGLE.CHROME', workspace: 'id:3' }
  ]
]) {
  assert.equal(ConfigModel.validatePatch({ workspaceGroups: invalidGroups }, schema).ok, false,
    `invalid workspaceGroups must reject atomically: ${JSON.stringify(invalidGroups)}`)
}

const current = {
  pinned: ['org.example.One'], hiddenApplications: ['org.example.Hidden'],
  groupWindows: true,
  workspaceGroups: [{ desktopId: 'org.mozilla.firefox', workspace: 'id:8' }],
  concurrentExtensionValue: { keep: 'exactly' }
}
let intent = ConfigModel.workspaceGroupIntent(
  current, [], 'group', { desktopId: 'com.google.Chrome', workspace: 'id:3' })
assert.equal(intent.ok, true)
assert.deepEqual(JSON.parse(JSON.stringify(intent.settings.concurrentExtensionValue)), { keep: 'exactly' })
assert.equal(intent.settings.groupWindows, true, 'legacy stored value is preserved byte-for-value')
assert.deepEqual(Array.from(intent.settings.workspaceGroups, entry => entry.workspace), ['id:8', 'id:3'])
const later = { ...intent.settings, concurrentExtensionValue: { keep: 'newer' }, margin: 77 }
intent = ConfigModel.workspaceGroupIntent(
  later, [], 'ungroup', { desktopId: 'com.google.Chrome', workspace: 'id:3' })
assert.equal(intent.ok, true)
assert.deepEqual(JSON.parse(JSON.stringify(intent.settings.concurrentExtensionValue)), { keep: 'newer' })
assert.equal(intent.settings.margin, 77)
assert.deepEqual(Array.from(intent.settings.workspaceGroups, entry => entry.workspace), ['id:8'])

assert.equal(DockWorkspaceGroupModel.legacyGroupingActive(true), false)
assert.equal(flat([]).filter(item => item.toplevels.length > 1).length, 0,
  'old groupWindows=true cannot create local groups when workspaceGroups is empty')
const deprecatedEnable = ConfigModel.validatePatch({ groupWindows: true }, schema)
assert.equal(deprecatedEnable.ok, false)
assert.match(deprecatedEnable.errors[0].message, /workspaceGroups|Group Windows/i)
const unrelated = ConfigModel.applyPatch(current, { iconSize: 50 }, schema)
assert.equal(unrelated.ok, true)
assert.equal(unrelated.settings.groupWindows, true)
assert.deepEqual(JSON.parse(JSON.stringify(unrelated.settings.workspaceGroups)),
  JSON.parse(JSON.stringify(current.workspaceGroups)))

console.log('CM-03 workspace-local grouping, persistence and legacy transition tests: PASS')
