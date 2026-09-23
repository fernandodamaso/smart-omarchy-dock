import assert from 'node:assert/strict'
import { loadModel, plain } from './host_harness.mjs'

const model = loadModel('DockSidebarInteractionModel')
const layout = width => plain(model.pinnedStripLayout(width - 28, 7, 32, 32, 7))

assert.deepEqual(layout(240), { slots:4, visible:3, hidden:4 })
assert.deepEqual(layout(256), { slots:5, visible:4, hidden:3 })
assert.deepEqual(layout(320), { slots:6, visible:5, hidden:2 })
assert.deepEqual(layout(220), { slots:4, visible:3, hidden:4 },
  'illustrative 220 px strip layout still fits')
assert.deepEqual(plain(model.pinnedStripLayout(228, 3, 32, 32, 7)),
  { slots:5, visible:3, hidden:0 }, 'no overflow when every pin fits')
assert.deepEqual(plain(model.pinnedStripLayout(228, 0, 32, 32, 7)),
  { slots:5, visible:0, hidden:0 })
assert.deepEqual(plain(model.pinnedStripLayout(71, 7, 32, 32, 7)),
  { slots:1, visible:0, hidden:7 }, 'last icon slot is reserved for overflow')

console.log('sidebar pinned strip layout: PASS')
