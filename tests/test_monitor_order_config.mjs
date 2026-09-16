import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import { hostHarness, plain, read } from './host_harness.mjs'

function loadModel(name) {
  const source = read('components/' + name + '.js')
  const context = vm.createContext({ console })
  for (const match of source.matchAll(/^\.import "([^"]+)\.js" as (\w+)$/gm))
    context[match[2]] = loadModel(match[1])
  vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ''), context,
    { filename: name })
  return context
}

const defaults = JSON.parse(read('config/dock.json'))
const schema = JSON.parse(read('config/settings-schema.json'))
const ConfigModel = loadModel('DockConfigModel')
const DockModel = loadModel('DockModel')

assert.deepEqual(defaults.workspaceMonitorOrder, [],
  'bundled default uses automatic physical monitor ordering')
assert.equal(schema.settings.workspaceMonitorOrder?.type, 'array')
assert.equal(schema.settings.workspaceMonitorOrder?.format, 'monitor-connectors')
assert.deepEqual(plain(DockModel.settingsDefaults().workspaceMonitorOrder), [])

const validOrders = [
  [],
  ['DP-1'],
  ['HDMI-A-1', 'DP-1'],
  ['Virtual Monitor 1', 'DP-1'],
  ['DP-1', 'dp-1']
]
for (const value of validOrders) {
  assert.equal(ConfigModel.validatePatch({ workspaceMonitorOrder: value }, schema).ok,
    true, JSON.stringify(value))
  assert.deepEqual(plain(DockModel.normalizeSetting('workspaceMonitorOrder', value)), value,
    'valid stored connector order is preserved exactly')
}

const invalidOrders = [
  null,
  {},
  [''],
  [' DP-1'],
  ['DP-1 '],
  ['DP-1', 'DP-1'],
  ['DP-1\n'],
  ['DP-1\u0000'],
  [42]
]
for (const value of invalidOrders) {
  assert.equal(ConfigModel.validatePatch({ workspaceMonitorOrder: value }, schema).ok,
    false, JSON.stringify(value))
  assert.deepEqual(plain(DockModel.normalizeSetting('workspaceMonitorOrder', value)), [],
    'invalid legacy stored state falls back to automatic order without repair')
}
assert.deepEqual(plain(DockModel.normalizeSetting('workspaceMonitorOrder', undefined)), [])

const preferenceReset = ConfigModel.preferenceResetPatch(defaults, schema)
assert.deepEqual(plain(preferenceReset.workspaceMonitorOrder), [],
  'preference reset returns monitor order to automatic')

const h = hostHarness({
  workspaceMonitorOrder: ['DP-1'],
  extensionData: { keep: ['exact'] }
})
const beforeDryWrites = h.writes.length
let reply = h.request('config.apply', {
  patch: { workspaceMonitorOrder: ['HDMI-A-1', 'DP-1'] }, dryRun: true
})
assert.equal(reply.ok, true)
assert.equal(reply.data.dryRun, true)
assert.equal(reply.data.applied, false)
assert.equal(reply.data.requested.workspaceMonitorOrder[0], 'HDMI-A-1')
assert.deepEqual(reply.data.effective.workspaceMonitorOrder, ['HDMI-A-1', 'DP-1'])
assert.equal(h.writes.length, beforeDryWrites, 'dry-run does not persist')
assert.deepEqual(plain(h.host.settings.workspaceMonitorOrder), ['DP-1'])

reply = h.request('config.apply', {
  patch: { workspaceMonitorOrder: ['HDMI-A-1', 'DP-1'] }, dryRun: false
})
assert.equal(reply.ok, true)
assert.equal(reply.data.persisted, true)
assert.deepEqual(plain(h.host.settings.workspaceMonitorOrder), ['HDMI-A-1', 'DP-1'])
assert.deepEqual(plain(h.host.settings.extensionData), { keep: ['exact'] })
assert.deepEqual(JSON.parse(h.writes.at(-1)).extensionData, { keep: ['exact'] })

const invalidBefore = JSON.stringify(h.host.settings)
const invalidWrites = h.writes.length
reply = h.request('config.apply', {
  patch: { workspaceMonitorOrder: ['DP-1', 'DP-1'] }, dryRun: false
})
assert.equal(reply.error.code, 'E_VALIDATION')
assert.equal(JSON.stringify(h.host.settings), invalidBefore)
assert.equal(h.writes.length, invalidWrites, 'rejected array is atomic')

reply = h.request('config.get', { key: 'workspaceMonitorOrder' })
assert.deepEqual(reply.data.settings.workspaceMonitorOrder, ['HDMI-A-1', 'DP-1'])
reply = h.request('config.get', { key: 'workspaceMonitorOrder', effective: true })
assert.deepEqual(reply.data.settings.workspaceMonitorOrder, ['HDMI-A-1', 'DP-1'])
reply = h.request('config.reset', { key: 'workspaceMonitorOrder' })
assert.equal(reply.ok, true)
assert.deepEqual(plain(h.host.settings.workspaceMonitorOrder), [])
assert.deepEqual(plain(h.host.settings.extensionData), { keep: ['exact'] })

const legacy = hostHarness({ workspaceMonitorOrder: [' bad'], extensionData: { keep: true } })
assert.deepEqual(legacy.request('config.get', { key: 'workspaceMonitorOrder' })
  .data.settings.workspaceMonitorOrder, [' bad'], 'requested readback preserves legacy bytes')
assert.deepEqual(legacy.request('config.get', { key: 'workspaceMonitorOrder', effective: true })
  .data.settings.workspaceMonitorOrder, [], 'effective readback safely normalizes legacy state')
assert.deepEqual(plain(legacy.host.settings.extensionData), { keep: true })

console.log('monitor order configuration contract: PASS')
