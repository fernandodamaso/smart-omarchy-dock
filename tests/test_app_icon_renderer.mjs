import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = path => fs.readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const plain = value => JSON.parse(JSON.stringify(value))
const icons = vm.createContext({})
vm.runInContext(read('components/DockIconModel.js').replace(/^\.pragma library\s*/m, ''), icons)

// All combinations include empty, invalid and duplicate resolutions.
for (const custom of ['', 'same', 'custom', null]) {
  for (const desktop of ['', 'same', 'desktop', undefined]) {
    for (const generic of ['', 'same', 'generic', 42]) {
      const expected = [...new Set([custom, desktop, generic].filter(s => typeof s === 'string' && s))]
      assert.deepEqual(plain(icons.candidates(custom, desktop, generic)), expected)
    }
  }
}

assert.ok(fs.existsSync(new URL('../components/DockAppIcon.qml', import.meta.url)),
  'FDM-879 must provide the bounded DockAppIcon renderer')
const qml = read('components/DockAppIcon.qml')
const methods = qml.match(/^  function [\s\S]*?^  }/gm)
assert.ok(methods?.length, 'exercise production QML methods, not a reimplemented state machine')

// Evaluate the actual readonly binding expressions as well as the methods.
// Image decoding and the QML signal/event engine are substituted here, not tested.
function binding(name) {
  const match = qml.match(new RegExp(`^  readonly property \\w+ ${name}: ([\\s\\S]*?)(?=\\n  [^ \\n]|\\n\\n)`, 'm'))
  assert.ok(match, `missing readonly ${name} binding`)
  return `(${match[1].trim()})`
}
function renderer({ desktop = 'desktop', generic = 'image://icon/generic', overrides = { app: '/tmp/custom.png' } } = {}) {
  const queue = new Set()
  const loads = []
  const clears = []
  const Image = { Null: 0, Ready: 1, Loading: 2, Error: 3 }
  let source = ''
  const artwork = { status: Image.Null, backer: { cache: true } }
  Object.defineProperty(artwork, 'source', {
    get: () => source,
    set(value) {
      source = String(value)
      artwork.status = source ? Image.Loading : Image.Null
      if (source) loads.push({ source, cache: artwork.backer.cache })
      else clears.push(loads.length)
    }
  })
  const scope = vm.createContext({
    DockIconModel: icons, Image, artwork,
    Quickshell: { iconPath: name => name === 'application-x-executable' ? generic : name === 'desktop' ? 'image://icon/desktop' : '' },
    Qt: { callLater: fn => queue.add(fn), resolvedUrl: path => `file:///repo/components/${path}` },
    desktopId: 'app', desktopIcon: desktop, iconOverrides: overrides, reloadRevision: 0,
    profileKey: '', profileName: '', profileAvatarPath: '', profileBadgesEnabled: true,
    componentReady: true, reloadPending: false, attemptSources: [], attemptIndex: 0,
    attemptedOverrides: [], attemptedProfileOverride: '', customFailed: false,
    terminalFallback: false
  })
  scope.root = scope
  vm.runInContext(methods.join('\n'), scope)
  for (const name of ['overrideKey', 'profileOverrideSource', 'overrideSource', 'desktopSource',
      'sourceCandidates', 'usingOverride', 'overrideFailed', 'renderedSource',
      'profileBadgeVisible', 'profileBadgeActive', 'profileBadgeAvatarVisible']) {
    Object.defineProperty(scope, name, { get: () => vm.runInContext(binding(name), scope) })
  }
  function flush() {
    let turns = 0
    while (queue.size) {
      assert.ok(++turns <= 8, 'fallback must not keep scheduling itself')
      const callbacks = [...queue]
      queue.clear()
      callbacks.forEach(fn => fn())
    }
  }
  function fail() {
    const failed = artwork.source
    artwork.status = Image.Error
    scope.rejectSource(failed)
    scope.rejectSource(failed) // duplicate/stale notification must not skip a candidate
    flush()
  }
  scope.requestReload()
  flush()
  return { scope, artwork, Image, loads, clears, flush, fail }
}

const valid = renderer()
assert.deepEqual(valid.loads, [{ source: 'file:///tmp/custom.png', cache: false }])
assert.equal(valid.scope.usingOverride, false)
valid.artwork.status = valid.Image.Ready
assert.equal(valid.scope.usingOverride, true)
assert.equal(valid.scope.renderedSource, 'file:///tmp/custom.png')
assert.equal(valid.scope.overrideFailed, false)
assert.equal(valid.scope.resolveDesktopIcon('/tmp/Legacy Icon.xpm'), 'file:///tmp/Legacy%20Icon.xpm')
assert.equal(valid.scope.resolveDesktopIcon('file:///tmp/Legacy%20Icon.xpm'), 'file:///tmp/Legacy%20Icon.xpm')
for (const input of ['', 'missing-theme-name', 'file://server/a.png', 'https://example.invalid/a.png'])
  assert.equal(valid.scope.resolveDesktopIcon(input), '')

const frozen = Object.freeze({ ' APP.desktop ': '/tmp/custom.png' })
const failures = renderer({ overrides: frozen })
failures.fail()
assert.equal(failures.artwork.source, 'image://icon/desktop')
assert.equal(failures.scope.overrideFailed, true)
assert.equal(failures.scope.usingOverride, false)
failures.fail()
assert.equal(failures.artwork.source, 'image://icon/generic')
failures.fail()
assert.equal(failures.scope.terminalFallback, true)
assert.match(failures.scope.renderedSource, /assets\/lucide\/app-window\.svg$/)
for (let i = 0; i < 5; i++) failures.fail()
assert.deepEqual(failures.loads, [
  { source: 'file:///tmp/custom.png', cache: false },
  { source: 'image://icon/desktop', cache: true },
  { source: 'image://icon/generic', cache: true }
])
assert.deepEqual(frozen, { ' APP.desktop ': '/tmp/custom.png' })

const empty = renderer({ desktop: '', generic: '', overrides: null })
assert.equal(empty.scope.terminalFallback, true)
assert.equal(empty.scope.overrideFailed, false)
assert.deepEqual(empty.loads, [])
const normal = renderer({ overrides: {} })
assert.equal(normal.artwork.source, 'image://icon/desktop')

// Profile-specific artwork wins over the app-wide override; the badge only
// renders when no profile override replaced the icon.
{
  const scoped = renderer({ overrides: { app: '/tmp/custom.png', 'app@profile:Profile 1': '/tmp/work.svg' } })
  assert.equal(scoped.artwork.source, 'file:///tmp/custom.png')
  assert.equal(scoped.scope.profileBadgeVisible, false) // no profile on this window
  scoped.scope.profileKey = 'Profile 1'
  scoped.scope.requestReload()
  scoped.flush()
  assert.equal(scoped.artwork.source, 'file:///tmp/work.svg')
  assert.equal(scoped.loads.at(-1).cache, false)
  assert.equal(scoped.scope.profileBadgeActive, false)
  scoped.artwork.status = scoped.Image.Ready
  assert.equal(scoped.scope.profileBadgeActive, true)
  assert.equal(scoped.scope.profileBadgeVisible, false)
  assert.equal(scoped.scope.profileBadgeAvatarVisible, false)
}

// App-wide custom artwork stays badged, including after a broken profile icon
// falls back to it. Both custom files bypass stale image caching.
{
  const scoped = renderer({ overrides: { app: '/tmp/custom.png', 'app@profile:Profile 1': '/tmp/missing.svg' } })
  scoped.scope.profileKey = 'Profile 1'
  scoped.scope.profileName = 'Work'
  scoped.scope.requestReload()
  scoped.flush()
  assert.deepEqual(scoped.loads.at(-1), { source: 'file:///tmp/missing.svg', cache: false })
  scoped.fail()
  assert.deepEqual(scoped.loads.at(-1), { source: 'file:///tmp/custom.png', cache: false })
  scoped.artwork.status = scoped.Image.Ready
  assert.equal(scoped.scope.usingOverride, true)
  assert.equal(scoped.scope.overrideFailed, true)
  assert.equal(scoped.scope.profileBadgeActive, false)
  assert.equal(scoped.scope.profileBadgeVisible, true)
}

// Badge visibility: profile without artwork shows an initial; avatar path wins.
{
  const scoped = renderer({ overrides: {} })
  scoped.scope.profileKey = 'Profile 1'
  scoped.scope.profileName = 'Work'
  assert.equal(scoped.scope.profileBadgeVisible, false) // artwork not ready yet
  scoped.artwork.status = scoped.Image.Ready
  assert.equal(scoped.scope.profileBadgeVisible, true)
  assert.equal(scoped.scope.profileBadgeAvatarVisible, false)
  scoped.scope.profileAvatarPath = '/home/u/.config/chrome/Profile 1/Google Profile Picture.png'
  assert.equal(scoped.scope.profileBadgeAvatarVisible, true)
  scoped.scope.profileBadgesEnabled = false
  assert.equal(scoped.scope.profileBadgeVisible, false)
}
const genericOnly = renderer({ desktop: 'missing-theme-name', overrides: {} })
assert.equal(genericOnly.artwork.source, 'image://icon/generic')
const duplicate = renderer({ desktop: '/tmp/custom.png', generic: 'file:///tmp/custom.png' })
duplicate.fail()
assert.equal(duplicate.loads.length, 1)
assert.equal(duplicate.scope.terminalFallback, true)

// Same-path reload must first clear the image and bypass only the custom cache.
valid.scope.requestReload()
valid.scope.requestReload()
assert.equal(valid.artwork.source, '')
valid.flush()
assert.equal(valid.loads.length, 2)
assert.equal(valid.loads[1].source, valid.loads[0].source)
assert.equal(valid.loads[1].cache, false)
assert.ok(valid.clears.includes(1))
valid.scope.loadNext() // a late duplicate callback cannot reload the current candidate
assert.equal(valid.loads.length, 2)

// A new request while a fallback is queued supersedes the old attempt list.
const interrupted = renderer()
interrupted.artwork.status = interrupted.Image.Error
interrupted.scope.rejectSource(interrupted.artwork.source)
interrupted.scope.iconOverrides = { app: '/tmp/replacement.svg' }
interrupted.scope.requestReload()
interrupted.flush()
assert.deepEqual(interrupted.loads.map(load => load.source), ['file:///tmp/custom.png', 'file:///tmp/replacement.svg'])
assert.equal(interrupted.scope.overrideFailed, false)
interrupted.scope.rejectSource('file:///tmp/custom.png')
interrupted.flush()
assert.equal(interrupted.loads.length, 2)

// Structural guards supplement, but do not establish, real QML/image behavior.
for (const declaration of ['property string desktopId: ""', 'property string desktopIcon: ""', 'property var iconOverrides: ({})', 'property int reloadRevision: 0',
    'property string profileKey: ""', 'property string profileName: ""', 'property bool profileBadgesEnabled: true'])
  assert.ok(qml.includes(declaration), declaration)
for (const event of ['onSourceCandidatesChanged', 'onDesktopIdChanged', 'onReloadRevisionChanged'])
  assert.match(qml, new RegExp(`${event}: (?:root\\.)?requestReload\\(\\)`))
assert.match(qml, /onStatusChanged:.*root\.rejectSource\(String\(source\)\)/)
assert.match(qml, /asynchronous: true/)
assert.match(qml, /backer\.sourceSize: Qt\.size\(512, 512\)/)
assert.match(qml, /backer\.fillMode: Image\.PreserveAspectFit/)
assert.match(qml, /iconName: "app-window"/)
assert.doesNotMatch(qml, /Timer\s*\{|FileView\s*\{|ColorOverlay\s*\{|MultiEffect\s*\{/)
assert.doesNotMatch(qml, /saveIconOverride|saveSettings|execDetached/)
console.log('App icon renderer candidate/state tests passed (not image decoding or QML runtime evidence)')
