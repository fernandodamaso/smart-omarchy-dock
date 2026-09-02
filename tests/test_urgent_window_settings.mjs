import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.join(here, "..")
const read = relative => fs.readFileSync(path.join(root, relative), "utf8")

const config = JSON.parse(read("config/dock.json"))
assert.equal(config.urgentWindowAnimationEnabled, true)

const host = read("DockHost.qml")
assert.match(host, /urgentWindowAnimationEnabled:\s*true/)
assert.match(host,
  /typeof parsed\.urgentWindowAnimationEnabled === "boolean"[\s\S]*?parsed\.urgentWindowAnimationEnabled : true/)
assert.match(host, /patch\.urgentWindowAnimationEnabled = true/)

const dock = read("components/Dock.qml")
assert.match(dock,
  /readonly property bool urgentWindowAnimationEnabled:[\s\S]*?typeof effectiveSetting\("urgentWindowAnimationEnabled"\) === "boolean"[\s\S]*?effectiveSetting\("urgentWindowAnimationEnabled"\) : true/)
assert.match(dock, /urgentWindowAnimationEnabled: root\.urgentWindowAnimationEnabled/)
assert.match(dock, /primaryBadgeOwner: root\.primaryBadgeOwnerFor\(index\)/)
assert.match(dock, /dockShown: root\.dockShown/)

const settings = read("components/DockSettings.qml")
assert.match(settings, /title: "Application Badges"/)
assert.match(settings, /label: "Attention badges"/)
assert.match(settings, /label: "Urgent window animation"/)
assert.match(settings,
  /label: "Urgent window animation"[\s\S]*?enabled: root\.current\("attentionBadgesEnabled"\) !== false/)
assert.match(settings,
  /label: "Urgent window animation"[\s\S]*?checked: root\.current\("urgentWindowAnimationEnabled"\) !== false/)
assert.match(settings,
  /onToggled: root\.commit\("urgentWindowAnimationEnabled", !checked\)/)

const item = read("components/DockItem.qml")
assert.match(item, /badgesEnabled: attentionBadgesEnabled/)
assert.match(item, /animationEnabled: urgentWindowAnimationEnabled/)
assert.match(item, /previewInteractionActive/)

const docs = read("docs/attention-badges.md")
assert.match(docs, /## Urgent-window motion/)
assert.match(docs, /0 -> 5 -> 0 -> 3 -> 0/)
assert.match(docs, /three-second per-application cooldown/i)
assert.match(docs, /auto-hidden dock does not reveal/i)
assert.match(docs, /titles,[\s\S]*notification bodies,[\s\S]*output/i)
assert.match(docs, /urgentWindowAnimationEnabled/)

console.log("urgent window settings/docs tests: PASS")
