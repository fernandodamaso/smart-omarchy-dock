import assert from 'node:assert/strict'
import { loadModel } from './host_harness.mjs'
import { qmlMethods } from './sidebar_interaction_fixture.mjs'
import { desktopModel } from './sidebar_fixture.mjs'

// Real DockDesktopModel -> DockSidebarModel -> controller launcher activation.
const SidebarModel = loadModel('DockSidebarModel')
const DockModel = loadModel('DockModel')

function catalogEntry(id, name, icon) {
  const entry = {
    id, name, icon, launches: 0,
    execute() { entry.launches += 1 }
  }
  return entry
}

const ghostty = catalogEntry('com.mitchellh.ghostty', 'Ghostty', 'com.mitchellh.ghostty')
const herdr = catalogEntry('herdr', 'Herdr', 'herdr')
const chrome = catalogEntry('google-chrome', 'Google Chrome', 'google-chrome')
chrome.startupClass = 'google-chrome'
const parsecd = catalogEntry('parsecd', 'Parsec', 'parsecd')
const closedPin = catalogEntry('closed.pin', 'Closed Pin', 'folder')
const applications = [ghostty, herdr, chrome, parsecd, closedPin]

const toplevels = [
  { id: 'g1', appId: 'com.mitchellh.ghostty', title: 'ghostty', activated: true },
  { id: 'h1', appId: 'herdr', title: 'herdr · w1', activated: false },
  { id: 'c1', appId: 'google-chrome', title: 'Inbox', activated: false },
  { id: 'c2', appId: 'Google-chrome', title: 'Docs', activated: false },
  { id: 'p1', appId: 'parsecd', title: 'Parsec', activated: false }
]
const handles = toplevels.map((toplevel, index) => ({
  wayland: toplevel,
  address: `0x${index + 1}`,
  lastIpcObject: { address: `0x${index + 1}`, workspace: { id: 1 }, monitor: 0, urgent: false }
}))
const monitors = [{ id: 0, name: 'DP-1', lastIpcObject: { id: 0, name: 'DP-1', x: 0, y: 0, focused: true, activeWorkspace: { id: 1 } } }]
const screens = [{ name: 'DP-1', x: 0, y: 0, width: 1920, height: 1080 }]
const settings = {
  pinned: ['com.mitchellh.ghostty', 'herdr', 'google-chrome', 'parsecd', 'closed.pin'],
  hiddenApplications: [], workspaceGroups: [], workspaceMonitorScope: 'all',
  workspaceMonitorOrder: [], sortByWorkspace: false
}

function buildInput(apps) {
  return {
    mode: 'sidebar', settings, applications: apps, toplevels, filteredToplevels: toplevels,
    hyprToplevels: handles, hyprWorkspaces: [{ id: 1, name: '1', monitorID: 0 }],
    hyprMonitors: monitors, dockMonitor: monitors[0], minimizedOrigins: {}, focusedWorkspace: 'id:1'
  }
}

function projectFrom(apps) {
  const desktop = desktopModel.build(buildInput(apps))
  const registry = SidebarModel.reconcileHandles(null, toplevels)
  return {
    desktop,
    projection: SidebarModel.project({
      desktop, screens, monitors, monitorOrder: [], pinned: settings.pinned,
      hiddenApplications: settings.hiddenApplications, registry, folds: {}, collapsed: false
    })
  }
}

// Late catalog arrival: empty applications first, then the real catalog.
const early = projectFrom([])
assert.ok(early.projection.launchers.some(row => DockModel.normalizedId(row.desktopId) === 'closed.pin'))
assert.equal(early.projection.launchers.find(row => DockModel.normalizedId(row.desktopId) === 'closed.pin').item.entry, null)

const { desktop, projection } = projectFrom(applications)
for (const item of desktop.workspacePresentation.renderedItems) {
  assert.ok(item.entry, `visible item ${item.desktopId} must carry a desktop entry`)
  assert.equal(item.entry.name, applications.find(entry => DockModel.normalizedId(entry.id) === DockModel.normalizedId(item.desktopId)).name)
}

const byDesktop = Object.create(null)
for (const row of projection.rows) {
  if (!row.desktopId) continue
  const key = DockModel.normalizedId(row.desktopId)
  byDesktop[key] = byDesktop[key] || []
  byDesktop[key].push(row)
}

// Running pins stay strip-owned; hierarchy must not duplicate launcher rows.
assert.ok(!projection.rows.some(r => r.kind === 'launcher'),
  'hierarchy rows must not contain strip launchers')
assert.ok(projection.launchers.some(r => DockModel.normalizedId(r.desktopId) === 'com.mitchellh.ghostty'
  && r.running === true), 'running pinned apps remain on the strip')
assert.ok(!byDesktop['com.mitchellh.ghostty'] || !byDesktop['com.mitchellh.ghostty'].some(r => r.kind === 'application'))
assert.equal(byDesktop['com.mitchellh.ghostty'][0].item.entry.name, 'Ghostty')
const chromeApp = projection.rows.find(r => r.kind === 'application' && DockModel.normalizedId(r.desktopId) === 'google-chrome')
assert.ok(chromeApp)
assert.equal(chromeApp.label, 'Google Chrome')
assert.equal(chromeApp.windowCount, 2)

const launcher = projection.launchers.find(r =>
  DockModel.normalizedId(r.desktopId) === 'closed.pin')
assert.ok(launcher, 'expanded pins live on projection.launchers for the strip')
assert.equal(launcher.label, 'Closed Pin')

const runningPin = projection.launchers.find(r =>
  DockModel.normalizedId(r.desktopId) === 'com.mitchellh.ghostty')
assert.ok(runningPin && runningPin.windows.length >= 1)

// Production indexRowsByKey — not an invented rows.concat(launchers) fixture repair.
const rowsByKey = SidebarModel.indexRowsByKey(projection)
assert.ok(rowsByKey[launcher.key], 'indexRowsByKey must register strip launchers')
assert.ok(rowsByKey[runningPin.key], 'indexRowsByKey must register running pins')
assert.equal(rowsByKey[launcher.key], launcher)
assert.ok(!Object.values(rowsByKey).some(r => r && r.kind === 'launcher'
  && projection.rows.includes(r)), 'launcher index entries are strip-owned objects')
const registry = SidebarModel.reconcileHandles(null, toplevels)
const railProjection = SidebarModel.project({
  desktop, screens, monitors, monitorOrder: [],
  pinned: settings.pinned, hiddenApplications: settings.hiddenApplications,
  registry, folds: { [chromeApp.key]: true }, collapsed: true
})
const unionRows = SidebarModel.indexRowsByKey(projection, railProjection)
assert.ok(unionRows[launcher.key], 'union index keeps strip launchers')
const railChromeWindows = railProjection.rows.filter(r => r.kind === 'window'
  && DockModel.normalizedId(r.desktopId) === 'google-chrome')
assert.ok(railChromeWindows.length >= 1, 'rail projects chrome windows despite fold')
assert.ok(unionRows[railChromeWindows[0].key], 'union lookup includes folded-group rail windows')

const activations = []
const controller = qmlMethods('DockSidebarController.qml', {
  DockModel,
  interactionBusy: false,
  mode: 'sidebar',
  settings: { hiddenApplications: [], pinned: settings.pinned },
  rowsByKey,
  windowActions: {
    isAlive() { return true },
    addressFor() { return '0x1' },
    activateToplevel(toplevel) {
      activations.push(toplevel && toplevel.id)
      return true
    }
  },
  focusReturnTarget: null,
  Qt: { callLater() {} }
})

const closedTarget = { key: launcher.key, kind: 'launcher', desktopId: launcher.desktopId }
assert.equal(controller.targetIsCurrent(closedTarget), true,
  'production rowsByKey must make strip launchers current')
assert.equal(controller.activateTarget(closedTarget, false, 'DP-1'), true)
assert.equal(closedPin.launches, 1, 'closed pin activateTarget executes the desktop entry')

const runningTarget = { key: runningPin.key, kind: 'launcher', desktopId: runningPin.desktopId }
assert.equal(controller.targetIsCurrent(runningTarget), true)
assert.equal(controller.activateTarget(runningTarget, false, 'DP-1'), true)
assert.deepEqual(activations, ['g1'], 'running pin focus-or-launch activates an existing toplevel')
assert.equal(ghostty.launches, 0, 'running pin must not re-execute when windows exist')

// Inline pin-picker requests must forward the activating anchor object.
const anchors = []
const pickerController = qmlMethods('DockSidebarController.qml', {
  pinPickerRequested(anchor) { anchors.push(anchor) },
  Qt: { callLater() {} }
})
const inline = { objectName: 'inline-pin' }
pickerController.requestPinPicker(inline)
assert.deepEqual(anchors, [inline])
pickerController.requestPinPicker()
assert.equal(anchors[1], null)

console.log('sidebar desktop-entry metadata + controller launch flow: PASS')
