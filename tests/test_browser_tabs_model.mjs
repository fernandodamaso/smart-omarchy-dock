import assert from 'node:assert/strict'
import { loadModel, plain } from './host_harness.mjs'

const Activity = loadModel('DockBrowserActivityModel')

assert.equal(Activity.normalizeTabRow(null), null)
assert.equal(Activity.normalizeTabRow({ targetId: 'not-hex!', title: 'X' }), null)
assert.deepEqual(plain(Activity.normalizeTabRow({
  targetId: 'a'.repeat(32), title: ' Inbox ', active: true, windowAddress: '0xA',
  url: 'https://secret.example/',
  faviconPath: '/tmp/evil.png'
})), {
  targetId: 'a'.repeat(32),
  title: 'Inbox',
  active: true,
  windowAddress: '0xa',
  faviconPath: ''
})

const cachedIcon = '/home/admin/.cache/smartdock/tab-favicons/abc.png'
assert.equal(Activity.normalizeTabRow({
  targetId: 'a'.repeat(32), title: 'Ok', faviconPath: cachedIcon
}).faviconPath, cachedIcon)
const longTitle = 'T'.repeat(200)
const capped = Activity.normalizeTabRow({ targetId: 'b'.repeat(32), title: longTitle })
assert.equal(capped.title.length, Activity.MAX_TAB_TITLE)
assert.ok(capped.title.endsWith('…'))

const rows = Activity.presentationTabs([
  { targetId: 'c'.repeat(32), title: 'Linear', active: false },
  { targetId: 'a'.repeat(32), title: 'Inbox', active: true },
  { targetId: 'c'.repeat(32), title: 'Linear dup', active: false },
  { targetId: 'not-hex', title: 'Skip' }
])
assert.equal(rows[0].title, 'Linear', 'preserves CDP/input order; does not promote active')
assert.equal(rows[1].title, 'Inbox')
assert.equal(rows[1].active, true)
assert.equal(rows.length, 2)
assert.ok(rows.every(row => !Object.prototype.hasOwnProperty.call(row, 'url')))

const byAddress = Activity.tabsForAddresses({
  '0x1': [{ targetId: 'a'.repeat(32), title: 'One', active: true }],
  '0x2': [{ targetId: 'b'.repeat(32), title: 'Two' }]
}, ['0x2', '0x1'])
assert.deepEqual(plain(byAddress.map(r => r.title)), ['Two', 'One'])

assert.equal(JSON.stringify(Activity.activationCommand('/bin/provider', 'AABB', 9222)),
  JSON.stringify(['/bin/provider', '--activate-target', 'AABB', '--port', '9222']))

// Exact tab activity uses RAW records (targetId + address), not window dedup.
const actId = 'd'.repeat(32)
const actId2 = 'e'.repeat(32)
const activities = {
  '0xAB': [
    { targetId: actId, serviceId: 'gmail', label: 'Gmail', count: 3, profileKey: 'P1' },
    { targetId: actId2, serviceId: 'gmail', label: 'Gmail', count: 8, profileKey: 'P1' }
  ]
}
assert.equal(Activity.activityForTarget(activities, actId, '0xab').count, 3)
assert.equal(Activity.rowsForAddresses(activities, ['0xAB']).find(r => r.serviceId === 'gmail').count, 8)
assert.equal(Activity.presentation(Activity.rawRowsForAddresses(activities, ['0xAB']), ['gmail']).total, 0,
  'service mute zeroes window total while raw tab rows remain findable')
assert.equal(Activity.activityForTarget(activities, actId, '0xAB').count, 3)

console.log('browser tabs model: PASS')
