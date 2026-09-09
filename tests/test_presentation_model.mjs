import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../components/DockPresentationModel.js", import.meta.url), "utf8")
const model = vm.createContext({})
vm.runInContext(source.replace(/^\.pragma.*$/gm, ""), model)

function item(key, value = key) {
  return { identity: key, value }
}

function keys(state) {
  return JSON.stringify(state.entries.map(entry => `${entry.key}:${entry.present ? "in" : "out"}`))
}

let state = model.reconcile(null, [item("a"), item("b"), item("c")], "identity", false)
assert.equal(keys(state), JSON.stringify(["a:in", "b:in", "c:in"]))
assert.equal(JSON.stringify(state.entries.map(entry => entry.animateEntrance)), JSON.stringify([false, false, false]))
const initialTokens = state.entries.map(entry => entry.token)

let next = model.reconcile(state, [item("a", "focused"), item("b"), item("c")], "identity", true)
assert.equal(JSON.stringify(next.entries.map(entry => entry.token)), JSON.stringify(initialTokens))
assert.equal(next.entries[0].item.value, "focused")

next = model.reconcile(next, [item("a"), item("x"), item("c")], "identity", true)
assert.equal(keys(next), JSON.stringify(["a:in", "b:out", "x:in", "c:in"]))
assert.equal(next.entries[2].animateEntrance, true)
assert.equal(next.entries[1].present, false)
const bToken = next.entries[1].token
const bRevision = next.entries[1].exitRevision
const refreshed = model.reconcile(next, [item("a", "updated"), item("x"), item("c")], "identity", true)
assert.equal(keys(refreshed), keys(next))
assert.equal(refreshed.entries[1].exitRevision, bRevision)

let cancelled = model.reconcile(next, [item("a"), item("b"), item("x"), item("c")], "identity", true)
assert.equal(keys(cancelled), JSON.stringify(["a:in", "b:in", "x:in", "c:in"]))
assert.equal(cancelled.entries[1].token, bToken)
assert.equal(cancelled.entries[1].animateEntrance, true)

const stale = model.completeRemoval(cancelled, bToken, bRevision)
assert.equal(stale.entries.some(entry => entry.token === bToken), true)

const removedAgain = model.reconcile(cancelled, [item("a"), item("x"), item("c")], "identity", true)
const secondRevision = removedAgain.entries.find(entry => entry.token === bToken).exitRevision
assert.notEqual(secondRevision, bRevision)
const completed = model.completeRemoval(removedAgain, bToken, bRevision)
assert.equal(completed.entries.some(entry => entry.token === bToken), true)
const completedCurrent = model.completeRemoval(completed, bToken, secondRevision)
assert.equal(completedCurrent.entries.some(entry => entry.token === bToken), false)

const immediate = model.reconcile(state, [item("a"), item("c")], "identity", false)
assert.equal(keys(immediate), JSON.stringify(["a:in", "c:in"]))
const fresh = model.reconcile(null, [item("z")], "identity", true)
assert.equal(fresh.entries[0].animateEntrance, false)

console.log("presentation model: PASS")
