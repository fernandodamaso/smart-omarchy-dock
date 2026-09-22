import assert from 'node:assert/strict'
import { interactionFixture } from './sidebar_interaction_fixture.mjs'

function herdrFixture() {
  const f = interactionFixture()
  const windowRow = f.controller.projection.rows[0]
  const windowKey = windowRow.key
  const agentKey = JSON.stringify(['herdr-agent', windowKey, 'srv:1:pane-a'])
  const tabKey = JSON.stringify(['herdr-tab', windowKey, 'ws1', 'tab1'])
  const multiTabKey = JSON.stringify(['herdr-tab', windowKey, 'ws1', 'tab2'])
  const shared = {
    windowKey,
    providerEpoch: 'epoch-1',
    serverId: 'srv',
    connectionGeneration: 1,
    nested: true,
    toplevel: windowRow.toplevel,
    address: windowRow.address,
    desktopId: '',
    workspaceIdentity: windowRow.workspaceIdentity,
    monitorIdentity: windowRow.monitorIdentity,
    transport: 'local',
    host: 'local',
    session: 'default',
    focusAgentSupported: true,
  }
  const agentRow = Object.assign({}, shared, {
    kind: 'herdr-agent',
    key: agentKey,
    agentId: 'srv:1:pane-a',
    paneId: 'pane-a',
    terminalId: 'term-a',
    actionable: true,
  })
  const soleTab = Object.assign({}, shared, {
    kind: 'herdr-tab',
    key: tabKey,
    agentId: 'srv:1:pane-b',
    paneId: 'pane-b',
    terminalId: 'term-b',
    actionable: true,
  })
  const multiTab = Object.assign({}, shared, {
    kind: 'herdr-tab',
    key: multiTabKey,
    agentId: 'srv:1:pane-m',
    paneId: 'pane-m',
    terminalId: 'term-m',
    actionable: true,
    groupHeader: true,
  })
  f.controller.projection.rows.push(agentRow, soleTab, multiTab)
  f.controller.herdrAssociations = { byWindowKey: { [windowKey]: 'srv' }, unmatchedServerIds: [] }
  const focusCalls = []
  let focusSeq = 0
  const provider = {
    focusAgent(target) {
      focusCalls.push(Object.assign({}, target))
      focusSeq += 1
      return 'focus-' + String(focusSeq)
    },
  }
  f.controller.host.herdrService = provider
  f.controller.widgetView = () => ({ provider })
  f.focusCalls = focusCalls
  f.agentRow = agentRow
  f.soleTab = soleTab
  f.multiTab = multiTab
  f.windowKey = windowKey
  return f
}

const f = herdrFixture()
const c = f.controller

const captured = c.captureTarget(f.agentRow.key)
assert.ok(captured)
assert.equal(captured.paneId, 'pane-a')
assert.equal(c.dragSourceLocation(captured), null, 'herdr rows are not drag sources')

assert.equal(c.activateTarget(captured, false, 'DP-1', 0), true)
assert.equal(f.focusCalls.length, 1)
assert.equal(c.latestFocusRequestId, 'focus-1')
assert.equal(f.focusCalls[0].paneId, 'pane-a')
// First activation does not raise yet — waits for focus success.
assert.equal(f.requests.length + f.batches.length, 0)

// Modifier on release → no focus.
f.focusCalls.length = 0
assert.equal(c.activateTarget(captured, false, 'DP-1', 1), false)
assert.equal(f.focusCalls.length, 0)
assert.equal(c.activateTarget(captured, true, 'DP-1', 0), false)

// Same-agent coalesce while pending.
assert.equal(c.activateTarget(captured, false, 'DP-1', 0), true)
assert.equal(f.focusCalls.length, 0, 'duplicate same-agent request coalesces')

// Success raises window then re-focuses to defeat tab restore.
f.focusCalls.length = 0
f.clear()
c.onHerdrFocusFinished('focus-1', true, '')
assert.match(JSON.stringify(f.requests.concat(f.batches)), /focuswindow|0x1/)
assert.equal(f.focusCalls.length, 1, 'confirm focus after raise')
assert.equal(f.focusCalls[0].paneId, 'pane-a')
assert.equal(c.latestFocusRequestId, 'focus-2')
f.focusCalls.length = 0
f.clear()
c.onHerdrFocusFinished('focus-2', true, '')
assert.equal(f.requests.length + f.batches.length, 0, 'confirm success does not raise again')
assert.equal(f.focusCalls.length, 0)

// Removal between press/release.
const gone = herdrFixture()
const goneTarget = gone.controller.captureTarget(gone.agentRow.key)
gone.controller.projection.rows = gone.controller.projection.rows.filter(
  row => row.key !== gone.agentRow.key)
assert.equal(gone.controller.activateTarget(goneTarget, false, 'DP-1', 0), false)
assert.equal(gone.focusCalls.length, 0)

// A then B: delayed A must not raise after B.
const race = herdrFixture()
const a = race.controller.captureTarget(race.agentRow.key)
const b = race.controller.captureTarget(race.soleTab.key)
assert.equal(race.controller.activateTarget(a, false, 'DP-1', 0), true)
assert.equal(race.controller.activateTarget(b, false, 'DP-1', 0), true)
assert.equal(race.focusCalls.length, 2)
assert.equal(race.controller.latestFocusRequestId, 'focus-2')
race.focusCalls.length = 0
race.clear()
race.controller.onHerdrFocusFinished('focus-1', true, '')
assert.equal(race.requests.length + race.batches.length, 0, 'delayed A must not raise after B')
assert.equal(race.focusCalls.length, 0)
race.controller.onHerdrFocusFinished('focus-2', true, '')
assert.match(JSON.stringify(race.requests.concat(race.batches)), /focuswindow|0x1/)
assert.equal(race.focusCalls.length, 1)
assert.equal(race.focusCalls[0].paneId, 'pane-b')

// Failure sets fixed error code only.
const fail = herdrFixture()
const failTarget = fail.controller.captureTarget(fail.agentRow.key)
assert.equal(fail.controller.activateTarget(failTarget, false, 'DP-1', 0), true)
fail.controller.onHerdrFocusFinished('focus-1', false, 'agent_gone')
assert.equal(fail.controller.herdrFocusErrorFor(fail.agentRow.key), 'agent_gone')
assert.deepEqual(Object.keys(fail.controller.pendingFocusByRequest), [])
assert.deepEqual(Object.keys(fail.controller.pendingFocusByAgent), [])

const tab = herdrFixture()
const tabTarget = tab.controller.captureTarget(tab.soleTab.key)
assert.ok(tabTarget)
assert.equal(tab.controller.activateTarget(tabTarget, false, 'DP-1', 0), true)
assert.equal(tab.focusCalls[0].paneId, 'pane-b')

// Multi-panel tab header focuses via its representative pane.
const multi = herdrFixture()
const multiTarget = multi.controller.captureTarget(multi.multiTab.key)
assert.ok(multiTarget, 'multi-panel tab header is actionable')
assert.equal(multiTarget.paneId, 'pane-m')
assert.equal(multi.controller.activateTarget(multiTarget, false, 'DP-1', 0), true)
assert.equal(multi.focusCalls[0].paneId, 'pane-m')

// Capability false or absent: visible row data may exist, but capture/focus is inert.
const unsupported = herdrFixture()
unsupported.agentRow.actionable = false
unsupported.agentRow.focusAgentSupported = false
assert.equal(unsupported.controller.captureTarget(unsupported.agentRow.key), null)
assert.equal(unsupported.focusCalls.length, 0)
assert.deepEqual(Object.keys(unsupported.controller.pendingFocusByRequest), [])

const absent = herdrFixture()
delete absent.soleTab.focusAgentSupported
assert.equal(absent.controller.captureTarget(absent.soleTab.key), null)
assert.equal(absent.focusCalls.length, 0)

// Reconnect/generation change invalidates an already captured action identity.
const staleGeneration = herdrFixture()
const staleTarget = staleGeneration.controller.captureTarget(staleGeneration.agentRow.key)
assert.ok(staleTarget)
staleGeneration.agentRow.connectionGeneration = 2
assert.equal(staleGeneration.controller.activateTarget(staleTarget, false, 'DP-1', 0), false)
assert.equal(staleGeneration.focusCalls.length, 0)

// Server/association disappearance also fails closed without enqueuing.
const serverGone = herdrFixture()
const serverGoneTarget = serverGone.controller.captureTarget(serverGone.agentRow.key)
assert.ok(serverGoneTarget)
serverGone.controller.herdrAssociations = { byWindowKey: {}, unmatchedServerIds: ['srv'] }
assert.equal(serverGone.controller.activateTarget(serverGoneTarget, false, 'DP-1', 0), false)
assert.equal(serverGone.focusCalls.length, 0)

// A source-level supported-remote fixture follows the same exact identity path.
// FDM-980 still advertises real remote servers as unsupported until qualified.
const remoteSupported = herdrFixture()
remoteSupported.agentRow.transport = 'remote'
remoteSupported.agentRow.host = 'devbox'
remoteSupported.agentRow.session = 'review'
const remoteTarget = remoteSupported.controller.captureTarget(remoteSupported.agentRow.key)
assert.ok(remoteTarget)
assert.equal(remoteSupported.controller.activateTarget(remoteTarget, false, 'DP-1', 0), true)
assert.equal(remoteSupported.focusCalls.length, 1)
assert.deepEqual(remoteSupported.focusCalls[0], {
  providerEpoch: 'epoch-1',
  serverId: 'srv',
  connectionGeneration: 1,
  agentId: 'srv:1:pane-a',
  paneId: 'pane-a',
  terminalId: 'term-a',
})

// Immediate provider rejection never creates pending UI state.
const rejected = herdrFixture()
rejected.controller.host.herdrService.focusAgent = () => ''
const rejectedTarget = rejected.controller.captureTarget(rejected.agentRow.key)
assert.ok(rejectedTarget)
assert.equal(rejected.controller.activateTarget(rejectedTarget, false, 'DP-1', 0), false)
assert.deepEqual(Object.keys(rejected.controller.pendingFocusByRequest), [])
assert.deepEqual(Object.keys(rejected.controller.pendingFocusByAgent), [])

console.log('herdr focus activation: PASS')
