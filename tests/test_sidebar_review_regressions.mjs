import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'
import { loadModel } from './host_harness.mjs'
import { qmlMethods } from './sidebar_interaction_fixture.mjs'

// Execute production methods/bindings, not copies of the implementation.
// These are host-independent regressions; compositor qualification stays in SB-06.
const widgetSource = fs.readFileSync(new URL('../components/DockSidebarWidgetArea.qml', import.meta.url), 'utf8')
const popupSource = widgetSource.slice(widgetSource.indexOf('  PopupWindow {'))
const popupVisible = popupSource.match(/^    visible: (.+)$/m)[1]

for (const edge of ['left', 'right']) {
  test(`resize on ${edge} preserves another output's collapsed reservation`, () => {
    const c = qmlMethods('DockSidebarController.qml', {
      DockModel: loadModel('DockModel'),
      SidebarModel: loadModel('DockSidebarModel'), settings: { sidebarExpandedWidth: 320 },
      collapsed: true, collapsedByMonitor: { 'DP-1': false }, resizeActive: false,
      resizePreviewWidth: 320, edge,
    })
    const expanded = { name: 'DP-1', width: 1920 }
    const rail = { name: 'DP-2', width: 1280 }
    assert.equal(c.geometryFor(rail).width, 72)
    c.resizeActive = true
    for (const width of [360, 400, 480]) {
      c.resizePreviewWidth = width
      assert.equal(c.geometryFor(expanded).width, width)
      assert.equal(c.geometryFor(rail).width, 72)
    }
    c.resizeActive = false
    assert.equal(c.geometryFor(expanded).width, 320)
    assert.equal(c.geometryFor(rail).width, 72)
  })
}

function shelf(animationsEnabled) {
  const values = []
  const displayModel = {
    get count() { return values.length },
    get: i => values[i],
    append: value => values.push(value),
    setProperty: (i, key, value) => { values[i][key] = value },
    remove: (i, count = 1) => values.splice(i, count),
    move: (from, to, count) => { values.splice(to, 0, ...values.splice(from, count)) },
  }
  const c = qmlMethods('DockSidebarPinnedStrip.qml', {
    displayModel, pins: [], prevPins: [], exitStash: {}, animationsEnabled, stripReady: true,
  })
  return {
    values, c,
    set(keys) { c.pins = keys.map(key => ({ key })); c.syncDisplay() },
    keys() { return values.filter(row => !row.exiting).map(row => String(row.key)) },
  }
}

for (const animated of [false, true]) {
  test(`pin reorder and insertion retain existing rows (animations=${animated})`, () => {
    const s = shelf(animated)
    s.set(['A', 'B'])
    const a = s.values[0], b = s.values[1]
    s.set(['B', 'A'])
    assert.deepEqual(s.keys(), ['B', 'A'])
    assert.equal(s.values.find(row => row.key === 'A'), a)
    assert.equal(s.values.find(row => row.key === 'B'), b)
    s.set(['C', 'B', 'D', 'A'])
    assert.deepEqual(s.keys(), ['C', 'B', 'D', 'A'])
    s.set(['C', 'B', 'D', 'A'])
    assert.deepEqual(s.keys(), ['C', 'B', 'D', 'A'])
    assert.equal(s.values.find(row => row.key === 'A'), a)
  })
}

test('pin reorder preserves pending exits and cancels a reinserted exit', () => {
  const s = shelf(true)
  s.set(['A', 'B', 'C'])
  const a = s.values[0]
  s.set(['C', 'B'])
  assert.deepEqual(s.keys(), ['C', 'B'])
  assert.equal(a.exiting, true)
  s.set(['B', 'A', 'C'])
  assert.deepEqual(s.keys(), ['B', 'A', 'C'])
  assert.equal(s.values.find(row => row.key === 'A'), a)
  assert.equal(a.exiting, false)
  s.c.finishExit('A')
  assert.deepEqual(s.keys(), ['B', 'A', 'C'])
  s.set(['C', 'B'])
  s.c.finishExit('A')
  assert.deepEqual(s.keys(), ['C', 'B'])
  assert.equal(s.values.some(row => row.key === 'A'), false)
})

function popups() {
  const panelA = { contentItem: { parent: null }, visible: true }
  const panelB = { contentItem: { parent: null }, visible: true }
  const viewportA = { parent:panelA.contentItem, height:800, anchorY:0,
    mapFromItem(){ return {y:this.anchorY} }, listView:{} }
  const viewportB = { parent:panelB.contentItem, height:800, anchorY:0,
    mapFromItem(){ return {y:this.anchorY} }, listView:{} }
  const anchorA = { visible: true, height:44, parent: viewportA }
  const anchorB = { visible: true, height:44, parent: viewportB }
  const controller = {
    widgetPopupId: '', widgetPopupAnchor: null, interactionBusy: false,
    resizeActive: false, rowDragActive: false,
    cancelResize() {},
    closeWidgetPopup() { this.widgetPopupId = ''; this.widgetPopupAnchor = null; this.interactionBusy = false },
    openWidgetPopup(id, anchor) {
      this.widgetPopupId = id; this.widgetPopupAnchor = anchor; this.interactionBusy = true
      return true
    },
  }
  function area(panel, viewport) {
    const result = qmlMethods('DockSidebarWidgetArea.qml', {
      controller, panel, viewport,
      popup: { anchor: { updateAnchor() {} } },
      managerPopup: { anchor: { updateAnchor() {} } },
      managerOpen:false, managerAnchor:null, anchorRevision:0, managerAnchorRevision:0,
    })
    result.testViewport = viewport
    return result
  }
  const a = area(panelA,viewportA), b = area(panelB,viewportB)
  function shell(widgets) {
    return qmlMethods('DockSidebar.qml', {
      controller, widgetArea: widgets, host: null, sidebarContext: { dismiss() {} },
      picker: { visible: false }, sidebarViewport: { cancelInputs() {} },
      positionDragSurface: { cancelGesture() {} },
      viewportDragSurface: { cancelGesture() {} },
    })
  }
  const visible = area => vm.runInContext(popupVisible, area)
  return { a, b, anchorA, anchorB, controller, visible, shell, viewportA, viewportB }
}

for (const id of ['fixture.one']) {
  test(`only the initiating panel displays popup ${id}`, () => {
    const p = popups()
    p.controller.openWidgetPopup(id, p.anchorA)
    assert.equal(p.visible(p.a), true)
    assert.equal(p.visible(p.b), false)
    p.controller.openWidgetPopup(id, p.anchorB)
    assert.equal(p.visible(p.a), false)
    assert.equal(p.visible(p.b), true)
  })
}

test('non-owning panel teardown preserves the widget session and busy state', () => {
  const p = popups()
  p.controller.openWidgetPopup('fixture.one', p.anchorA)
  p.shell(p.b).closeSurfaces()
  assert.equal(p.controller.widgetPopupId, 'fixture.one')
  assert.equal(p.controller.widgetPopupAnchor, p.anchorA)
  assert.equal(p.controller.interactionBusy, true)
  p.shell(p.a).closeSurfaces()
  assert.equal(p.controller.widgetPopupId, '')
  assert.equal(p.controller.interactionBusy, false)
})

test('scrolling the shared viewport closes a popup whose card leaves view', () => {
  const p = popups()
  p.controller.openWidgetPopup('fixture.one', p.anchorA)
  p.viewportA.anchorY = 900
  p.a.updatePopupAnchor()
  assert.equal(p.controller.widgetPopupId, '')
})

test('same-widget click on another panel transfers instead of closing', () => {
  const p = popups()
  p.a.openWidget('fixture.one', p.anchorA)
  p.b.openWidget('fixture.one', p.anchorB)
  assert.equal(p.controller.widgetPopupId, 'fixture.one')
  assert.equal(p.controller.widgetPopupAnchor, p.anchorB)
  p.b.openWidget('fixture.one', p.anchorB)
  assert.equal(p.controller.widgetPopupId, '')
})
