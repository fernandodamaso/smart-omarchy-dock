import assert from "node:assert/strict"
import { hostHarness, read } from "./host_harness.mjs"

const config = JSON.parse(read("config/dock.json"))
assert.equal(config.urgentWindowAnimationEnabled, true)

const host = read("DockHost.qml")
assert.match(host, /property var settings: dockControl\.defaults/)
assert.match(read("components/DockControl.qml"),
  /typeof requested\.urgentWindowAnimationEnabled === "boolean"[\s\S]*?requested\.urgentWindowAnimationEnabled : true/)
const h = hostHarness({ urgentWindowAnimationEnabled: false })
assert.equal(h.request("config.reset", { preferences: true }).ok, true)
assert.equal(h.host.settings.urgentWindowAnimationEnabled, true)
assert.equal(h.writes.length, 1)

const dock = read("components/Dock.qml")
assert.match(dock,
  /readonly property bool urgentWindowAnimationEnabled:[\s\S]*?typeof settings\.urgentWindowAnimationEnabled === "boolean"[\s\S]*?settings\.urgentWindowAnimationEnabled : true/)
assert.match(dock, /urgentWindowAnimationEnabled: root\.urgentWindowAnimationEnabled\s*\n/)
assert.match(dock, /primaryBadgeOwner: root\.primaryBadgeOwnerFor\(renderedIndex\)/)
assert.match(dock, /dockShown: root\.dockShown/)

const item = read("components/DockItem.qml")
assert.match(item, /badgesEnabled: attentionBadgesEnabled/)
assert.match(item, /animationEnabled: urgentWindowAnimationEnabled/)
assert.match(item, /previewInteractionActive/)

const docs = read("docs/attention-badges.md")
assert.match(docs, /## Urgent-window motion/)
assert.match(docs, /0 -> 5 -> 0 -> 3 -> 0/)
assert.match(docs, /no\s+more than once every\s+three seconds/i)
assert.match(docs, /SNI[\s\S]*critical local-notification attention[\s\S]*Hyprland/i)
assert.match(docs, /count[\s\S]*?without attention[\s\S]*?never triggers/i)
assert.match(docs, /timer or reveal requests can retry/i)
assert.match(docs, /auto-hidden dock\s+does not reveal/i)
assert.match(docs, /titles,[\s\S]*notification bodies,[\s\S]*output/i)
assert.match(docs, /urgentWindowAnimationEnabled/)

const readme = read("README.md")
assert.match(readme, /"urgentWindowAnimationEnabled": true/)
assert.match(readme, /\| `urgentWindowAnimationEnabled` \|/)
assert.match(readme, /0 -> 5 -> 0 -> 3 -> 0/)
assert.match(readme, /Auto-hidden docks do\s+not reveal for attention/i)

console.log("urgent window settings/docs tests: PASS")
