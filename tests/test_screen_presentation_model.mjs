import assert from 'node:assert/strict'
import {loadModel} from './host_harness.mjs'

const model = loadModel('DockScreenPresentationModel')
// Values created inside the vm realm carry a foreign Object/Array prototype, so
// structural assertions cross realms through JSON, as the other model tests do.
const plain = value => JSON.parse(JSON.stringify(value))
const names = list => [...list].map(screen => screen.name)

function resolve(settings, screens, extra = {}) {
  return model.resolve({
    presentationMode: settings.presentationMode,
    presentationModeByMonitor: settings.presentationModeByMonitor,
    sidebarMonitor: settings.sidebarMonitor,
    workspaceMonitorOrder: settings.workspaceMonitorOrder,
    screens,
    monitors: [],
    previousSidebarScreens: [],
    busy: false,
    ...extra,
  })
}

const twoScreens = [{name: 'DP-1', x: 0, width: 1920, height: 1080},
  {name: 'DP-2', x: 1920, width: 1920, height: 1080}]

// --- Empty override map preserves legacy behavior exactly. ---
{
  const classic = resolve({presentationMode: 'classic', presentationModeByMonitor: {},
    sidebarMonitor: '', workspaceMonitorOrder: []}, twoScreens)
  assert.equal(classic.defaultMode, 'classic')
  assert.deepEqual(names(classic.classicScreens), ['DP-1', 'DP-2'])
  assert.deepEqual(names(classic.sidebarScreens), [],
    'classic default maps no sidebar')
  assert.equal(classic.mixed, false)
  classic.entries.forEach(entry => {
    assert.equal(entry.source, 'inherited')
    assert.equal(entry.mapped, true, 'classic surfaces always map')
  })

  const mirrored = resolve({presentationMode: 'sidebar', presentationModeByMonitor: {},
    sidebarMonitor: '', workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(mirrored.sidebarScreens), ['DP-1', 'DP-2'],
    'sidebar default with empty sidebarMonitor mirrors every screen')
  assert.deepEqual(names(mirrored.classicScreens), [])

  const pinned = resolve({presentationMode: 'sidebar', presentationModeByMonitor: {},
    sidebarMonitor: 'DP-2', workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(pinned.sidebarScreens), ['DP-2'],
    'sidebarMonitor still selects the only sidebar output')
  const unpinned = pinned.entries.find(e => e.connector === 'DP-1')
  assert.equal(unpinned.mode, 'sidebar')
  assert.equal(unpinned.mapped, false,
    'inherited sidebar outside the legacy selection renders nothing, as before')
}

// --- Per-monitor overrides. ---
{
  const mixed = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'DP-2': 'sidebar'}, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  assert.equal(mixed.mixed, true)
  assert.deepEqual(names(mixed.classicScreens), ['DP-1'])
  assert.deepEqual(names(mixed.sidebarScreens), ['DP-2'])
  assert.equal(mixed.modeByMonitor['DP-1'], 'classic')
  assert.equal(mixed.modeByMonitor['DP-2'], 'sidebar')
  assert.equal(mixed.sourceByMonitor['DP-1'], 'inherited')
  assert.equal(mixed.sourceByMonitor['DP-2'], 'override')
  assert.equal(mixed.mappedByMonitor['DP-1'], true)
  assert.equal(mixed.mappedByMonitor['DP-2'], true)

  // Explicit override beats sidebarMonitor in both directions.
  const beatsMonitor = resolve({presentationMode: 'sidebar',
    presentationModeByMonitor: {'DP-1': 'classic'}, sidebarMonitor: 'DP-1',
    workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(beatsMonitor.classicScreens), ['DP-1'],
    'classic override wins over a sidebarMonitor selection')
  assert.deepEqual(names(beatsMonitor.sidebarScreens), [],
    'sidebarMonitor still excludes every other screen: the override only '
    + 'changes DP-1, it does not release the connector pin')

  const joinsMonitor = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'DP-1': 'sidebar'}, sidebarMonitor: 'DP-2',
    workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(joinsMonitor.sidebarScreens), ['DP-1'],
    'sidebarMonitor does not force a classic default onto other screens')

  // Disconnected overrides are retained and inert until the output returns.
  const retained = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'HDMI-A-1': 'sidebar', 'DP-1': 'sidebar'},
    sidebarMonitor: '', workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(retained.sidebarScreens), ['DP-1'])
  assert.deepEqual(plain(retained.overrides), {'DP-1': 'sidebar', 'HDMI-A-1': 'sidebar'},
    'disconnected connector stays in the normalized map')
}

// --- Invalid override bytes normalize away instead of failing resolution. ---
{
  const dirty = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'DP-1': 'vertical', 'BAD\n': 'sidebar', 'DP-2': 'sidebar'},
    sidebarMonitor: '', workspaceMonitorOrder: []}, twoScreens)
  assert.deepEqual(names(dirty.classicScreens), ['DP-1'],
    'a non-mode value is dropped and the connector inherits the default')
  assert.deepEqual(names(dirty.sidebarScreens), ['DP-2'],
    'valid overrides on the same map still apply')
  assert.equal(Object.prototype.hasOwnProperty.call(dirty.overrides, 'BAD\n'), false,
    'control-character connectors never become overrides')
}

// --- Removing an override restores inheritance. ---
{
  const base = {presentationMode: 'sidebar', sidebarMonitor: '',
    workspaceMonitorOrder: []}
  const withOverride = resolve({...base, presentationModeByMonitor: {'DP-1': 'classic'}},
    twoScreens)
  assert.deepEqual(names(withOverride.classicScreens), ['DP-1'])
  const cleared = resolve({...base, presentationModeByMonitor: {}}, twoScreens)
  assert.deepEqual(names(cleared.sidebarScreens), ['DP-1', 'DP-2'],
    'an empty map inherits the default again on every screen')
}

// --- Changing the global default never removes overrides. ---
{
  const overrides = {'DP-1': 'sidebar'}
  const classicDefault = resolve({presentationMode: 'classic',
    presentationModeByMonitor: overrides, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  const sidebarDefault = resolve({presentationMode: 'sidebar',
    presentationModeByMonitor: overrides, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  assert.equal(classicDefault.modeByMonitor['DP-1'], 'sidebar')
  assert.equal(sidebarDefault.modeByMonitor['DP-1'], 'sidebar')
  assert.equal(sidebarDefault.sourceByMonitor['DP-1'], 'override')
  assert.deepEqual(plain(sidebarDefault.overrides), {'DP-1': 'sidebar'},
    'the stored map survives a default change')
  assert.equal(sidebarDefault.sourceByMonitor['DP-2'], 'inherited',
    'the non-overridden screen follows the new default')
  assert.deepEqual(names(sidebarDefault.sidebarScreens), ['DP-1', 'DP-2'],
    'only the override map decides who does not follow the new default')
}

// --- Ordering follows workspaceMonitorOrder through monitorMetadata. ---
{
  const ordered = resolve({presentationMode: 'classic', presentationModeByMonitor: {},
    sidebarMonitor: '', workspaceMonitorOrder: ['DP-2', 'DP-1']}, twoScreens)
  assert.deepEqual([...ordered.entries].map(entry => entry.connector),
    ['DP-2', 'DP-1'])
}

// --- Busy keeps the previous legacy sidebar mapping while connected. ---
{
  const previous = [twoScreens[1]]
  const busy = resolve({presentationMode: 'sidebar', presentationModeByMonitor: {},
    sidebarMonitor: '', workspaceMonitorOrder: []}, twoScreens,
    {previousSidebarScreens: previous, busy: true})
  assert.deepEqual(names(busy.sidebarScreens), ['DP-2'],
    'an in-flight interaction defers adopting new legacy mappings')
}

// --- Panel aggregation flattens only owners that expose panels. ---
{
  const one = {id: 1}
  const two = {id: 2}
  assert.deepEqual(
    plain(model.aggregateSidebarPanels([{panels: [one]}, {panels: []},
      {panels: null}, null, {surface: {panels: [two]}}])),
    [one, two])
  assert.deepEqual(plain(model.aggregateSidebarPanels(null)), [])
}

// --- Gesture tokens capture press-time state and detect staleness. ---
{
  const presentation = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'DP-1': 'sidebar'}, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  const token = model.modeGestureToken(presentation, 'DP-1')
  assert.deepEqual(plain(token), {connector: 'DP-1', mode: 'sidebar',
    source: 'override', hasOverride: true, overrideValue: 'sidebar',
    inheritedMode: 'classic'})
  assert.equal(model.modeGestureTokenCurrent(token, presentation, 'DP-1'), true)

  // The override changed after press → stale.
  const changed = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {'DP-1': 'classic'}, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  assert.equal(model.modeGestureTokenCurrent(token, changed, 'DP-1'), false,
    'a mode change during the gesture invalidates the captured token')

  // The override disappeared after press → stale.
  const inherited = resolve({presentationMode: 'classic',
    presentationModeByMonitor: {}, sidebarMonitor: '', workspaceMonitorOrder: []},
    twoScreens)
  assert.equal(model.modeGestureTokenCurrent(token, inherited, 'DP-1'), false)

  // The inherited default changed after press → stale.
  const redefaulted = resolve({presentationMode: 'sidebar',
    presentationModeByMonitor: {'DP-1': 'sidebar'}, sidebarMonitor: '',
    workspaceMonitorOrder: []}, twoScreens)
  assert.equal(model.modeGestureTokenCurrent(token, redefaulted, 'DP-1'), false,
    'an inherited-state change invalidates the captured token')

  // The source screen disappeared → stale.
  const gone = resolve({presentationMode: 'classic', presentationModeByMonitor: {},
    sidebarMonitor: '', workspaceMonitorOrder: []}, [twoScreens[1]])
  assert.equal(model.modeGestureTokenCurrent(token, gone, 'DP-1'), false,
    'a disconnected source connector can never commit')

  // A token captured on one monitor can never validate against another.
  const inheritedToken = model.modeGestureToken(inherited, 'DP-2')
  assert.equal(model.modeGestureTokenCurrent(inheritedToken, inherited, 'DP-1'), false)

  assert.equal(model.modeGestureToken(presentation, 'HDMI-A-1'), null,
    'unknown connectors capture no token')
  assert.equal(model.modeGestureTokenCurrent(null, presentation, 'DP-1'), false)
}

console.log('Screen presentation resolution, aggregation and gesture tokens: PASS')
