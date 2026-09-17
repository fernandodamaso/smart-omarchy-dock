import assert from 'node:assert/strict'
import {loadModel} from './host_harness.mjs'

const model = loadModel('DockSidebarModel')

function g(screen, requested = 320, collapsed = false) {
  return model.screenGeometry(screen, requested, collapsed)
}

// Qt screen geometry is already logical. Scale/device-pixel metadata must never
// divide it a second time.
for (const scale of [1, 1.25, 1.5, 2]) {
  const geometry = g({name:'DP-1', x:-1920, width:1920, height:1080,
    scale, devicePixelRatio:scale, availableWidth:1200}, 320, false)
  assert.equal(geometry.width, 320, `logical width at ${scale}x`)
  assert.equal(geometry.maximum, 480)
  assert.equal(geometry.railWidth, 56)
}

assert.deepEqual(
  Object.fromEntries(['width','expandedWidth','minimum','maximum','railWidth'].map(k => [k, g({width:720,height:1280},320,false)[k]])),
  {width:288, expandedWidth:288, minimum:240, maximum:288, railWidth:56},
  'portrait screen uses the exact 40% cap')
assert.equal(g({width:100,height:400},320,false).width,56,'narrow output is bounded')
assert.equal(g({width:40,height:400},320,false).width,40,'extremely narrow output never exceeds screen')
assert.equal(g({width:0,height:400},320,false).mapped,false,'zero-width screen does not map')
assert.equal(g({width:0,height:400},320,false).width,0)
assert.equal(g({width:1920,height:1080},320,true).width,56,'rail width')

// availableWidth/workarea can already include our own exclusive zone. Width
// budgeting must use the unreserved full logical screen width instead.
const noFeedback = g({width:1000, availableWidth:600, height:800},400,false)
assert.equal(noFeedback.width,400)
assert.equal(noFeedback.maximum,400)

assert.equal(model.resizeWidth(320, 100, 140, 'left', 1920),360)
assert.equal(model.resizeWidth(320, 100, 140, 'right', 1920),280)
assert.equal(model.resizeWidth(320, -1600, -1640, 'right', 1920),360,
  'right-edge calculation uses stable screen-global delta on negative-origin output')
assert.equal(model.resizeWidth(320, 100, 1000, 'left', 1920),480,'drag clamps to configured maximum')
assert.equal(model.resizeWidth(320, 100, -1000, 'left', 1920),240,'drag clamps to configured minimum')
assert.equal(model.resizeWidth(288, 0, 100, 'left', 720),288,'runtime cap is respected')
assert.equal(model.resizeWidth(56, 0, 100, 'left', 100),56,'narrow runtime bounds are respected')

const screens = [{name:'HDMI-A-1',width:1200,x:0},{name:'DP-1',width:1920,x:1200}]
assert.equal(model.selectScreen(screens,[],[],'DP-1','HDMI-A-1',true).name,'HDMI-A-1',
  'preferred-monitor return is deferred while interacting')
assert.equal(model.selectScreen(screens,[],[],'DP-1','HDMI-A-1',false).name,'DP-1')
assert.equal(model.selectScreen([screens[1]],[],[],'DP-1','HDMI-A-1',true).name,'DP-1',
  'current-screen removal falls back immediately even during interaction')

// Topology fallback/reconnect changes only effective geometry; caller-owned
// requested width remains the same preference.
const requested = 420
assert.equal(g({width:800},requested,false).width,320)
assert.equal(g({width:1920},requested,false).width,420)
assert.equal(requested,420)

console.log('SB-03 sidebar logical geometry and stable resize delta: PASS')
