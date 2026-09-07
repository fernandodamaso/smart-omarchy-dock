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
  motionAttentionEligible,
  BADGE_NONE,
  BADGE_ATTENTION,
  BADGE_URGENT
} = context

assert.equal(typeof motionAttentionEligible, "function")

// An ordinary desktop notification keeps its attention dot, but must not
// trigger FDM-814's repeating motion.
assert.equal(motionAttentionEligible(false, false, BADGE_ATTENTION), false)
assert.equal(motionAttentionEligible(false, false, BADGE_NONE), false)

// These are the three motion-eligible source classes in the active contract.
assert.equal(motionAttentionEligible(true, false, BADGE_NONE), true)
assert.equal(motionAttentionEligible(false, true, BADGE_NONE), true)
assert.equal(motionAttentionEligible(false, false, BADGE_URGENT), true)

// Source priority/combinations must remain eligible without needing a final
// rendered badge token (which can be replaced visually by a launcher count).
assert.equal(motionAttentionEligible(true, false, BADGE_ATTENTION), true)
assert.equal(motionAttentionEligible(false, true, BADGE_ATTENTION), true)
assert.equal(motionAttentionEligible(true, true, BADGE_URGENT), true)

console.log("attention motion source eligibility tests: PASS")
