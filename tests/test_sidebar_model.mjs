import assert from 'node:assert/strict'
import fs from 'node:fs'
import { loadModel, plain } from './host_harness.mjs'
import { sidebarFixture, desktopModel } from './sidebar_fixture.mjs'
assert.ok(fs.existsSync(new URL('../components/DockSidebarModel.js', import.meta.url)),
  'SB-02 must provide the production sidebar projection')
const Model = loadModel('DockSidebarModel')
let f = sidebarFixture()
let registry = Model.reconcileHandles(null, f.toplevels)
const project = (options = {}) => Model.project({ desktop: desktopModel.build(f.input),
  screens: f.screens, monitors: f.monitors, monitorOrder: f.settings.workspaceMonitorOrder,
  pinned: f.settings.pinned, registry, folds: {}, collapsed: false, ...options })
let p = project()
const windows = result => result.rows.filter(row => row.kind === 'window')
const allWindows = result => result.monitorSections.flatMap(m => m.workspaces.flatMap(w => w.applications.flatMap(a => a.windows)))
  .concat(result.unassignedWindows)
const findWindow = (result, id) => allWindows(result).find(w => w.toplevel.id === id)
assert.deepEqual(Array.from(p.monitorSections, m => m.connector), ['DP-1', 'HDMI-A-1', 'USB-C-1', ''])
assert.equal(p.monitorSections[2].workspaces.length, 0, 'connected empty monitor has a header, not an invented workspace')
assert.deepEqual(Array.from(p.monitorSections[3].workspaces, w => w.identity), ['id:11', 'id:12'])
assert.equal(p.monitorSections[0].workspaces.find(w => w.identity === 'id:4').applications.length, 0)
assert.ok(p.monitorSections[1].workspaces.some(w => w.identity === 'name:project alpha'))
assert.equal(p.monitorSections[0].workspaces.find(w => w.identity === 'id:3').active, true)
assert.equal(p.monitorSections[1].workspaces.find(w => w.identity === 'id:7').active, true)
assert.equal(findWindow(p, 'sticky').workspaceIdentity, 'id:7')
assert.equal(findWindow(p, 'minimized').workspaceIdentity, 'id:3')
assert.equal(findWindow(p, 'minimized').minimized, true)
assert.equal(findWindow(p, 'b').urgent, true)
assert.equal(findWindow(p, 'hidden'), undefined)
assert.equal(p.unassignedWindows.find(w => w.toplevel.id === 'scratch').workspaceIdentity, '')
assert.deepEqual(Array.from(p.launchers, l => l.desktopId), ['closed-app'])
assert.equal(windows(p).length, f.toplevels.length - 1)
assert.equal(new Set(allWindows(p).map(w => w.key)).size, f.toplevels.length - 1)
const unknowns = p.unassignedWindows.filter(w => !w.toplevel.appId)
assert.notEqual(unknowns[0].applicationKey, unknowns[1].applicationKey, 'unidentified handles must never share a fake app group')
assert.notEqual(findWindow(p, 'pending-one').key, findWindow(p, 'pending-two').key)
const chrome3 = p.monitorSections[0].workspaces[0].applications.find(a => a.desktopId === 'chrome')
assert.deepEqual(Array.from(chrome3.windows, w => w.toplevel.id), ['a', 'b', 'minimized'])
assert.equal(chrome3.folded, false, 'classic saved grouping is inactive in sidebar')
assert.equal(chrome3.key, JSON.stringify(['app', 'id:3', 'chrome']))

// Real native badge traversal remains independent of visual order; one count owner per app.
const chromeOwner = p.rows.filter(r => r.desktopId === 'chrome' && r.primaryOwner)
assert.equal(chromeOwner.length, 1)
assert.equal(chromeOwner[0].toplevel.id, 'c', 'focused workspace traversal owns Chrome even when left monitor renders first')
const chrome7 = p.monitorSections[1].workspaces.find(w => w.identity === 'id:7').applications.find(a => a.desktopId === 'chrome')
let folded = project({ folds: { [chrome3.key]: true, [chrome7.key]: true } })
assert.equal(folded.rows.filter(r => r.desktopId === 'chrome' && r.primaryOwner)[0].key, chrome7.key)
assert.ok(!windows(folded).some(w => w.desktopId === 'chrome'))
const rail = project({ folds: { [chrome3.key]: true, [chrome7.key]: true }, collapsed: true })
assert.deepEqual(Array.from(windows(rail), w => w.key), Array.from(windows(p), w => w.key), 'rail exposes every member in canonical order')
assert.ok(!rail.rows.some(r => r.kind === 'application'), 'rail does not replace windows with app launchers')
assert.equal(project({ folds: { [chrome3.key]: true } }).monitorSections[0].workspaces[0].applications[0].folded, true)
assert.equal(new Set(p.badgeItems.map(i => i.presentationId)).size, p.badgeItems.length)

const oldKeys = Array.from(windows(p), w => w.key)
f.toplevels[0].title = '<b>Changed title</b>'
f.toplevels[0].activated = true
f.toplevels[2].activated = false
f.monitors[0].lastIpcObject.focused = false
f.monitors[1].lastIpcObject.focused = true
f.input.focusedWorkspace = 'id:3'
f.handles[4].address = '0x123'
f.input.toplevels = f.toplevels.slice().reverse()
registry = Model.reconcileHandles(registry, f.input.toplevels)
p = project()
assert.deepEqual(Array.from(windows(p), w => w.key), oldKeys, 'focus/title/address and source reorder do not shuffle members')
assert.equal(findWindow(p, 'a').title, '<b>Changed title</b>')
assert.equal(findWindow(p, 'pending-one').address, '0x123')
const oldAKey = findWindow(p, 'a').key
f.handles[0].lastIpcObject.workspace = { id: 7 }
p = project()
assert.equal(findWindow(p, 'a').key, oldAKey, 'a workspace move does not change live-handle identity')
const stableApp = p.monitorSections[1].workspaces.find(w => w.identity === 'id:7').applications.find(a => a.desktopId === 'chrome').key
f.workspaces.find(w => w.id === 7).monitorID = 9
assert.equal(project().monitorSections[0].workspaces.find(w => w.identity === 'id:7').applications.find(a => a.desktopId === 'chrome').key, stableApp)
registry = Model.reconcileHandles(registry, f.toplevels.filter(t => t.id !== 'a'))
const replacement = { id: 'replacement', appId: 'chrome', title: 'New lifetime' }
registry = Model.reconcileHandles(registry, [replacement, ...f.toplevels.filter(t => t.id !== 'a')])
assert.notEqual(Model.handleEntry(registry, replacement).key, oldAKey, 'address reuse never reuses a closed handle token')
assert.equal(registry.entries.length, f.toplevels.length)
registry = Model.reconcileHandles(registry, [])
assert.equal(registry.entries.length, 0, 'registry is bounded by live handles')

// Reuse an actual Hyprland address after closing the old handle: a new key is required.
f = sidebarFixture()
registry = Model.reconcileHandles(null, f.toplevels)
const prior = findWindow(project(), 'a')
const fresh = {id:'fresh',appId:'chrome',title:'Fresh lifetime'}
f.input.toplevels = [fresh, ...f.toplevels.slice(1)]
f.input.hyprToplevels = [{...f.handles[0],wayland:fresh},...f.handles.slice(1)]
registry = Model.reconcileHandles(Model.reconcileHandles(registry,f.toplevels.slice(1)),f.input.toplevels)
const reused = findWindow(project(),'fresh')
assert.equal(reused.address,prior.address)
assert.notEqual(reused.key,prior.key)

// Screen selection is connector-based and sticky except for explicit preference at idle.
f = sidebarFixture()
const pick = (preferred, current, busy = false, screens = f.screens, order = []) =>
  Model.selectScreen(screens, f.monitors, order, preferred, current, busy)
assert.equal(pick('', '').name, 'DP-1')
assert.equal(pick('', 'HDMI-A-1').name, 'HDMI-A-1')
assert.equal(pick('USB-C-1', 'DP-1').name, 'USB-C-1')
assert.equal(pick('USB-C-1', 'DP-1', true).name, 'DP-1')
assert.equal(pick('Missing', 'HDMI-A-1').name, 'HDMI-A-1')
assert.equal(pick('dp-1', '').name, 'DP-1', 'saved connector matching is case-sensitive')
assert.equal(pick('', '', false, f.screens, ['USB-C-1']).name, 'USB-C-1')
assert.equal(pick('DP-1', 'DP-1', true, f.screens.filter(s => s.name !== 'DP-1')).name, 'HDMI-A-1', 'removal overrides busy retention')
assert.equal(pick('DP-1', 'DP-1', false, []), null)
assert.equal(pick('', 'HDMI-A-1', false, [{ name: 'NEW', x: -5000, y: 0, width: 1000 }, ...f.screens]).name, 'HDMI-A-1')
for (const width of [0, -1, 30, 56, 200, 600, 720, 1000, 1920]) {
  for (const requested of [240, 320, 480]) for (const collapsed of [false, true]) {
    const g = Model.geometry(width, requested, collapsed)
    assert.ok(g.width >= 0 && g.width <= Math.max(0, width))
    assert.equal(g.mapped, width > 0)
    if (collapsed) assert.equal(g.width, Math.min(56, Math.max(0, width)))
  }
}
assert.equal(Model.geometry(720, 480, false).width, 288, 'Qt dimensions are logical, not divided by scale again')
assert.equal(Model.geometry(1920, 320, false).width, 320)
assert.equal(Model.geometry(0, 320, false).width, 0)
assert.deepEqual(plain(Model.recoverAnchor({ key: 'gone', offset: 7 }, ['a', 'gone', 'b'], [{ key: 'a' }, { key: 'b' }])), { key: 'b', offset: 7 })
assert.deepEqual(plain(Model.recoverAnchor({ key: 'b', offset: 7 }, ['a', 'b'], [])), { key: '', offset: 0 })
// Empty/whitespace application IDs must neither steal closed pins nor merge handles.
f = sidebarFixture()
f.toplevels.find(t => t.id === 'unknown-one').appId = '  '
registry = Model.reconcileHandles(null, f.toplevels)
p = project()
assert.deepEqual(Array.from(p.launchers,l => l.desktopId),['closed-app'])
assert.notEqual(findWindow(p,'unknown-one').applicationKey,findWindow(p,'unknown-two').applicationKey)
const inputBefore = JSON.stringify(f.input)
project()
assert.equal(JSON.stringify(f.input), inputBefore, 'projection never rewrites source snapshots or saved groups')
console.log('SB-02 sidebar native projection, stable identity, folding/rail, badges, screens and geometry: PASS')
