import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = path => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const plain = value => JSON.parse(JSON.stringify(value))
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(read(`components/${name}.js`).replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}
const DockModel = model('DockModel')
const DockIconModel = model('DockIconModel')
const hostSource = read('DockHost.qml')
const writerSource = hostSource.match(/^  FileView \{[\s\S]*?^  \}/m)[0]

// Execute production methods, literal defaults and FileView signal bodies.
// Only the writer/session dependencies are substituted; this is not a QML or
// filesystem test. In particular, the double models FileView's identical-text
// suppression and its cache retaining attempted bytes even after failure.
function fixture() {
  const calls = []
  const attempts = []
  const warnings = []
  const outcomes = []
  let cached = ''
  let disk = ''
  let pending = null
  const host = vm.createContext({
    DockModel, DockIconModel,
    DockWindowModel: model('DockWindowModel', { DockModel }),
    TrashModel: model('DockTrashModel'),
    FileViewError: { toString: error => error === 3 ? 'Permission denied' : 'Unknown error' },
    settings: { pinned: ['code'], showTrash: false, iconSize: 42,
      iconOverrides: { code: 'file:///tmp/code.png' }, unrelated: { keep: true } },
    configPath: '/disposable-test-config/dock.json', showTrash: false,
    Qt: { callLater() {} }, console: { warn: (...args) => warnings.push(args) }
  })
  host.root = host
  for (const match of hostSource.matchAll(/^  property (?:string|int|bool) (\w+): ("[^"\n]*"|true|false|\d+)\s*$/gm))
    host[match[1]] = vm.runInContext(match[2], host)
  vm.runInContext(hostSource.match(/^  function [\s\S]*?^  }/gm).join('\n'), host)

  function signal(name, parameter = '') {
    const match = writerSource.match(new RegExp(
      `^    ${name}: (?:${parameter ? `${parameter} => ` : ''})(\\{[\\s\\S]*?^    \\}|[^\\n]+)`, 'm'))
    return match ? vm.runInContext(`((${parameter}) => ${match[1]})`, host) : () => {}
  }
  const saved = signal('onSaved')
  const failed = signal('onSaveFailed', 'error')
  const loaded = signal('onLoaded')
  function complete(error = null) {
    assert.ok(pending, 'a completion must belong to an accepted write')
    cached = pending.text
    if (error === null) disk = cached
    pending = null
    if (error === null) saved()
    else failed(error)
  }
  const writer = {
    text: () => cached,
    setText(text) {
      calls.push(text)
      if (text === cached) return // Native FileView emits no signal for this.
      assert.equal(pending, null, 'preserved blocking writer has one write at a time')
      assert.equal(host.settingsWriteState, 'saving', 'saving precedes the writer call')
      pending = { text, errorAtStart: host.settingsWriteError }
      attempts.push(pending)
      if (outcomes.length) complete(outcomes.shift())
    }
  }
  // Evaluate the production cached-text binding, rather than reproduce it.
  const cacheBinding = writerSource.match(/^    readonly property string cachedText: (.+)$/m)
  Object.defineProperty(writer, 'cachedText', {
    get: () => cacheBinding ? vm.runInContext(cacheBinding[1], host) : undefined
  })
  host.configFile = writer
  host.text = writer.text // FileView-local name used by its binding/loaded handler.
  return {
    host, calls, attempts, warnings, outcomes, complete,
    disk: () => disk,
    load(text) { cached = disk = text; loaded() }
  }
}

let count = 0
function check(name, run) {
  run()
  count++
  console.log(`PASS: ${name}`)
}

check('idle on startup/load; saved only after an actual completion', () => {
  const f = fixture()
  assert.equal(f.host.settingsWriteState, 'idle')
  assert.equal(f.host.settingsWriteError, '')
  f.load(JSON.stringify(plain(f.host.settings)))
  assert.equal(f.host.settingsWriteState, 'idle', 'loading is not saving')
  assert.equal(f.calls.length, 0)
  assert.equal(f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg').ok, true)
  assert.equal(f.host.settingsWriteState, 'saving', 'returning without a signal is not success')
  assert.equal(f.host.settings.iconOverrides.chatgpt, 'file:///tmp/chatgpt.svg')
  assert.equal(JSON.parse(f.disk()).iconOverrides.chatgpt, undefined)
  f.complete()
  assert.equal(f.host.settingsWriteState, 'saved')
  assert.equal(f.host.settingsWriteError, '')
  assert.deepEqual(JSON.parse(f.disk()), plain(f.host.settings))
})

check('failed Apply retains optimistic settings and the existing diagnostic', () => {
  const f = fixture()
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  const session = plain(f.host.settings)
  f.complete(3)
  assert.equal(f.host.settingsWriteState, 'error')
  assert.match(f.host.settingsWriteError, /retry/i)
  assert.match(f.host.settingsWriteError, /session/i)
  assert.match(f.host.settingsWriteError, /Permission denied/)
  assert.deepEqual(plain(f.host.settings), session)
  assert.equal(f.disk(), '', 'the failed atomic-write double leaves disk unchanged')
  assert.deepEqual(f.warnings, [[`Dock: could not save ${f.host.configPath}:`, 3]])
})

check('failed Restore can retry even after its only override row disappears', () => {
  const f = fixture()
  f.load(JSON.stringify(plain(f.host.settings), null, 2) + '\n')
  assert.equal(f.host.saveIconOverride('code', '').ok, true)
  f.complete(3)
  assert.deepEqual(plain(f.host.settings.iconOverrides), {})
  assert.equal(f.host.settingsWriteState, 'error')
  assert.equal(JSON.parse(f.disk()).iconOverrides.code, 'file:///tmp/code.png')
  const revision = f.host.iconReloadRevision
  const warning = f.host.settingsWriteError
  f.host.retrySettingsWrite()
  assert.equal(f.attempts.length, 2, 'Retry must bypass failed-byte cache suppression')
  assert.equal(f.host.settingsWriteState, 'saving')
  assert.equal(f.host.settingsWriteError, warning, 'Retry is not durable recovery yet')
  assert.equal(f.host.iconReloadRevision, revision, 'Retry does not reapply an icon operation')
  f.complete()
  assert.deepEqual(JSON.parse(f.disk()).iconOverrides, {})
  assert.equal(f.host.settingsWriteState, 'saved')
  assert.equal(f.host.settingsWriteError, '')
})

check('Retry saves both latest app choices and all unrelated settings', () => {
  const f = fixture()
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  f.complete(3)
  f.host.saveIconOverride('code', '/tmp/code-new.png')
  f.complete(3)
  f.host.saveSetting('iconSize', 64)
  f.complete(3)
  const latest = plain(f.host.settings)
  const revision = f.host.iconReloadRevision
  f.host.retrySettingsWrite()
  assert.deepEqual(JSON.parse(f.attempts.at(-1).text), latest)
  assert.equal(f.host.iconReloadRevision, revision)
  f.complete()
  assert.deepEqual(JSON.parse(f.disk()), latest)
  assert.deepEqual(JSON.parse(f.disk()).iconOverrides, {
    code: 'file:///tmp/code-new.png', chatgpt: 'file:///tmp/chatgpt.svg'
  })
  assert.deepEqual(JSON.parse(f.disk()).unrelated, { keep: true })
})

check('Retry does not resurrect a restored mapping after another app changes', () => {
  const f = fixture()
  f.host.saveIconOverride('code', '')
  f.complete(3)
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  f.complete(3)
  f.host.retrySettingsWrite()
  f.complete()
  assert.deepEqual(JSON.parse(f.disk()).iconOverrides, { chatgpt: 'file:///tmp/chatgpt.svg' })
})

check('repeated identical retries write again with a bounded whitespace variant', () => {
  const f = fixture()
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  f.complete(3)
  const latest = plain(f.host.settings)
  for (let i = 0; i < 4; i++) {
    const before = f.attempts.length
    f.host.retrySettingsWrite()
    assert.equal(f.attempts.length, before + 1)
    assert.deepEqual(JSON.parse(f.attempts.at(-1).text), latest)
    assert.equal(f.host.settingsWriteState, 'saving')
    f.complete(i === 3 ? null : 3)
  }
  assert.equal(new Set(f.attempts.map(attempt => attempt.text)).size, 2)
  assert.equal(f.host.settingsWriteState, 'saved')
  assert.equal(f.host.settingsWriteError, '')
})

check('identical Apply and ordinary saves never stick at saving on native no-op', () => {
  const f = fixture()
  f.load(JSON.stringify(plain(f.host.settings), null, 2) + '\n')
  f.host.saveIconOverride('code', '/tmp/code.png')
  assert.equal(f.attempts.length, 1)
  f.complete()
  f.host.saveSetting('iconSize', f.host.settings.iconSize)
  assert.equal(f.attempts.length, 2)
  f.complete()
  assert.equal(f.host.settingsWriteState, 'saved')
})

check('a later complete-settings save clears an earlier whole-config warning', () => {
  const f = fixture()
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  f.complete(3)
  const warning = f.host.settingsWriteError
  f.host.saveSetting('iconSize', 64)
  assert.equal(f.host.settingsWriteState, 'saving')
  assert.equal(f.host.settingsWriteError, warning)
  f.complete()
  assert.equal(f.host.settingsWriteState, 'saved')
  assert.equal(f.host.settingsWriteError, '')
  assert.equal(JSON.parse(f.disk()).iconOverrides.chatgpt, 'file:///tmp/chatgpt.svg')
})

check('invalid operations and no-op Restore do not write or change status', () => {
  const f = fixture()
  for (const phase of ['idle', 'saving', 'error', 'saved']) {
    if (phase === 'saving') f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
    if (phase === 'error') f.complete(3)
    if (phase === 'saved') { f.host.retrySettingsWrite(); f.complete() }
    const before = [f.calls.length, f.host.iconReloadRevision,
      f.host.settingsWriteState, f.host.settingsWriteError, plain(f.host.settings)]
    for (const [id, source] of [['code', 'relative.svg'], ['unknown-application', '/tmp/a.png'],
      ['__proto__', '/tmp/a.png'], ['', '/tmp/a.svg']])
      assert.equal(f.host.saveIconOverride(id, source).ok, false)
    assert.equal(f.host.saveIconOverride('not-configured', '').changed, false)
    assert.deepEqual([f.calls.length, f.host.iconReloadRevision,
      f.host.settingsWriteState, f.host.settingsWriteError, plain(f.host.settings)], before)
  }
})

check('blocking completion/failure signals are not overwritten after setText returns', () => {
  const f = fixture()
  assert.match(writerSource, /^    blockWrites: true$/m)
  assert.doesNotMatch(writerSource, /^    atomicWrites: false$/m)
  f.outcomes.push(null, 3, null)
  f.host.saveIconOverride('chatgpt', '/tmp/chatgpt.svg')
  assert.equal(f.host.settingsWriteState, 'saved')
  f.host.saveIconOverride('code', '/tmp/new.png')
  assert.equal(f.host.settingsWriteState, 'error')
  f.host.retrySettingsWrite()
  assert.equal(f.host.settingsWriteState, 'saved')
  assert.equal(f.host.settingsWriteError, '')
  assert.deepEqual(JSON.parse(f.disk()), plain(f.host.settings))
})

console.log(`Icon settings write behavior: ${count} cases passed (controlled writer, not real FileView/filesystem evidence)`)
