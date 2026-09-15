import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = name => fs.readFileSync(new URL(`../components/${name}`, import.meta.url), 'utf8')
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(read(name).replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}
function methods(file, properties) {
  const scope = vm.createContext(properties)
  scope.root = scope
  const bodies = read(file).match(/^  function [\s\S]*?^  }/gm) || []
  vm.runInContext(bodies.join('\n'), scope, { filename: file })
  return scope
}

const DockModel = model('DockModel.js')
const DockWindowModel = model('DockWindowModel.js', { DockModel })
const FullscreenModel = model('DockFullscreenModel.js')
const MenuModel = model('DockMenuModel.js')

const normal = { fullscreen: 0, fullscreenClient: 0 }
const keepBars = { fullscreen: 1, fullscreenClient: 0 }
const hideBars = { fullscreen: 2, fullscreenClient: 2 }
assert.equal(FullscreenModel.mode(normal), 'normal')
assert.equal(FullscreenModel.mode(keepBars), 'keep-bars')
assert.equal(FullscreenModel.mode(hideBars), 'hide-bars')

const transitions = [
  ['normal', 'keep-bars', 'keep-bars'],
  ['normal', 'hide-bars', 'hide-bars'],
  ['keep-bars', 'keep-bars', 'normal'],
  ['keep-bars', 'hide-bars', 'hide-bars'],
  ['hide-bars', 'hide-bars', 'normal'],
  ['hide-bars', 'keep-bars', 'keep-bars']
]
for (const [current, selected, expected] of transitions)
  assert.equal(FullscreenModel.targetMode(current, selected), expected,
    `${current} + ${selected} -> ${expected}`)

assert.equal(
  FullscreenModel.request('0xaaa', 'keep-bars', true),
  'hl.dsp.window.fullscreen_state({ internal = 1, client = 0, action = "set", window = "address:0xaaa" })')
assert.equal(
  FullscreenModel.request('0xaaa', 'hide-bars', true),
  'hl.dsp.window.fullscreen_state({ internal = 2, client = 2, action = "set", window = "address:0xaaa" })')
assert.equal(
  FullscreenModel.request('0xaaa', 'normal', true),
  'hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = "address:0xaaa" })')
assert.equal(FullscreenModel.request('0xaaa', 'hide-bars', false), '',
  'non-Lua fallback must not retarget the focused window implicitly')

const windows = [
  { title: 'Window A', closeCount: 0, close() { this.closeCount++ } },
  { title: 'Window B', closeCount: 0, close() { this.closeCount++ } },
  { title: 'Same app outside represented group', closeCount: 0, close() { this.closeCount++ } }
]
const handles = windows.map((wayland, index) => ({
  wayland,
  address: `0x${index + 1}`,
  lastIpcObject: {
    workspace: { id: index < 2 ? 3 : 8, name: String(index < 2 ? 3 : 8) },
    monitor: 0,
    fullscreen: 0,
    fullscreenClient: 0
  }
}))
const requests = []
const actions = methods('DockWindowActions.qml', {
  DockModel,
  DockWindowModel,
  minimizedOrigins: {},
  minimizedWorkspace: 'special:smartdock-minimized',
  activeToplevel: windows[0],
  ToplevelManager: { toplevels: { values: windows } },
  Quickshell: { execDetached() {} },
  Hyprland: {
    toplevels: { values: handles },
    workspaces: { values: [] },
    monitors: { values: [] },
    focusedWorkspace: { id: 3 },
    usingLua: true,
    dispatch: request => requests.push(request)
  }
})
const context = methods('DockContextActionController.qml', {
  FullscreenModel,
  windowActions: actions,
  Hyprland: actions.Hyprland
})

const targetA = { toplevel: windows[0], address: '0x1' }
const targetB = { toplevel: windows[1], address: '0x2' }
const represented = [targetA, targetB]
assert.equal(context.setFullscreenMode(targetA, 'hide-bars'), true)
assert.deepEqual(requests, [
  'hl.dsp.window.fullscreen_state({ internal = 2, client = 2, action = "set", window = "address:0x1" })'
], 'fullscreen must address Window A, never its sibling')
requests.length = 0
handles[0].lastIpcObject.fullscreen = 2
handles[0].lastIpcObject.fullscreenClient = 2
assert.equal(context.setFullscreenMode(targetA, 'hide-bars'), true)
assert.deepEqual(requests, [
  'hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = "address:0x1" })'
], 'selecting the active mode restores only Window A')

// Represented actions receive exactly the menu membership. The same app's
// window on Workspace 8 must not be broadened into the operation.
requests.length = 0
handles[1].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
actions.minimizedOrigins = {
  '0x2': { workspace: '3', monitor: '0' }
}
assert.equal(context.minimizeVisible(represented, true), true)
assert.equal(requests.length, 1)
assert.match(requests[0], /address:0x1/)
assert.doesNotMatch(requests[0], /address:0x3/)
requests.length = 0
assert.equal(context.restoreMinimized(represented, true), true)
assert.equal(requests.length, 1)
assert.match(requests[0], /address:0x2/)
assert.doesNotMatch(requests[0], /address:0x3/)
assert.equal(context.closeRepresented(represented), true)
assert.equal(windows[0].closeCount, 1)
assert.equal(windows[1].closeCount, 1)
assert.equal(windows[2].closeCount, 0)

const hostileProfile = `Profile O'Malley \"$HOME\" \`echo nope\`; still-data`
const setSpec = MenuModel.iconCommandSpec({
  runtime: 'plugin',
  instance: '4242',
  desktopId: 'com.google.Chrome',
  profile: hostileProfile,
  action: 'set'
})
assert.deepEqual(Array.from(setSpec.argv), [
  'smartdock', '--runtime', 'plugin', '--instance', '4242',
  'icons', 'set', 'com.google.Chrome', '<IMAGE_PATH>', '--profile', hostileProfile
], 'command argv round-trips hostile profile text as data')
assert.match(setSpec.text, /'<IMAGE_PATH>'/,
  'custom image path placeholder must be quoted, not shell syntax')
assert.match(setSpec.text, /'"'"'/,
  'apostrophes must use POSIX single-quote escaping')
assert.ok(!setSpec.text.includes('sh -c'), 'copied commands are data and never shell-executed in tests')

const resetSpec = MenuModel.iconCommandSpec({
  runtime: 'standalone', instance: '9876', desktopId: 'org.example.App',
  profile: '', action: 'reset'
})
assert.deepEqual(Array.from(resetSpec.argv), [
  'smartdock', '--runtime', 'standalone', '--instance', '9876',
  'icons', 'reset', 'org.example.App'
])

const pending = MenuModel.mutationPresentation({
  ok: false,
  error: { code: 'E_BUSY', message: 'save pending' },
  data: { applied: true, persisted: false, writeState: 'saving' }
})
assert.equal(pending.state, 'pending')
assert.equal(pending.durable, false)
const saved = MenuModel.mutationPresentation({
  ok: true,
  data: { applied: true, persisted: true, writeState: 'saved' }
})
assert.equal(saved.state, 'saved')
assert.equal(saved.durable, true)
const failed = MenuModel.mutationPresentation({
  ok: false,
  error: { code: 'E_PERSISTENCE', message: 'disk full' },
  data: { applied: true, persisted: false, writeState: 'error' }
})
assert.equal(failed.state, 'error')
assert.equal(failed.durable, false)
assert.match(failed.message, /disk full/)

console.log('CM-02 exact actions, fullscreen, group scope, persistence and command-copy tests: PASS')
