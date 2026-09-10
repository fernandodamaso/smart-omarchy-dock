import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../components/DockModel.js", import.meta.url), "utf8")
const model = vm.createContext({})
vm.runInContext(source.replace(/^\.pragma.*$/gm, ""), model)

assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", undefined), true)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", true), true)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", false), false)
assert.equal(model.normalizeSetting("interfaceAnimationsEnabled", "false"), true)
assert.equal(model.settingsDefaults().interfaceAnimationsEnabled, true)
assert.equal(model.resetSettingsPatch().interfaceAnimationsEnabled, true)

const read = relative => fs.readFileSync(new URL(`../${relative}`, import.meta.url), "utf8")
const config = JSON.parse(read("config/dock.json"))
assert.equal(config.interfaceAnimationsEnabled, true)
assert.match(read("DockHost.qml"), /property var settings: dockControl\.defaults/)
assert.match(read("components/Dock.qml"), /readonly property bool interfaceAnimationsEnabled/)
assert.match(read("components/DockSettings.qml"), /label: "Interface animations"/)
assert.match(read("README.md"), /`interfaceAnimationsEnabled`/)
assert.match(read("components/DockBadgeTracker.qml"), /DockModel\.normalizeWindowAddress\(handle\.address \|\| ipc\.address\)/)
assert.doesNotMatch(read("components/DockBadgeTracker.qml"), /DockWindowModel\.normalizedAddress/)

console.log("interface animation settings: PASS")
