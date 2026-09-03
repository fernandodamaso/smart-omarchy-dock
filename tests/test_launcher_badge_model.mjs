import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const modelPath = path.join(here, "..", "components", "DockBadgeModel.js")
const source = fs.readFileSync(modelPath, "utf8")
const context = vm.createContext({ console, decodeURIComponent })
vm.runInContext(source, context, { filename: modelPath })

const {
  normalizeLauncherIdentity,
  normalizeLauncherBadgeMode,
  normalizeLauncherCount,
  launcherCountState,
  applicationBadgePresentation,
  applicationBadgeToken,
  herdrBadgeState,
  herdrCountStateFor
} = context

assert.equal(
  normalizeLauncherIdentity(" application://Com.DiscordApp.Discord.desktop "),
  "com.discordapp.discord")
assert.equal(normalizeLauncherIdentity("org.telegram.desktop.desktop"),
  "org.telegram.desktop")
assert.equal(normalizeLauncherIdentity("application://My%20App.desktop"), "my app")
assert.equal(normalizeLauncherIdentity("https://example.test/app.desktop"), "")
assert.equal(normalizeLauncherIdentity("application://../bad.desktop"), "")
assert.equal(normalizeLauncherIdentity("application://foo\\bar.desktop"), "")
assert.equal(normalizeLauncherIdentity("application://%ZZ.desktop"), "")

assert.equal(normalizeLauncherBadgeMode("automatic"), "automatic")
assert.equal(normalizeLauncherBadgeMode("dots-only"), "dots-only")
assert.equal(normalizeLauncherBadgeMode("bad-value"), "automatic")
assert.equal(normalizeLauncherCount(4), 4)
assert.equal(normalizeLauncherCount(4.9), 4)
assert.equal(normalizeLauncherCount(-3), 0)
assert.equal(normalizeLauncherCount(false), null)
assert.equal(normalizeLauncherCount("oops"), null)

const records = {
  "com.discordapp.discord": { count: 7, visible: true },
  "org.telegram.desktop": { count: 120, visible: true },
  "com.hidden.app": { count: 5, visible: false },
  "com.zero.app": { count: 0, visible: true },
  "com.malformed.app": { count: "oops", visible: true }
}

const discord = launcherCountState(records, "com.discordapp.Discord", true)
assert.equal(JSON.stringify(discord), JSON.stringify({
  authoritative: true,
  count: 7,
  visible: true
}))
assert.equal(launcherCountState(records, "com.discordapp.Discord", false).authoritative,
  false)
assert.equal(launcherCountState(records, "com.unknown.App", true).authoritative, false)
assert.equal(launcherCountState(records, "com.malformed.App", true).authoritative, false)

let presentation = applicationBadgePresentation(true, "automatic", discord, "attention")
assert.equal(JSON.stringify(presentation), JSON.stringify({
  kind: "count",
  count: 7,
  countVisible: true,
  severity: "attention",
  text: "7"
}))
assert.equal(applicationBadgeToken(true, "automatic", discord, "attention"),
  "count:7:attention")

presentation = applicationBadgePresentation(
  true, "automatic",
  launcherCountState(records, "org.telegram.desktop", true), "urgent")
assert.equal(presentation.text, "99+")
assert.equal(presentation.severity, "urgent")

presentation = applicationBadgePresentation(
  true, "automatic",
  launcherCountState(records, "com.hidden.app", true), "attention")
assert.equal(presentation.kind, "dot")
assert.equal(presentation.severity, "attention")

presentation = applicationBadgePresentation(
  true, "automatic",
  launcherCountState(records, "com.zero.app", true), "urgent")
assert.equal(presentation.kind, "dot")
assert.equal(presentation.severity, "urgent")

presentation = applicationBadgePresentation(true, "dots-only", discord, "attention")
assert.equal(presentation.kind, "dot")
assert.equal(applicationBadgeToken(true, "dots-only", discord, "attention"), "attention")

presentation = applicationBadgePresentation(false, "automatic", discord, "urgent")
assert.equal(presentation.kind, "none")

const herdrWorking = herdrBadgeState([
  { agent_status: "working" },
  { agent_status: "working" },
  { agent_status: "idle" },
  { agent_status: "done" }
], true)
assert.equal(JSON.stringify(herdrWorking), JSON.stringify({
  authoritative: true,
  count: 2,
  visible: true,
  severity: "attention",
  total: 4,
  working: 2,
  blocked: 0,
  done: 1,
  idle: 1,
  unknown: 0
}))
assert.equal(
  herdrCountStateFor(
    "com.mitchellh.ghostty", "com.mitchellh.ghostty", herdrWorking).count,
  2)
assert.equal(
  herdrCountStateFor("org.gnome.Nautilus", "com.mitchellh.ghostty", herdrWorking)
    .authoritative,
  false)

const herdrBlocked = herdrBadgeState([
  { agent_status: "blocked" },
  { agent_status: "working" },
  { agent_status: "mystery" }
], true)
assert.equal(herdrBlocked.count, 1)
assert.equal(herdrBlocked.severity, "urgent")
assert.equal(herdrBlocked.unknown, 1)

const herdrIdle = herdrBadgeState([{ agent_status: "idle" }], true)
assert.equal(herdrIdle.authoritative, false)
assert.equal(herdrIdle.severity, "none")
assert.equal(herdrBadgeState([], false).authoritative, false)

console.log("launcher badge model tests: PASS")
