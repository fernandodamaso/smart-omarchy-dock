import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

function load(path, imports = {}) {
  const source = fs.readFileSync(new URL("../" + path, import.meta.url), "utf8")
  const context = vm.createContext(imports)
  vm.runInContext(source.replace(/^\.(pragma|import).*$/gm, ""), context)
  return context
}

const icons = load("components/DockIconModel.js")
const DockModel = load("components/DockModel.js")
const WorkspaceGroups = load("components/DockWorkspaceGroupModel.js", { DockModel })

const rules = [
  { appId: " Org.GNOME.Console ", titlePattern: " *Solar* ", source: "/tmp/a.png" },
  { appId: "org.gnome.console", titlePattern: "build-release", source: "/tmp/b.svg" }
]

const normalized = icons.normalizeWindowRules(rules)
assert.equal(normalized.length, 2)
assert.deepEqual(JSON.parse(JSON.stringify(normalized[0])), {
  appId: "org.gnome.console",
  titlePattern: "*Solar*",
  source: "file:///tmp/a.png"
})

const firstKey = icons.windowRuleKey("org.gnome.console", "*SOLAR*")
assert.equal(firstKey, icons.windowRuleKey(" Org.GNOME.Console ", "*solar*"),
  "rule identity uses the same case-insensitive normalization as matching")
assert.notEqual(
  icons.windowRuleKey("ab", "c"),
  icons.windowRuleKey("a", "bc"),
  "tuple encoding must be collision-safe"
)

assert.equal(icons.matchWindowRule(normalized, "org.gnome.console", "my SOLAR shell").key, firstKey)
assert.equal(icons.matchWindowRule(normalized, "ORG.GNOME.CONSOLE", "build-release").source,
  "file:///tmp/b.svg")
assert.equal(icons.matchWindowRule(normalized, "org.gnome.console", "prefix build-release"), null,
  "without a leading wildcard the pattern is anchored to the full title")
assert.equal(icons.matchWindowRule(normalized, "org.gnome.console", "build-release suffix"), null,
  "without a trailing wildcard the pattern is anchored to the full title")
assert.equal(icons.titlePatternMatches("build-*", "build-release suffix"), true,
  "an explicit trailing wildcard consumes the remaining title")
assert.equal(icons.titlePatternMatches("*a*b", "a b c b"), true,
  "anchored suffix matching uses the final valid occurrence, not the first one")

assert.match(icons.windowRulesError([
  rules[0],
  { appId: "org.gnome.console", titlePattern: "*solar*", source: "/tmp/other.png" }
]), /duplicate/i)
assert.match(icons.windowRulesError([
  { appId: "org.gnome.console", titlePattern: "", source: "/tmp/a.png" }
]), /pattern/i)
assert.match(icons.windowRulesError([
  { appId: "org.gnome.console", titlePattern: "x".repeat(201), source: "/tmp/a.png" }
]), /200/)
assert.match(icons.windowRulesError([
  { appId: "org.gnome.console", titlePattern: "bad\npattern", source: "/tmp/a.png" }
]), /control/i)
assert.match(icons.windowRulesError([
  { appId: "org.gnome.console", titlePattern: "*", source: "/tmp/a.jpg" }
]), /PNG|SVG/i)

assert.deepEqual(
  JSON.parse(JSON.stringify(icons.candidates(
    "file:///tmp/window.png",
    "file:///tmp/profile.png",
    "file:///tmp/app.png",
    "image://icon/desktop",
    "image://icon/application-x-executable"
  ))),
  [
    "file:///tmp/window.png",
    "file:///tmp/profile.png",
    "file:///tmp/app.png",
    "image://icon/desktop",
    "image://icon/application-x-executable"
  ],
  "window rule artwork must precede profile/app/desktop/generic candidates"
)

const reordered = [normalized[1], normalized[0]]
assert.equal(icons.matchWindowRule(reordered, "org.gnome.console", "my solar shell").key, firstKey,
  "reordering an unrelated rule must not rename an unchanged rule")
assert.equal(icons.matchWindowRule([normalized[0]], "org.gnome.console", "my solar shell").key, firstKey,
  "removing an unrelated rule must not renumber rule identity")

const sharedSourceRules = icons.normalizeWindowRules([
  { appId: "com.google.Chrome", titlePattern: "Alpha*", source: "/tmp/shared.svg" },
  { appId: "com.google.Chrome", titlePattern: "Beta*", source: "/tmp/shared.svg" }
])
const alphaOne = { appId: "com.google.Chrome", title: "Alpha one" }
const alphaTwo = { appId: "com.google.Chrome", title: "Alpha two" }
const beta = { appId: "com.google.Chrome", title: "Beta one" }
const plain = { appId: "com.google.Chrome", title: "Plain" }
const windows = [alphaOne, alphaTwo, beta, plain]
const matches = windows.map(window =>
  icons.matchWindowRule(sharedSourceRules, window.appId, window.title))
const baseItems = DockModel.buildVisibleItems(
  ["com.google.Chrome"], windows, [], [], false, false, [], matches)
const pinned = baseItems.find(item => item.pinned)
assert.deepEqual(Array.from(pinned.toplevels), [plain],
  "a matching rule window never attaches to the pinned launcher")
assert.equal(baseItems.filter(item => item.windowOverrideSource === "file:///tmp/shared.svg").length, 3)

const records = windows.map((toplevel, index) => ({
  toplevel,
  workspaceKnown: true,
  workspace: "id:3",
  address: "0x" + String(index + 1)
}))
const localized = WorkspaceGroups.buildFlatPresentation(baseItems, records, [
  { desktopId: "com.google.Chrome", workspace: "id:3" }
], false)
const ruleGroups = localized.filter(item => item.windowRuleKey)
assert.equal(ruleGroups.length, 2,
  "different matching rules stay in separate local groups even with the same source")
assert.deepEqual(Array.from(ruleGroups.map(item => item.toplevels.length)).sort(), [1, 2])
assert.equal(ruleGroups[0].windowOverrideSource, "file:///tmp/shared.svg")
assert.equal(ruleGroups[1].windowOverrideSource, "file:///tmp/shared.svg")
assert.notEqual(ruleGroups[0].presentationId, ruleGroups[1].presentationId,
  "group identity includes the stable rule identity")
const unmatched = localized.find(item => !item.windowRuleKey)
assert.deepEqual(Array.from(unmatched.toplevels), [plain],
  "matched and unmatched windows stay partitioned")

const alphaBefore = icons.matchWindowRule(sharedSourceRules, alphaOne.appId, alphaOne.title)
alphaOne.title = "Beta renamed"
const betaAfter = icons.matchWindowRule(sharedSourceRules, alphaOne.appId, alphaOne.title)
assert.notEqual(alphaBefore.key, betaAfter.key,
  "live title changes can switch rule identity without changing the window object")
assert.equal(alphaBefore.source, betaAfter.source,
  "rule identity remains distinct even when two rules intentionally share artwork")
assert.equal(DockModel.visibleItemsEqual([
  { desktopId: "com.google.Chrome", pinned: false, presentationId: "same",
    identityToplevel: alphaOne, toplevels: [alphaOne],
    windowRuleKey: alphaBefore.key, windowOverrideSource: alphaBefore.source }
], [
  { desktopId: "com.google.Chrome", pinned: false, presentationId: "same",
    identityToplevel: alphaOne, toplevels: [alphaOne],
    windowRuleKey: betaAfter.key, windowOverrideSource: betaAfter.source }
]), false, "rule changes invalidate the visible-item snapshot even when sources are equal")
assert.equal(DockModel.visibleItemsEqual([
  { desktopId: "com.google.Chrome", pinned: false, presentationId: "same",
    identityToplevel: alphaOne, toplevels: [alphaOne],
    windowRuleKey: alphaBefore.key, windowOverrideSource: "file:///tmp/a.svg" }
], [
  { desktopId: "com.google.Chrome", pinned: false, presentationId: "same",
    identityToplevel: alphaOne, toplevels: [alphaOne],
    windowRuleKey: alphaBefore.key, windowOverrideSource: "file:///tmp/b.svg" }
]), false, "source A -> B invalidates the snapshot without changing rule/window identity")

console.log("window icon override contracts: PASS")
