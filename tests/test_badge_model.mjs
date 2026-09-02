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
  normalizeIdentity,
  identityCandidates,
  strictIdentityMatches,
  entryForStrictSource,
  reduceSeverity,
  notificationSeverity,
  upsertNotification,
  pruneExpired,
  localSeverity,
  clearMatchingNotifications,
  badgeSeverity,
  shouldClearFocused,
  isPrimaryVisibleItem,
  LOCAL_ATTENTION_TTL_MS,
  FOCUS_DWELL_MS
} = context

assert.equal(normalizeIdentity("  Com.Google.Chrome.desktop  "), "com.google.chrome")
assert.equal(normalizeIdentity("Chat GPT"), "chat gpt")
assert.equal(normalizeIdentity("chat-gpt"), "chat-gpt")

const firefox = {
  id: "org.mozilla.firefox.desktop",
  startupClass: "firefox",
  name: "Firefox Browser"
}
assert.deepEqual(
  Array.from(identityCandidates("org.mozilla.firefox", firefox, {})),
  ["org.mozilla.firefox", "firefox", "firefox browser"]
)
assert.equal(strictIdentityMatches("org.mozilla.firefox", firefox, ["FIREFOX"], {}), true)
assert.equal(strictIdentityMatches("org.mozilla.firefox", firefox, ["Firefox Browser"], {}), true)
assert.equal(strictIdentityMatches("org.mozilla.firefox", firefox, ["mozilla"], {}), false)
assert.equal(strictIdentityMatches("org.mozilla.firefox", firefox, ["org.mozilla.firefox-nightly"], {}), false)
assert.equal(strictIdentityMatches(
  "org.mozilla.firefox", firefox, ["Mozilla Firefox"], {}), false)
assert.equal(strictIdentityMatches(
  "org.mozilla.firefox", firefox, ["Mozilla Firefox"],
  { "org.mozilla.firefox": ["Mozilla Firefox"] }), true)

const entries = [
  firefox,
  { id: "com.discordapp.Discord", startupClass: "discord", name: "Discord" }
]
assert.equal(entryForStrictSource(["discord"], entries, {}).id, "com.discordapp.Discord")
assert.equal(entryForStrictSource(["cord"], entries, {}), null)

assert.equal(reduceSeverity(["none", "attention"]), "attention")
assert.equal(reduceSeverity(["attention", "urgent", "none"]), "urgent")
assert.equal(notificationSeverity(2, 2), "urgent")
assert.equal(notificationSeverity(1, 2), "attention")
assert.equal(badgeSeverity(true, false, "urgent"), "urgent")
assert.equal(badgeSeverity(true, false, "none"), "attention")

const slack = { id: "com.slack.Slack", startupClass: "Slack", name: "Slack" }
const discord = entries[1]
let records = upsertNotification({}, {
  originalId: 7,
  app: "Slack",
  appIcon: "",
  urgency: 1,
  timestamp: 1000
}, 2, 1000)
assert.equal(localSeverity(records, slack.id, slack, {}), "attention")

records = upsertNotification(records, {
  originalId: 7,
  app: "Discord",
  appIcon: "discord",
  urgency: 2,
  timestamp: 1000
}, 2, 1200)
assert.equal(Object.keys(records).length, 1)
assert.equal(localSeverity(records, slack.id, slack, {}), "none")
assert.equal(localSeverity(records, discord.id, discord, {}), "urgent")

const beforeTtl = pruneExpired(records, 1000 + LOCAL_ATTENTION_TTL_MS - 1)
assert.equal(Object.keys(beforeTtl).length, 1)
const atTtl = pruneExpired(records, 1000 + LOCAL_ATTENTION_TTL_MS)
assert.equal(Object.keys(atTtl).length, 0)

let local = upsertNotification({}, {
  originalId: 11,
  app: "Discord",
  appIcon: "discord",
  urgency: 1,
  timestamp: 5000
}, 2, 5000)
// Removing/dismissing a popup is intentionally not a state transition here.
assert.equal(localSeverity(local, discord.id, discord, {}), "attention")
assert.equal(shouldClearFocused(5000, 5000 + FOCUS_DWELL_MS - 1), false)
assert.equal(shouldClearFocused(5000, 5000 + FOCUS_DWELL_MS), true)
local = clearMatchingNotifications(local, discord.id, discord, {})
assert.equal(localSeverity(local, discord.id, discord, {}), "none")
// Focus clearing is local-only; a live SNI NeedsAttention source still wins.
assert.equal(badgeSeverity(true, false, localSeverity(local, discord.id, discord, {})), "attention")

const ungrouped = [
  { desktopId: "com.discordapp.Discord" },
  { desktopId: "com.discordapp.Discord.desktop" },
  { desktopId: "org.mozilla.firefox" }
]
assert.equal(isPrimaryVisibleItem(ungrouped, 0), true)
assert.equal(isPrimaryVisibleItem(ungrouped, 1), false)
assert.equal(isPrimaryVisibleItem(ungrouped, 2), true)
assert.equal(isPrimaryVisibleItem([{ desktopId: "org.mozilla.firefox" }], 0), true)

console.log("attention badge model tests: PASS")
