import assert from "node:assert/strict"
import fs from "node:fs"
import { hostHarness, loadModel, plain, read } from "./host_harness.mjs"

const ConfigModel = loadModel("DockConfigModel")
const DockIconModel = loadModel("DockIconModel")
const defaults = JSON.parse(read("config/dock.json"))

assert.equal(typeof ConfigModel.windowIconIntent, "function",
  "Task 2 requires a latest-state window icon intent")
assert.equal(typeof ConfigModel.windowIconsChanged, "function",
  "Task 2 requires window-rule changes to participate in artwork reload revisions")

const a = { appId: "org.ghostty", titlePattern: "*solar*", source: "file:///tmp/a.svg" }
const b = { appId: "org.ghostty", titlePattern: "*lunar*", source: "file:///tmp/b.svg" }
const aKey = DockIconModel.windowRuleKey(a.appId, a.titlePattern)
const bKey = DockIconModel.windowRuleKey(b.appId, b.titlePattern)

function settings(rules) {
  return { ...plain(defaults), windowIconOverrides: plain(rules) }
}
function expectConflict(result, label) {
  assert.equal(result.ok, false, label)
  assert.equal(result.errorCode, "E_CONFLICT", label + " exposes a conflict, not validation")
  assert.deepEqual(Array.from(result.changedKeys || []), [], label + " never applies a stale edit")
}

let result = ConfigModel.windowIconIntent(settings([a, b]), "set", {
  mode: "cli", appId: " ORG.GHOSTTY ", titlePattern: " *SOLAR* ", source: "/tmp/c.svg"
})
assert.equal(result.ok, true)
assert.deepEqual(plain(result.settings.windowIconOverrides), [
  { appId: "org.ghostty", titlePattern: "*SOLAR*", source: "file:///tmp/c.svg" },
  b
], "CLI set edits the latest matching rule in place without rebuilding unrelated rules")
assert.deepEqual(Array.from(result.changedKeys), ["windowIconOverrides"])

result = ConfigModel.windowIconIntent(result.settings, "reset", {
  mode: "cli", appId: "org.ghostty", titlePattern: "*solar*"
})
assert.equal(result.ok, true)
assert.deepEqual(plain(result.settings.windowIconOverrides), [b],
  "CLI reset removes only the exact stable rule key")

const capturedA = { key: aKey, expected: a }
const unrelatedLatest = settings([b, a])
result = ConfigModel.windowIconIntent(unrelatedLatest, "set", {
  mode: "dialog", originalKey: capturedA.key, expected: capturedA.expected,
  appId: "org.ghostty", titlePattern: "*solar*", source: "/tmp/c.svg"
})
assert.equal(result.ok, true)
assert.deepEqual(plain(result.settings.windowIconOverrides), [
  b,
  { appId: "org.ghostty", titlePattern: "*solar*", source: "file:///tmp/c.svg" }
], "unrelated reorder/edit does not false-conflict and latest order is preserved")

expectConflict(ConfigModel.windowIconIntent(settings([
  { ...a, source: "file:///tmp/concurrent.svg" }, b
]), "set", {
  mode: "dialog", originalKey: aKey, expected: a,
  appId: a.appId, titlePattern: a.titlePattern, source: "/tmp/c.svg"
}), "same-rule source change")

expectConflict(ConfigModel.windowIconIntent(settings([b]), "set", {
  mode: "dialog", originalKey: aKey, expected: a,
  appId: a.appId, titlePattern: a.titlePattern, source: "/tmp/c.svg"
}), "same-rule deletion")

expectConflict(ConfigModel.windowIconIntent(settings([a, b]), "set", {
  mode: "dialog", originalKey: aKey, expected: a,
  appId: b.appId, titlePattern: b.titlePattern, source: "/tmp/c.svg"
}), "editing onto another stable key")

expectConflict(ConfigModel.windowIconIntent(settings([a]), "set", {
  mode: "dialog", originalKey: "", expected: null,
  appId: "ORG.GHOSTTY", titlePattern: "*SOLAR*", source: "/tmp/c.svg"
}), "same-key concurrent create")

result = ConfigModel.windowIconIntent(settings([b]), "set", {
  mode: "dialog", originalKey: "", expected: null,
  appId: a.appId, titlePattern: a.titlePattern, source: "/tmp/a.svg"
})
assert.equal(result.ok, true)
assert.deepEqual(plain(result.settings.windowIconOverrides), [b, a],
  "new dialog rules append after the latest collection")

result = ConfigModel.windowIconIntent(settings([a, b]), "reset", {
  mode: "dialog", originalKey: aKey, expected: a,
  appId: a.appId, titlePattern: a.titlePattern
})
assert.equal(result.ok, true)
assert.deepEqual(plain(result.settings.windowIconOverrides), [b],
  "dialog reset removes only the originally captured exact rule")

result = ConfigModel.windowIconIntent(settings([a]), "set", {
  mode: "cli", appId: a.appId, titlePattern: a.titlePattern, source: a.source
})
assert.equal(result.ok, true)
assert.deepEqual(Array.from(result.changedKeys), [],
  "same-path set is a config no-op so reload can be revision-only")

assert.equal(ConfigModel.windowIconIntent(
  { ...settings([]), windowIconOverrides: [{ appId: "bad", source: "/tmp/a.svg" }] },
  "set", { mode: "cli", appId: a.appId, titlePattern: a.titlePattern, source: a.source }
).ok, false, "malformed existing rule collections block mutation atomically")

const harness = hostHarness({ windowIconOverrides: [] })
let reply = harness.request("icons.set", {
  id: "org.ghostty", titlePattern: "*solar*", source: "/tmp/a.svg"
})
assert.equal(reply.ok, true)
assert.equal(reply.data.applied, true)
assert.equal(reply.data.persisted, true)
assert.equal(reply.data.renderVerified, false)
assert.equal(harness.writes.length, 1)
const firstRevision = reply.data.iconReloadRevision

reply = harness.request("icons.set", {
  id: "org.ghostty", titlePattern: "*solar*", source: "/tmp/a.svg"
})
assert.equal(reply.ok, true)
assert.equal(harness.writes.length, 1,
  "same-path apply never creates a redundant settings write")
assert.equal(reply.data.iconReloadRevision, firstRevision + 1,
  "same-path apply still refreshes artwork bytes")

reply = harness.request("icons.set", {
  id: "org.ghostty", titlePattern: "*solar*", source: "/tmp/b.svg"
})
assert.equal(reply.ok, true)
assert.equal(harness.writes.length, 2)
assert.equal(reply.data.iconReloadRevision, firstRevision + 2,
  "source A -> B is both a persisted rule change and an artwork refresh")

reply = harness.request("icons.list")
assert.deepEqual(reply.data.windowOverrides, [
  { appId: "org.ghostty", titlePattern: "*solar*", source: "file:///tmp/b.svg" }
])
assert.deepEqual(reply.data.effectiveWindowOverrides, reply.data.windowOverrides)

reply = harness.request("icons.reset", {
  id: "org.ghostty", titlePattern: "*solar*"
})
assert.equal(reply.ok, true)
assert.deepEqual(harness.host.settings.windowIconOverrides, [])

const dialogPath = new URL("../components/DockWindowIconDialog.qml", import.meta.url)
assert.ok(fs.existsSync(dialogPath), "selected-window editing uses DockWindowIconDialog.qml")
const dialog = fs.readFileSync(dialogPath, "utf8")
assert.match(dialog, /import QtQuick\.Dialogs/)
assert.match(dialog, /FileDialog\s*\{/)
assert.match(dialog, /readOnly:\s*true/)
assert.match(dialog, /enabled:\s*false/)
assert.match(dialog, /titlePattern/)
assert.match(dialog, /originalKey/)
assert.match(dialog, /expectedRule/)
assert.match(dialog, /literal.*\*/i)
assert.match(dialog, /trim/i)
assert.doesNotMatch(dialog, /titlePattern\s*=\s*"\*"/,
  "missing/invalid titles must never seed a broad wildcard")

const context = read("components/DockContextMenu.qml")
assert.match(context, /"Change Icon"/)
assert.match(context, /"Reset Icon"/)
assert.match(context, /windowIconDialog/)
assert.match(context, /reply\.ok\s*\|\|\s*reply\.data\.applied/,
  "dialog dismissal follows applied truth, including persistence-pending replies")

const agents = read("AGENTS.md")
assert.match(agents, /selected live window/i,
  "AGENTS narrows the CLI-only icon editing rule for the selected-window dialog")
assert.match(read(".github/workflows/ci.yml"), /qml6-module-qtquick-dialogs/,
  "CI installs QtQuick.Dialogs for the native FileDialog")

console.log("window icon mutation and selected-window dialog contracts: PASS")
