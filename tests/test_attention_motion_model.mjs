import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const modelPath = path.join(here, "..", "components", "DockBadgeModel.js")
const source = fs.readFileSync(modelPath, "utf8")
const context = vm.createContext({ console })
vm.runInContext(source, context, { filename: modelPath })

const {
  reduceWindowUrgencyState,
  primeUrgentMotionState,
  reduceUrgentMotion,
  urgentMotionVector,
  URGENT_WINDOW_COOLDOWN_MS
} = context

function decision(previous, overrides = {}) {
  return reduceUrgentMotion(previous, {
    revision: 1,
    windowUrgent: true,
    primaryOwner: true,
    badgesEnabled: true,
    animationEnabled: true,
    dockShown: true,
    interactionActive: false,
    now: 10000,
    ...overrides
  })
}

let urgency = reduceWindowUrgencyState(null, [], true, true)
assert.equal(urgency.windowUrgentRevision, 0)
assert.equal(urgency.windowUrgent, false)
assert.equal(urgency.primaryOwner, true)

urgency = reduceWindowUrgencyState(urgency, ["0xaaa"], true, false)
assert.equal(urgency.windowUrgentRevision, 1)
assert.equal(urgency.windowUrgent, true)
assert.deepEqual(Array.from(urgency.urgentAddresses), ["0xaaa"])

const duplicate = reduceWindowUrgencyState(urgency, ["0xaaa"], true, false)
assert.equal(duplicate.windowUrgentRevision, 1)

const grouped = reduceWindowUrgencyState(duplicate, ["0xaaa", "0xbbb"], true, false)
assert.equal(grouped.windowUrgentRevision, 2)
assert.equal(grouped.windowUrgent, true)

const oneClosed = reduceWindowUrgencyState(grouped, ["0xbbb"], true, false)
assert.equal(oneClosed.windowUrgentRevision, 2)
assert.equal(oneClosed.windowUrgent, true)

const cleared = reduceWindowUrgencyState(oneClosed, [], true, false)
assert.equal(cleared.windowUrgentRevision, 2)
assert.equal(cleared.windowUrgent, false)

const reurgent = reduceWindowUrgencyState(cleared, ["0xbbb"], true, false)
assert.equal(reurgent.windowUrgentRevision, 3)
assert.equal(reurgent.windowUrgent, true)

let motion = decision(null, { revision: 9 })
assert.equal(motion.play, false)
assert.equal(motion.state.seenRevision, 9)
assert.equal(motion.state.pendingRevision, 0)

motion = decision(motion.state, { revision: 10, now: 20000 })
assert.equal(motion.play, true)
assert.equal(motion.state.seenRevision, 10)
assert.equal(motion.state.lastPlayedAt, 20000)

const groupedDuplicate = decision(motion.state, { revision: 10, now: 20500 })
assert.equal(groupedDuplicate.play, false)

const cooldown = decision(motion.state, {
  revision: 11,
  now: 20000 + URGENT_WINDOW_COOLDOWN_MS - 1
})
assert.equal(cooldown.play, false)
assert.equal(cooldown.state.seenRevision, 11)
assert.equal(cooldown.state.pendingRevision, 0)

const afterCooldown = decision(cooldown.state, {
  revision: 12,
  now: 20000 + URGENT_WINDOW_COOLDOWN_MS
})
assert.equal(afterCooldown.play, true)

let hidden = decision(null, { revision: 20, dockShown: false })
hidden = decision(hidden.state, { revision: 21, dockShown: false, now: 30000 })
assert.equal(hidden.play, false)
assert.equal(hidden.state.pendingRevision, 21)
const reveal = decision(hidden.state, { revision: 21, dockShown: true, now: 30010 })
assert.equal(reveal.play, true)
assert.equal(reveal.state.pendingRevision, 0)
const revealAgain = decision(reveal.state, { revision: 21, dockShown: true, now: 34000 })
assert.equal(revealAgain.play, false)

let stalePending = decision(null, { revision: 30, dockShown: false })
stalePending = decision(stalePending.state, { revision: 31, dockShown: false, now: 40000 })
const clearedBeforeReveal = decision(stalePending.state, {
  revision: 31,
  windowUrgent: false,
  dockShown: true,
  now: 40100
})
assert.equal(clearedBeforeReveal.play, false)
assert.equal(clearedBeforeReveal.state.pendingRevision, 0)

let suppressed = decision(null, { revision: 40 })
suppressed = decision(suppressed.state, {
  revision: 41,
  interactionActive: true,
  now: 50000
})
assert.equal(suppressed.play, false)
assert.equal(suppressed.state.pendingRevision, 0)
const afterInteraction = decision(suppressed.state, {
  revision: 41,
  interactionActive: false,
  now: 54000
})
assert.equal(afterInteraction.play, false)

let nonPrimary = decision(null, { revision: 50, primaryOwner: false })
nonPrimary = decision(nonPrimary.state, {
  revision: 51,
  primaryOwner: false,
  now: 60000
})
assert.equal(nonPrimary.play, false)
const primary = decision(nonPrimary.state, {
  revision: 51,
  primaryOwner: true,
  now: 60000
})
assert.equal(primary.play, true)

let disabled = decision(null, { revision: 60 })
disabled = decision(disabled.state, {
  revision: 61,
  animationEnabled: false,
  now: 70000
})
assert.equal(disabled.play, false)
const enabledSameRevision = decision(disabled.state, {
  revision: 61,
  animationEnabled: true,
  now: 74000
})
assert.equal(enabledSameRevision.play, false)

let badgesDisabled = decision(null, { revision: 70 })
badgesDisabled = decision(badgesDisabled.state, {
  revision: 71,
  badgesEnabled: false,
  now: 80000
})
assert.equal(badgesDisabled.play, false)

const primed = primeUrgentMotionState({
  initialized: true,
  seenRevision: 2,
  pendingRevision: 2,
  lastPlayedAt: 1234
}, 8)
assert.equal(primed.seenRevision, 8)
assert.equal(primed.pendingRevision, 0)
assert.equal(primed.lastPlayedAt, 1234)

assert.deepEqual(urgentMotionVector("bottom", 5), { x: 0, y: -5 })
assert.deepEqual(urgentMotionVector("top", 5), { x: 0, y: 5 })
assert.deepEqual(urgentMotionVector("left", 5), { x: 5, y: 0 })
assert.deepEqual(urgentMotionVector("right", 5), { x: -5, y: 0 })
assert.deepEqual(urgentMotionVector("unknown", 3), { x: 0, y: -3 })

console.log("attention motion model tests: PASS")
