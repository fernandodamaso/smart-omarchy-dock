import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const source = fs.readFileSync(new URL('../components/DockMenuModel.js', import.meta.url), 'utf8')
const scope = vm.createContext({})
vm.runInContext(source.replace(/^\.(pragma|import).*$/gm, ''), scope)

const targetA = { toplevel: { id: 'A' }, address: '0xaaa' }
const targetB = { toplevel: { id: 'B' }, address: '0xbbb' }
const records = [
  scope.headerRecord('header', 'Chrome', '2 open windows'),
  scope.actionRecord('window:a', 'Window A', 'app-window', true, 'open-window', targetA),
  scope.actionRecord('disabled', 'Disabled', '', false, 'noop', null),
  scope.separatorRecord('divider'),
  scope.actionRecord('window:b', 'Window B', 'app-window', true, 'open-window', targetB)
]

assert.equal(scope.firstEnabledIndex(records), 1)
assert.equal(scope.nextEnabledIndex(records, 1, 1), 4)
assert.equal(scope.nextEnabledIndex(records, 4, -1), 1)

const cursor = scope.cursorStep(records, 1, 1, targetA)
assert.equal(cursor.index, 4)
assert.equal(cursor.targetContext, targetA,
  'cursor movement must not retarget the action context')

const live = [targetA.toplevel, targetB.toplevel]
const addresses = toplevel => toplevel === targetA.toplevel ? '0xaaa' : '0xbbb'
assert.equal(scope.targetIsCurrent(targetA, live, addresses), true)
assert.equal(scope.targetIsCurrent(targetA, [targetB.toplevel], addresses), false)

const replacement = { id: 'replacement' }
assert.equal(
  scope.targetIsCurrent(targetA, [replacement, targetB.toplevel], () => '0xaaa'),
  false,
  'replacement at the same list position/address must not inherit the captured target')
assert.equal(
  scope.targetIsCurrent(
    { toplevel: targetA.toplevel, address: '0xold' }, live, addresses),
  false,
  'address identity changes invalidate the target')

assert.equal(scope.initialPage(false, 0, false), 'app')
assert.equal(scope.initialPage(false, 1, false), 'window')
assert.equal(scope.initialPage(false, 3, false), 'app')
assert.equal(scope.initialPage(false, 3, true), 'window')
assert.equal(scope.initialPage(true, 0, false), 'controls')

assert.equal(scope.contentYForRow(0, 120, 20, 32, 400), 0)
assert.equal(scope.contentYForRow(0, 120, 180, 32, 400), 92)
assert.equal(scope.contentYForRow(160, 120, 40, 32, 400), 40)
assert.equal(scope.contentYForRow(260, 120, 390, 32, 400), 280)

console.log('context menu explicit-target and keyboard model tests: PASS')
