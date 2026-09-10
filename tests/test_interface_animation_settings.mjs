import assert from "node:assert/strict"
import { hostHarness, loadModel, read } from "./host_harness.mjs"

const model = loadModel("DockModel")
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", undefined), true)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", true), true)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", false), false)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", "false"), true)
assert.equal(model.settingsDefaults().interfaceAnimationsEnabled, true)

const h = hostHarness({ interfaceAnimationsEnabled: false })
assert.equal(h.request("config.reset", { key: "interfaceAnimationsEnabled" }).ok, true)
assert.equal(h.host.settings.interfaceAnimationsEnabled, true)
assert.equal(h.writes.length, 1)
const config = JSON.parse(read("config/dock.json"))
assert.equal(config.interfaceAnimationsEnabled, true)
assert.match(read("DockHost.qml"), /property var settings: dockControl\.defaults/)
assert.match(read("components/Dock.qml"), /readonly property bool interfaceAnimationsEnabled/)
assert.match(read("README.md"), /`interfaceAnimationsEnabled`/)
assert.match(read("components/DockBadgeTracker.qml"), /DockModel\.normalizeWindowAddress\(handle\.address \|\| ipc\.address\)/)
assert.doesNotMatch(read("components/DockBadgeTracker.qml"), /DockWindowModel\.normalizedAddress/)

console.log("interface animation settings: PASS")
