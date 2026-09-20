import assert from 'node:assert/strict'
import { loadModel, plain } from './host_harness.mjs'

const Model = loadModel('DockHerdrModel')

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
