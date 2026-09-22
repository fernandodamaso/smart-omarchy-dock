import assert from 'node:assert/strict'
import { loadModel, plain } from './host_harness.mjs'
import { sidebarFixture } from './sidebar_fixture.mjs'

const Sidebar = loadModel('DockSidebarModel')
const Herdr = loadModel('DockHerdrModel')
const Desktop = loadModel('DockDesktopModel')
const Interaction = loadModel('DockSidebarInteractionModel')

function projectSession({ transport, host, session, focusAgent, health = 'live' }) {
  const f = sidebarFixture()
  const desktop = Desktop.build(f.input)
  const registry = Sidebar.reconcileHandles({ nextToken: 1, entries: [] }, f.toplevels)
  const entry = registry.entries.find((_, i) => f.toplevels[i].id === 'terminal')
  assert.ok(entry)
  const serverId = transport + '-' + host + '-' + session
  const server = {
    id: serverId, transport, host, session, label: host,
    connectionGeneration: 7, health,
  }
  if (focusAgent !== undefined) server.capabilities = { focusAgent }
  const agents = health === 'live' ? ['a', 'b', 'solo'].map((pane, index) => ({
    id: serverId + ':7:' + pane,
    serverId,
    connectionGeneration: 7,
    paneId: pane,
    terminalId: 'terminal-' + pane,
    workspaceId: 'w',
    workspaceLabel: 'Project',
    tabId: pane === 'solo' ? 'solo-tab' : 'multi-tab',
    tabTitle: pane === 'solo' ? 'Solo tab' : 'Multi-panel tab',
    title: 'Agent ' + pane,
    agent: 'codex',
    status: index === 0 ? 'working' : 'idle',
    live: true,
  })) : []
  const snapshot = {
    providerEpoch: 'epoch-remote-rows', revision: 1, servers: [server], agents,
    liveCounts: health === 'live' ? { agents: agents.length, complete: true } : null,
    completeness: { state: health === 'live' ? 'complete' : 'unknown' },
  }
  const projection = Sidebar.project({
    desktop, registry, screens: f.screens, monitors: f.monitors,
    monitorOrder: [], pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    folds: {}, collapsed: false, herdrSnapshot: snapshot,
    herdrAssociations: { byWindowKey: { [entry.key]: serverId }, unmatchedServerIds: [] },
    herdrAssociationsVerified: true,
  })
  return {
    server, snapshot,
    parent: projection.rows.find(row => row.key === entry.key),
    rows: projection.rows.filter(row => row.windowKey === entry.key),
  }
}

// Exercise the actual projection, not hand-built controller row fixtures.
// Removing the capability copy from multi-panel children must fail this test:
// the production controller and delegate both require that exact metadata.
for (const transport of ['local', 'remote']) {
  for (const focusAgent of [true, false, undefined, 'true']) {
    for (const session of ['default', 'review']) {
      const host = transport === 'local' ? 'local' : 'devbox'
      const f = projectSession({ transport, host, session, focusAgent })
      const expectedFocus = focusAgent === true
      const expectedLabel = transport === 'remote' && session !== 'default'
        ? host + ' · ' + session : host
      assert.equal(f.parent.herdrDisplayLabel, transport === 'remote' ? expectedLabel : 'Herdr')
      const children = f.rows.filter(row => row.kind === 'herdr-agent')
      assert.equal(children.length, 2)
      for (const child of children) {
        assert.equal(child.focusAgentSupported, expectedFocus,
          transport + ': multi-panel child must preserve the server focus capability')
        assert.equal(child.actionable, expectedFocus)
        assert.equal(child.transport, transport)
        assert.equal(child.host, host)
        assert.equal(child.session, session)
        assert.equal(child.serverLabel, expectedLabel)
        assert.equal(child.serverConnectionGeneration, 7)
        assert.equal(child.providerEpoch, 'epoch-remote-rows')
        assert.equal(child.serverId, f.server.id)
        assert.equal(child.connectionGeneration, 7)
        assert.equal(child.agentId, f.server.id + ':7:' + child.paneId)
        assert.equal(child.terminalId, 'terminal-' + child.paneId)
        assert.equal(Interaction.rowHoverFillEligible(child.kind,
          child.actionable === true && child.focusAgentSupported === true), expectedFocus)
      }
      for (const tab of f.rows.filter(row => row.kind === 'herdr-tab')) {
        assert.equal(tab.focusAgentSupported, expectedFocus)
        assert.equal(tab.actionable, expectedFocus)
        assert.equal(tab.transport, transport)
        assert.equal(tab.serverLabel, expectedLabel)
      }
      assert.equal(children.find(row => row.paneId === 'a').status, 'working',
        'focus support must never suppress the working status')
    }
  }
}

// Default/named remote state rows stay under the proven hosting window.
for (const health of ['connecting', 'unavailable']) {
  const f = projectSession({ transport: 'remote', host: 'devbox', session: 'review',
    focusAgent: false, health })
  assert.equal(f.parent.herdrDisplayLabel, 'devbox · review')
  assert.equal(f.rows.length, 1)
  assert.equal(f.rows[0].kind, 'herdr-state')
  assert.equal(f.rows[0].title, health === 'connecting' ? 'Reconnecting' : 'Herdr unavailable')
  assert.equal(f.rows[0].actionable, false)
  assert.equal(f.parent.herdrStatusCounts.agents, 0)
}

// Remote association uses local TUI ancestry, never remote pane PID/title.
const servers = ['local', 'remote-a', 'remote-b'].map((id, index) => ({
  id, transport: index === 0 ? 'local' : 'remote',
  host: index === 0 ? 'local' : id, session: 'review', label: id,
  clients: [{ pid: 101 + index, startTime: 1001 + index,
    ancestors: [{ pid: 201 + index, startTime: 2001 + index },
      { pid: 900, startTime: 9000 }] }],
}))
const windows = servers.map((server, index) => ({
  key: 'window-' + server.id, pid: 201 + index, startTime: 2001 + index,
  title: 'same title',
})).concat([{ key: 'outer', pid: 900, startTime: 9000 }])
const associated = plain(Herdr.associateWindows(servers, windows))
assert.deepEqual(associated.byWindowKey, {
  'window-local': 'local', 'window-remote-a': 'remote-a', 'window-remote-b': 'remote-b',
})
assert.deepEqual(associated.unmatchedServerIds, [])
const ambiguous = plain(Herdr.associateWindows(servers, windows.concat([
  { key: 'ambiguous-surface', pid: 202, startTime: 2002 },
])))
assert.equal(ambiguous.byWindowKey['window-remote-a'], undefined)
assert.equal(ambiguous.byWindowKey.outer, undefined)
assert.deepEqual(ambiguous.unmatchedServerIds, ['remote-a'])
assert.equal(Sidebar.herdrFallbackVisible({ servers }, ambiguous), true)
assert.notEqual(Herdr.serverDisplayLabel(servers[1]), Herdr.serverDisplayLabel(servers[2]))

console.log('herdr remote and local multi-panel projection: PASS')
