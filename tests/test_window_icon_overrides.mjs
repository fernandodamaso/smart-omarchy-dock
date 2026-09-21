import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

function load(path) {
  const source = fs.readFileSync(new URL("../" + path, import.meta.url), "utf8")
  const context = vm.createContext({})
  vm.runInContext(source.replace(/^\.pragma.*$/gm, ""), context)
  return context
}

const icons = load("components/DockIconModel.js")

const rules = [
  { appId: " Org.GNOME.Console ", titlePattern: " *Solar* ", source: "/tmp/a.png" },
  { appId: "org.gnome.console", titlePattern: "build-*", source: "/tmp/b.svg" }
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

console.log("window icon override contracts: PASS")
