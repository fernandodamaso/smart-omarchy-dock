import assert from 'node:assert/strict'
import { loadModel } from './host_harness.mjs'

const Sidebar = loadModel('DockSidebarModel')
const unmatched = { byWindowKey: {}, unmatchedServerIds: [] }
const matched = { byWindowKey: { 'window:1': 'remote' }, unmatchedServerIds: [] }

// #104 hides empty local cards. FDM-981 must still display unmatched remote
// endpoints, including healthy zero, resolving, reconnecting and unavailable.
for (const health of ['live', 'connecting', 'unavailable']) {
  for (const focusAgent of [true, false, undefined]) {
    const remote = {
      id: 'remote', transport: 'remote', host: 'devbox', session: 'review', health,
      capabilities: { focusAgent },
    }
    const snapshot = {
      servers: [remote], agents: [],
      liveCounts: health === 'live' ? { agents: 0, complete: true } : null,
      completeness: { state: health === 'live' ? 'complete' : 'unknown' },
    }
    assert.equal(Sidebar.herdrFallbackVisible(snapshot, unmatched), true,
      health + ': remote state must not disappear merely because no agents are live')
    assert.equal(Sidebar.herdrFallbackVisible(snapshot, matched), false,
      'a matched remote endpoint is represented beneath its window instead')
    const state = Sidebar.herdrFallbackStateChild(remote, snapshot)
    assert.equal(state.title, health === 'live' ? 'No active agents'
      : health === 'connecting' ? 'Reconnecting' : 'Herdr unavailable')
  }
}

const local = { id: 'local', transport: 'local', session: 'review', health: 'live' }
const remote = { id: 'remote', transport: 'remote', host: 'devbox', session: 'review', health: 'unavailable' }
assert.equal(Sidebar.herdrFallbackVisible({ servers: [local], agents: [] }, unmatched), false)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [{ id: 'legacy-local', health: 'live' }], agents: [] }, unmatched), false)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [local, remote], agents: [] }, unmatched), true)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [local, remote], agents: [] }, matched), false)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [local], agents: [{ id: 'a', serverId: 'local' }] }, unmatched), true)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [local], agents: [{ id: 'a', serverId: 'unknown' }] }, unmatched), false)
assert.equal(Sidebar.herdrFallbackVisible({ servers: [{ transport: 'remote' }], agents: [] }, unmatched), false)
assert.equal(Sidebar.herdrFallbackVisible(null, unmatched), false)

console.log('herdr local-empty and remote-state fallback visibility: PASS')
