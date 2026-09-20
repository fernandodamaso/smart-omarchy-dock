import assert from 'node:assert/strict'
import { loadModel, plain, read } from './host_harness.mjs'
import { sidebarFixture } from './sidebar_fixture.mjs'

const Model = loadModel('DockHerdrModel')
const Sidebar = loadModel('DockSidebarModel')
const desktopModel = loadModel('DockDesktopModel')

function client(pid, startTime, ancestors) {
  return { pid, startTime, ancestors: ancestors || [] }
}

function server(id, clients) {
  return { id, clients: clients || [] }
}

function windowRow(key, pid, startTime) {
  return { key, pid, startTime }
}

// Unique terminal ancestor matches one window.
{
  const servers = [
    server('local-a', [
      client(41, 41, [
        { pid: 40, startTime: 40 },
        { pid: 1, startTime: 1 },
      ]),
    ]),
  ]
  const windows = [windowRow('win:ghostty', 40, 40)]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, { 'win:ghostty': 'local-a' })
  assert.deepEqual(result.unmatchedServerIds, [])
}

// Inner+outer windows: only the closest matching ancestor associates.
{
  const servers = [
    server('local-a', [
      client(41, 41, [
        { pid: 40, startTime: 40 },
        { pid: 10, startTime: 10 },
      ]),
    ]),
  ]
  const windows = [
    windowRow('win:inner', 40, 40),
    windowRow('win:outer', 10, 10),
  ]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, { 'win:inner': 'local-a' })
  assert.equal(result.byWindowKey['win:outer'], undefined)
  assert.deepEqual(result.unmatchedServerIds, [])
}

// Nearest identity shared by multiple windows: no farther fallback.
{
  const servers = [
    server('local-a', [
      client(41, 41, [
        { pid: 40, startTime: 40 },
        { pid: 10, startTime: 10 },
      ]),
    ]),
  ]
  const windows = [
    windowRow('win:a', 40, 40),
    windowRow('win:b', 40, 40),
    windowRow('win:far', 10, 10),
  ]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds, ['local-a'])
}

// Multiple independently proven windows for one session (two clients).
{
  const servers = [
    server('local-shared', [
      client(11, 11, [{ pid: 100, startTime: 100 }]),
      client(12, 12, [{ pid: 200, startTime: 200 }]),
    ]),
  ]
  const windows = [
    windowRow('win:one', 100, 100),
    windowRow('win:two', 200, 200),
  ]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {
    'win:one': 'local-shared',
    'win:two': 'local-shared',
  })
  assert.deepEqual(result.unmatchedServerIds, [])
}

// Conflicting servers claiming the same unique window stay unmatched.
{
  const servers = [
    server('a', [client(1, 1, [{ pid: 40, startTime: 40 }])]),
    server('b', [client(2, 2, [{ pid: 40, startTime: 40 }])]),
  ]
  const windows = [windowRow('win:term', 40, 40)]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds.sort(), ['a', 'b'])
}

// Shared terminal PID without exact surface identity stays unmatched.
{
  const servers = [
    server('local-a', [client(41, 41, [{ pid: 40, startTime: 40 }])]),
  ]
  const windows = [
    windowRow('win:a', 40, 40),
    windowRow('win:b', 40, 40),
  ]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds, ['local-a'])
}

// PID reuse (startTime mismatch) and missing clients stay unmatched.
{
  const servers = [
    server('reuse', [client(41, 41, [{ pid: 40, startTime: 40 }])]),
    server('gone', []),
  ]
  const windows = [windowRow('win:term', 40, 99)]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds.sort(), ['gone', 'reuse'])
}

// Never guesses by title / focus / row order: only process identity.
{
  const servers = [
    server('local-a', [client(41, 41, [{ pid: 999, startTime: 1 }])]),
  ]
  const windows = [{
    key: 'win:focused',
    pid: 40,
    startTime: 40,
    title: 'herdr',
    focused: true,
    index: 0,
  }]
  const result = plain(Model.associateWindows(servers, windows))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds, ['local-a'])
}

// --- Phase A bridge: revision/epoch gating and identity merge ---

function request(revision, epoch, targets) {
  return { revision, epoch, targets }
}

// Obsolete metadata reply after window replacement is withheld.
{
  const snap = {
    providerEpoch: 'epoch-a',
    servers: [server('local-a', [client(41, 41, [{ pid: 40, startTime: 40 }])])],
    windowProcesses: {
      revision: 1,
      identities: [{ pid: 40, startTime: 40 }],
    },
  }
  const withheld = Model.resolveAssociations(
    request(2, 'epoch-a', [{ key: 'window:2', pid: 40 }]),
    snap,
  )
  assert.equal(withheld, null)

  const applied = plain(Model.resolveAssociations(
    request(1, 'epoch-a', [{ key: 'window:1', pid: 40 }]),
    snap,
  ))
  assert.deepEqual(applied.byWindowKey, { 'window:1': 'local-a' })
}

// Missing / foreign process identity cannot associate.
{
  const snap = {
    providerEpoch: 'epoch-a',
    servers: [server('local-a', [client(41, 41, [{ pid: 40, startTime: 40 }])])],
    windowProcesses: {
      revision: 3,
      identities: [], // pid 40 unread / foreign UID omitted
    },
  }
  const result = plain(Model.resolveAssociations(
    request(3, 'epoch-a', [{ key: 'window:1', pid: 40 }]),
    snap,
  ))
  assert.deepEqual(result.byWindowKey, {})
  assert.deepEqual(result.unmatchedServerIds, ['local-a'])
}

// Successful use of a real resolved PID/startTime pair.
{
  const snap = {
    providerEpoch: 'epoch-b',
    servers: [server('local-a', [client(41, 41, [{ pid: 40, startTime: 9911 }])])],
    windowProcesses: {
      revision: 4,
      identities: [{ pid: 40, startTime: 9911 }],
    },
  }
  const result = plain(Model.resolveAssociations(
    request(4, 'epoch-b', [{ key: 'win:term', pid: 40 }]),
    snap,
  ))
  assert.deepEqual(result.byWindowKey, { 'win:term': 'local-a' })
  assert.deepEqual(result.unmatchedServerIds, [])
}

// Epoch mismatch withholds even when revision matches.
{
  const snap = {
    providerEpoch: 'epoch-new',
    servers: [server('local-a', [client(41, 41, [{ pid: 40, startTime: 40 }])])],
    windowProcesses: {
      revision: 5,
      identities: [{ pid: 40, startTime: 40 }],
    },
  }
  assert.equal(
    Model.resolveAssociations(
      request(5, 'epoch-old', [{ key: 'window:1', pid: 40 }]),
      snap,
    ),
    null,
  )
}

// Fingerprint changes when the handle/PID set changes, not on workspace alone.
{
  const a = Model.windowProcessFingerprint([
    { key: 'window:1', pid: 40 },
    { key: 'window:2', pid: 50 },
  ])
  const sameAfterWorkspace = Model.windowProcessFingerprint([
    { key: 'window:2', pid: 50 },
    { key: 'window:1', pid: 40 },
  ])
  assert.equal(a, sameAfterWorkspace)
  const replaced = Model.windowProcessFingerprint([
    { key: 'window:3', pid: 40 }, // new handle, reused PID
    { key: 'window:2', pid: 50 },
  ])
  assert.notEqual(a, replaced)
}

// PID normalization: unique positive ints, cap 256, reject junk.
{
  assert.deepEqual(
    plain(Model.normalizeWindowProcessPids([1, 1, 2, 0, -3, 2.5, '9', null])),
    [1, 2],
  )
  const many = Array.from({ length: 300 }, (_, i) => i + 1)
  assert.equal(Model.normalizeWindowProcessPids(many).length, 256)
}

console.log('herdr sidebar model association: PASS')

// --- Phase B: project matched agents into the tree ---

{
  // Matching: agents nest under the associated window; unmatched stay out of the tree.
  const f = sidebarFixture()
  const desktop = desktopModel.build(f.input)
  const registry = Sidebar.reconcileHandles({ nextToken: 1, entries: [] }, f.toplevels)
  const termEntry = registry.entries.find((_, i) => f.toplevels[i].id === 'terminal')
  assert.ok(termEntry)
  const windowKey = termEntry.key
  const snapshot = {
    providerEpoch: 'epoch-b',
    revision: 1,
    servers: [
      { id: 'local-matched', health: 'live', label: 'Matched' },
      { id: 'local-free', health: 'live', label: 'Free' },
    ],
    agents: [
      {
        id: 'local-matched:1:pane-a',
        serverId: 'local-matched',
        connectionGeneration: 1,
        paneId: 'pane-a',
        terminalId: 'term-a',
        name: 'Codex Review',
        agent: 'codex',
        status: 'working',
      },
      {
        id: 'local-matched:1:pane-b',
        serverId: 'local-matched',
        connectionGeneration: 1,
        paneId: 'pane-b',
        name: 'Claude Fix',
        agent: 'claude',
        status: 'idle',
      },
      {
        id: 'local-free:1:pane-z',
        serverId: 'local-free',
        connectionGeneration: 1,
        paneId: 'pane-z',
        name: 'Unmatched Agent',
        agent: 'cursor',
        status: 'blocked',
      },
    ],
    liveCounts: { agents: 3, working: 1, idle: 1, blocked: 1, done: 0, unknown: 0, complete: true },
    completeness: { state: 'complete' },
  }
  const associations = {
    byWindowKey: { [windowKey]: 'local-matched' },
    unmatchedServerIds: ['local-free'],
  }
  const projected = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: snapshot,
    herdrAssociations: associations,
    herdrAssociationsVerified: true,
  }))
  const parent = projected.rows.find(row => row.key === windowKey)
  assert.ok(parent)
  assert.equal(parent.herdrAssociated, true)
  assert.equal(parent.herdrServerId, 'local-matched')
  const agentRows = projected.rows.filter(row => row.kind === 'herdr-agent')
  assert.equal(agentRows.length, 2)
  assert.equal(agentRows[0].title, 'Codex Review')
  assert.equal(agentRows[1].title, 'Claude Fix')
  assert.equal(agentRows[0].key, JSON.stringify(['herdr-agent', windowKey, 'local-matched:1:pane-a']))
  assert.equal(agentRows[0].windowKey, windowKey)
  assert.equal(agentRows[0].providerEpoch, 'epoch-b')
  assert.equal(agentRows[0].serverId, 'local-matched')
  assert.equal(agentRows[0].paneId, 'pane-a')
  assert.equal(agentRows[0].terminalId, 'term-a')
  // Immediately after the associated window.
  const parentIndex = projected.rows.findIndex(row => row.key === windowKey)
  assert.equal(projected.rows[parentIndex + 1].kind, 'herdr-agent')
  assert.equal(projected.rows[parentIndex + 2].kind, 'herdr-agent')
  assert.ok(!projected.rows.some(row => row.title === 'Unmatched Agent'),
    'unmatched agents stay out of the window tree')
  // Tree annotations / compact child metrics.
  assert.equal(agentRows[0].parentKey, windowKey)
  assert.ok(agentRows[0].treeDepth > parent.treeDepth)
  assert.equal(typeof agentRows[0].isLastSibling, 'boolean')
  assert.ok(Array.isArray(agentRows[0].ancestorContinues))

  // Unmatched fallback filter helpers: matched ids excluded.
  const matched = Sidebar.matchedHerdrServerIds(associations)
  assert.equal(matched['local-matched'], true)
  assert.equal(matched['local-free'], undefined)

  // Movement / status: agent keys stay stable when status changes.
  const statusFlip = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: Object.assign({}, snapshot, {
      agents: snapshot.agents.map(agent =>
        agent.id === 'local-matched:1:pane-a'
          ? Object.assign({}, agent, { status: 'done' })
          : agent),
    }),
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched' },
      unmatchedServerIds: ['local-free'],
    },
    herdrAssociationsVerified: true,
  }))
  const flipped = statusFlip.rows.filter(row => row.kind === 'herdr-agent')
  assert.equal(flipped[0].key, agentRows[0].key)
  assert.equal(flipped[0].status, 'done')
  assert.equal(flipped[1].key, agentRows[1].key)

  // Empty healthy inventory vs unavailable / reconnecting / partial.
  assert.equal(Sidebar.herdrStateTitle({ health: 'live' }, {
    liveCounts: { agents: 0, complete: true },
    completeness: { state: 'complete' },
  }), 'No active agents')
  assert.equal(Sidebar.herdrStateTitle({ health: 'connecting' }, {
    liveCounts: null,
    completeness: { state: 'unknown' },
  }), 'Reconnecting')
  assert.equal(Sidebar.herdrStateTitle(null, null), 'Herdr unavailable')
  assert.equal(Sidebar.herdrStateTitle({ health: 'live' }, {
    liveCounts: null,
    completeness: { state: 'partial' },
  }), 'Partial inventory')

  const emptyProjected = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: {
      providerEpoch: 'epoch-b',
      servers: [{ id: 'local-matched', health: 'live' }],
      agents: [],
      liveCounts: { agents: 0, complete: true },
      completeness: { state: 'complete' },
    },
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched' },
      unmatchedServerIds: [],
    },
    herdrAssociationsVerified: true,
  }))
  const emptyChild = emptyProjected.rows.find(row => row.kind === 'herdr-state'
    && row.windowKey === windowKey)
  assert.ok(emptyChild)
  assert.equal(emptyChild.title, 'No active agents')
  assert.equal(emptyChild.actionable, false)

  // Provider loss: preserved parent association emits non-actionable state only.
  const lost = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: null,
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched' },
      unmatchedServerIds: [],
    },
    herdrAssociationsVerified: false,
  }))
  assert.ok(!lost.rows.some(row => row.kind === 'herdr-agent'))
  const lostState = lost.rows.find(row => row.kind === 'herdr-state' && row.windowKey === windowKey)
  assert.ok(lostState)
  assert.equal(lostState.title, 'Herdr unavailable')

  // Unverified preserved parent with a live snapshot still emits only state.
  const pendingAgents = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: snapshot,
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched' },
      unmatchedServerIds: [],
    },
    herdrAssociationsVerified: false,
  }))
  assert.ok(!pendingAgents.rows.some(row => row.kind === 'herdr-agent'))
  const pendingState = pendingAgents.rows.find(row => row.kind === 'herdr-state'
    && row.windowKey === windowKey)
  assert.ok(pendingState)
  assert.equal(pendingState.title, 'Herdr unavailable')
  assert.equal(pendingState.actionable, false)

  // Nonempty partial/truncated snapshot keeps agents and appends a state child.
  const partialSnap = Object.assign({}, snapshot, {
    agents: [snapshot.agents[0]],
    liveCounts: { agents: 1, working: 1, idle: 0, blocked: 0, done: 0, unknown: 0, complete: false },
    completeness: { state: 'partial', truncated: true, agentTruncated: true },
  })
  const partialProjected = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: false,
    herdrSnapshot: partialSnap,
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched' },
      unmatchedServerIds: ['local-free'],
    },
    herdrAssociationsVerified: true,
  }))
  const partialAgents = partialProjected.rows.filter(row =>
    row.kind === 'herdr-agent' && row.windowKey === windowKey)
  const partialStates = partialProjected.rows.filter(row =>
    row.kind === 'herdr-state' && row.windowKey === windowKey)
  assert.equal(partialAgents.length, 1)
  assert.equal(partialStates.length, 1)
  assert.equal(partialStates[0].title, 'Partial inventory')
  assert.equal(partialStates[0].actionable, false)

  // Fallback empty classification: unknown/partial must not claim healthy empty.
  const partialEmpty = Sidebar.herdrFallbackEmptyChild(
    { id: 'local-free', health: 'live' },
    { liveCounts: null, completeness: { state: 'partial' } },
  )
  assert.ok(partialEmpty)
  assert.equal(partialEmpty.title, 'Partial inventory')
  assert.notEqual(partialEmpty.title, 'No active coding agents')
  assert.notEqual(partialEmpty.title, 'No active agents')
  const truncatedEmpty = Sidebar.herdrFallbackEmptyChild(
    { id: 'local-free', health: 'live' },
    {
      liveCounts: { agents: 0, complete: false },
      completeness: { state: 'partial', truncated: true, agentTruncated: true },
    },
  )
  assert.equal(truncatedEmpty.title, 'Partial inventory')
  const healthyEmpty = Sidebar.herdrFallbackEmptyChild(
    { id: 'local-free', health: 'live' },
    { liveCounts: { agents: 0, complete: true }, completeness: { state: 'complete' } },
  )
  assert.equal(healthyEmpty.title, 'No active agents')
  assert.equal(Sidebar.herdrFallbackVisible(snapshot, associations), true)
  assert.equal(Sidebar.herdrFallbackVisible(snapshot, {
    byWindowKey: { [windowKey]: 'local-matched', x: 'local-free' },
    unmatchedServerIds: [],
  }), false)

  // Rail omits nested herdr children (same as browser tabs).
  const rail = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: ({}),
    collapsed: true,
    herdrSnapshot: snapshot,
    herdrAssociations: associations,
    herdrAssociationsVerified: true,
  }))
  assert.ok(!rail.rows.some(row => row.kind === 'herdr-agent' || row.kind === 'herdr-state'))

  // Browser rows still project beside herdr children when both apply.
  const chromeEntry = registry.entries.find((_, i) => f.toplevels[i].id === 'c')
  const withBrowser = plain(Sidebar.project({
    desktop,
    screens: f.screens,
    monitors: f.monitors,
    monitorOrder: [],
    pinned: f.settings.pinned,
    hiddenApplications: f.settings.hiddenApplications,
    registry,
    folds: { ['tabs:' + chromeEntry.key]: true },
    collapsed: false,
    sidebarBrowserTabsEnabled: true,
    browserTabs: {
      [String(f.handles.find(h => h.wayland.id === 'c').address).toLowerCase()]: [
        { targetId: 't1', title: 'Docs', active: true },
      ],
    },
    herdrSnapshot: snapshot,
    herdrAssociations: {
      byWindowKey: { [windowKey]: 'local-matched', [chromeEntry.key]: 'local-matched' },
      unmatchedServerIds: ['local-free'],
    },
    herdrAssociationsVerified: true,
  }))
  assert.ok(withBrowser.rows.some(row => row.kind === 'browser-tab'))
  assert.ok(withBrowser.rows.some(row => row.kind === 'herdr-agent' && row.windowKey === windowKey))
}

// Delegates must not acquire a provider (static source contract).
{
  const agentsView = read('components/DockHerdrAgentsView.qml')
  const widgetView = read('components/DockSidebarWidgetView.qml')
  assert.equal(agentsView.includes('acquire('), false)
  assert.equal(agentsView.includes('herdrService'), false)
  assert.equal(widgetView.includes('.acquire('), false)
  assert.ok(agentsView.includes('never acquires a provider'))
}

console.log('herdr sidebar model projection: PASS')
