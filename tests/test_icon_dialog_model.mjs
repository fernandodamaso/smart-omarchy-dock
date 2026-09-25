import assert from "node:assert/strict"
import vm from "node:vm"
import { loadModel, plain, read } from "./host_harness.mjs"

const DockIconModel = loadModel("DockIconModel")
const ConfigModel = loadModel("DockConfigModel")
const defaults = JSON.parse(read("config/dock.json"))

// "Title contains" round-trips through the saved *TEXT* pattern.
assert.deepEqual(plain(DockIconModel.containsToPattern("  solar ")),
  { ok: true, pattern: "*solar*", error: "" })
for (const bad of ["", "   ", "a*b", "tab\there", "x".repeat(199), null])
  assert.equal(DockIconModel.containsToPattern(bad).ok, false, "rejects " + JSON.stringify(bad))
assert.equal(DockIconModel.containsToPattern("x".repeat(198)).pattern.length, 200)

assert.equal(DockIconModel.patternToContains("*solar*"), "solar")
assert.equal(DockIconModel.patternToContains(" *Solar API* "), "Solar API")
for (const exact of ["solar", "*solar", "solar*", "*a*b*", "**", "*", "* x*", ""])
  assert.equal(DockIconModel.patternToContains(exact), null,
    JSON.stringify(exact) + " stays an exact pattern")
for (const text of ["solar", "Solar API", "~/Projects"])
  assert.equal(DockIconModel.patternToContains(DockIconModel.containsToPattern(text).pattern), text)

// Current override follows the renderer precedence: window -> profile -> app.
const settings = {
  iconOverrides: {
    "google-chrome": "/icons/chrome.svg",
    "google-chrome@profile:Profile 1": "/icons/work.svg",
    "com.mitchellh.ghostty": "/icons/ghostty.png"
  },
  windowIconOverrides: [
    { appId: "com.mitchellh.ghostty", titlePattern: "*solar*", source: "/icons/sun.svg" },
    { appId: "google-chrome", titlePattern: "*mail*", source: "/icons/mail.svg" }
  ]
}

assert.deepEqual(plain(DockIconModel.currentIconTarget({
  settings, desktopId: "com.mitchellh.ghostty", appId: "com.mitchellh.ghostty",
  title: "solar — nvim"
})), {
  kind: "window",
  key: DockIconModel.windowRuleKey("com.mitchellh.ghostty", "*solar*"),
  appId: "com.mitchellh.ghostty", titlePattern: "*solar*", source: "file:///icons/sun.svg"
})
assert.deepEqual(plain(DockIconModel.currentIconTarget({
  settings, desktopId: "com.mitchellh.ghostty", appId: "com.mitchellh.ghostty", title: "htop"
})), { kind: "app", key: "com.mitchellh.ghostty", source: "file:///icons/ghostty.png" })
assert.deepEqual(plain(DockIconModel.currentIconTarget({
  settings, desktopId: "google-chrome.desktop", profileKey: "Profile 1",
  appId: "google-chrome", title: "News"
})), { kind: "profile", key: "google-chrome@profile:Profile 1", source: "file:///icons/work.svg" })
assert.equal(DockIconModel.currentIconTarget({
  settings, desktopId: "google-chrome", profileKey: "Profile 1",
  appId: "google-chrome", title: "Inbox (3) - mail"
}).kind, "window", "a title rule beats the profile icon")
assert.equal(DockIconModel.currentIconTarget({
  settings, desktopId: "google-chrome", profileKey: "Profile 9", appId: "", title: ""
}).kind, "app", "a pinned app without a window falls back to the app icon")
assert.deepEqual(plain(DockIconModel.currentIconTarget({ settings, desktopId: "code" })),
  { kind: "none", key: "", source: "" })
assert.equal(DockIconModel.currentIconTarget({}).kind, "none")

// Recent images: distinct, window rules then app icons, latest additions first.
assert.deepEqual(plain(DockIconModel.recentIconSources(settings)), [
  "file:///icons/mail.svg", "file:///icons/sun.svg", "file:///icons/ghostty.png",
  "file:///icons/work.svg", "file:///icons/chrome.svg"
])
assert.deepEqual(plain(DockIconModel.recentIconSources(settings, 2)),
  ["file:///icons/mail.svg", "file:///icons/sun.svg"])
assert.deepEqual(plain(DockIconModel.recentIconSources({
  iconOverrides: { a: "/x.svg", b: "/x.svg", c: "https://remote/x.svg" },
  windowIconOverrides: "invalid"
})), ["file:///x.svg"], "duplicates and invalid sources are skipped")
assert.deepEqual(plain(DockIconModel.recentIconSources(null)), [])

// Preview flags which open windows a choice would change.
const windows = [
  { title: "solar — nvim" },
  { title: "~/Projects/smart-omarchy-dock", profileKey: "Profile 1" },
  { title: "SOLAR-api · logs", profileKey: "Profile 1" },
  { title: "htop" }
]
assert.deepEqual(plain(DockIconModel.previewMatches(windows, { kind: "app" })),
  { flags: [true, true, true, true], count: 4 })
assert.deepEqual(plain(DockIconModel.previewMatches(windows,
  { kind: "window", titlePattern: "*solar*" })),
  { flags: [true, false, true, false], count: 2 })
assert.deepEqual(plain(DockIconModel.previewMatches(windows,
  { kind: "profile", profileKey: "Profile 1" })),
  { flags: [false, true, true, false], count: 2 })
assert.equal(DockIconModel.previewMatches(windows, { kind: "window", titlePattern: "" }).count, 0)
assert.equal(DockIconModel.previewMatches(null, { kind: "app" }).count, 0)

// One save covers a scope change: remove what applied, set the new choice.
const base = {
  ...plain(defaults),
  iconOverrides: { "com.mitchellh.ghostty": "file:///icons/ghostty.png", legacy: "/keep.svg" },
  windowIconOverrides: [
    { appId: "com.mitchellh.ghostty", titlePattern: "*solar*", source: "file:///icons/sun.svg" },
    { appId: "com.mitchellh.ghostty", titlePattern: "*lunar*", source: "file:///icons/moon.svg" }
  ]
}
const solarRule = { kind: "window", ...DockIconModel.currentIconTarget({
  settings: base, desktopId: "com.mitchellh.ghostty",
  appId: "com.mitchellh.ghostty", title: "solar — nvim"
}) }
const appIcon = { kind: "app", key: "com.mitchellh.ghostty", source: "file:///icons/ghostty.png" }

let change = ConfigModel.iconChangeIntent(base, {
  remove: solarRule,
  set: { kind: "app", key: "com.mitchellh.ghostty", source: "/icons/new.svg" }
})
assert.equal(change.ok, true)
assert.deepEqual(Array.from(change.changedKeys).sort(), ["iconOverrides", "windowIconOverrides"])
assert.deepEqual(plain(change.settings.windowIconOverrides), [base.windowIconOverrides[1]],
  "title rule to whole app removes the rule")
assert.deepEqual(plain(change.settings.iconOverrides),
  { legacy: "/keep.svg", "com.mitchellh.ghostty": "file:///icons/new.svg" },
  "unrelated legacy entries are untouched")

change = ConfigModel.iconChangeIntent(base, {
  remove: solarRule,
  set: { kind: "window", appId: "com.mitchellh.ghostty", titlePattern: "*sol*",
    source: "/icons/sun.svg" }
})
assert.equal(change.ok, true)
assert.deepEqual(plain(change.settings.windowIconOverrides)[0],
  { appId: "com.mitchellh.ghostty", titlePattern: "*sol*", source: "file:///icons/sun.svg" },
  "editing a title rule keeps its place in the ordered list")
assert.deepEqual(Array.from(change.changedKeys), ["windowIconOverrides"])

change = ConfigModel.iconChangeIntent(base, {
  set: { kind: "profile", key: "google-chrome@profile:Profile 1", source: "/icons/work.svg" }
})
assert.equal(change.ok, true)
assert.equal(change.settings.iconOverrides["google-chrome@profile:Profile 1"], "file:///icons/work.svg")

change = ConfigModel.iconChangeIntent(base, { remove: appIcon })
assert.equal(change.ok, true, "Reset to default removes exactly the applied override")
assert.deepEqual(plain(change.settings.iconOverrides), { legacy: "/keep.svg" })

const stale = ConfigModel.iconChangeIntent(base, {
  remove: { ...appIcon, source: "file:///icons/other.png" },
  set: { kind: "app", key: "com.mitchellh.ghostty", source: "/icons/new.svg" }
})
assert.equal(stale.ok, false)
assert.equal(stale.errorCode, "E_CONFLICT", "a concurrent app icon edit is refused")
assert.equal(ConfigModel.iconChangeIntent(base, {
  remove: { ...solarRule, source: "file:///icons/other.svg" }
}).errorCode, "E_CONFLICT", "a concurrent title rule edit is refused")

const failedSet = ConfigModel.iconChangeIntent(base, {
  remove: appIcon, set: { kind: "app", key: "com.mitchellh.ghostty", source: "https://x/y.svg" }
})
assert.equal(failedSet.ok, false, "an invalid new image rejects the whole save")
assert.deepEqual(Array.from(failedSet.changedKeys), [])

assert.deepEqual(Array.from(ConfigModel.iconChangeIntent(base, {
  remove: appIcon, set: { kind: "app", key: "com.mitchellh.ghostty", source: "/icons/ghostty.png" }
}).changedKeys), [], "saving the same image and scope writes nothing")
assert.deepEqual(Array.from(ConfigModel.iconChangeIntent(base, {}).changedKeys), [])
assert.equal(ConfigModel.iconChangeIntent(base, { set: { kind: "bogus" } }).ok, false)

// Dialog helpers: labels, notice, save arguments and the preview sentence.
assert.equal(DockIconModel.sourceFileName("file:///icons/My%20Sun.svg"), "My Sun.svg")
assert.equal(DockIconModel.sourceFileName(""), "")

const sunRule = DockIconModel.currentIconTarget({
  settings, desktopId: "com.mitchellh.ghostty", appId: "com.mitchellh.ghostty", title: "solar"
})
assert.equal(DockIconModel.currentIconNotice(sunRule, "Ghostty"),
  "This window uses sun.svg because its title contains \u201csolar\u201d. Editing this updates that setting.")
assert.equal(DockIconModel.currentIconNotice({ kind: "window", titlePattern: "solar*",
  source: "file:///x/a.png" }, "Ghostty"),
  "This window uses a.png because its title matches \u201csolar*\u201d. Editing this updates that setting.")
assert.equal(DockIconModel.currentIconNotice({ kind: "app", source: "file:///icons/ghostty.png" },
  "Ghostty"), "Ghostty uses a custom icon (ghostty.png) for all its windows.")
assert.equal(DockIconModel.currentIconNotice({ kind: "profile", source: "file:///w/work.svg" },
  "Chrome", "Work"), "The Work profile uses a custom icon (work.svg).")
assert.equal(DockIconModel.currentIconNotice({ kind: "none" }, "Ghostty"), "")

const ids = { desktopId: "com.mitchellh.ghostty", appId: "com.mitchellh.ghostty" }
const ghosttyApp = { kind: "app", key: "com.mitchellh.ghostty", source: "file:///icons/ghostty.png" }
const none = { kind: "none", key: "", source: "" }
let save = DockIconModel.iconChangeArguments(none, { ...ids, kind: "app", source: "/i/new.svg" })
assert.deepEqual(plain(save), { ok: true, error: "", unchanged: false, args: {
  remove: null, set: { kind: "app", key: "com.mitchellh.ghostty", source: "/i/new.svg" } } })
save = DockIconModel.iconChangeArguments(sunRule, { ...ids, kind: "app", source: "/i/new.svg" })
assert.deepEqual(plain(save.args.remove), plain(sunRule), "a wider scope replaces the title rule")
save = DockIconModel.iconChangeArguments(ghosttyApp, { ...ids, kind: "window",
  titleMode: "contains", titleText: " solar ", source: "/i/sun.svg" })
assert.equal(save.args.remove, null, "a narrower title rule keeps the whole-app icon")
assert.deepEqual(plain(save.args.set), { kind: "window", appId: "com.mitchellh.ghostty",
  titlePattern: "*solar*", source: "/i/sun.svg" })
save = DockIconModel.iconChangeArguments(sunRule, { ...ids, kind: "window",
  titleMode: "contains", titleText: "SOLAR", source: "file:///icons/sun.svg" })
assert.equal(save.unchanged, true, "same scope, pattern and image is unchanged")
save = DockIconModel.iconChangeArguments(sunRule, { ...ids, kind: "window",
  titleMode: "exact", titleText: " solar* ", source: "file:///icons/sun.svg" })
assert.equal(save.unchanged, false)
assert.equal(save.args.set.titlePattern, "solar*", "exact patterns are saved verbatim")
assert.deepEqual(plain(save.args.remove), plain(sunRule))
assert.equal(DockIconModel.iconChangeArguments(none, { ...ids, kind: "window",
  titleMode: "contains", titleText: "", source: "/i/sun.svg" }).error, "Type part of the window title.")
assert.equal(DockIconModel.iconChangeArguments(none, { kind: "window", titleText: "x",
  source: "/i/sun.svg" }).ok, false, "title rules need the raw Wayland app ID")
assert.equal(DockIconModel.iconChangeArguments(none, { ...ids, kind: "app",
  source: "https://x/y.svg" }).ok, false)
save = DockIconModel.iconChangeArguments(none, { desktopId: "google-chrome", profileKey: "Profile 1",
  kind: "profile", source: "/w.svg" })
assert.deepEqual(plain(save.args.set), { kind: "profile", key: "google-chrome@profile:Profile 1",
  source: "/w.svg" })
assert.equal(DockIconModel.iconChangeArguments(none, { desktopId: "google-chrome",
  kind: "profile", source: "/w.svg" }).ok, false)
save = DockIconModel.iconChangeArguments(ghosttyApp, { ...ids, kind: "app", source: "" })
assert.deepEqual(plain(save.args), { remove: ghosttyApp, set: null }, "Default removes the override")
assert.equal(DockIconModel.iconChangeArguments(none, { ...ids, kind: "app", source: "" }).unchanged, true)
// The produced arguments save through the host intent in one step.
save = DockIconModel.iconChangeArguments(solarRule, { ...ids, kind: "app", source: "/icons/new.svg" })
assert.equal(ConfigModel.iconChangeIntent(base, save.args).ok, true)

assert.equal(DockIconModel.previewSummary({ kind: "window", hasPattern: true, count: 2, total: 4,
  appName: "Ghostty" }), "Preview: 2 of 4 open Ghostty windows match, and new windows with a matching title will too.")
assert.equal(DockIconModel.previewSummary({ kind: "app", count: 4, total: 4, appName: "Ghostty" }),
  "Preview: all 4 open Ghostty windows change, and new ones will too.")
assert.equal(DockIconModel.previewSummary({ kind: "app", count: 1, total: 1, appName: "Ghostty" }),
  "Preview: the open Ghostty window changes, and new ones will too.")
assert.equal(DockIconModel.previewSummary({ kind: "window", hasPattern: false, total: 3 }),
  "Type part of a window title to choose which windows change.")
assert.equal(DockIconModel.previewSummary({ kind: "profile", count: 1, total: 2, appName: "Chrome",
  profileName: "Work" }), "Preview: 1 of 2 open Chrome windows use the Work profile, and new ones will too.")
assert.equal(DockIconModel.previewSummary({ kind: "app", total: 0 }), "")
assert.equal(DockIconModel.previewSummary({ kind: "app", resetting: true, count: 3, total: 3,
  appName: "Ghostty" }), "Preview: 3 of 3 open Ghostty windows go back to the app's own icon.")
assert.equal(DockIconModel.previewSummary({ kind: "none", resetting: true, count: 0, total: 2,
  appName: "Ghostty" }), "Preview: no open Ghostty window uses a custom icon.")

// omarchy-file-select output: first non-empty line, path or file URI.
assert.equal(DockIconModel.chosenFileSource("/home/u/icons/app.png\n"), "file:///home/u/icons/app.png")
assert.equal(DockIconModel.chosenFileSource("/home/u/My Icons/app.SVG"),
  "file:///home/u/My%20Icons/app.SVG")
assert.equal(DockIconModel.chosenFileSource("file:///home/u/My%20Icons/app.svg\n"),
  "file:///home/u/My%20Icons/app.svg")
assert.equal(DockIconModel.chosenFileSource("\n/a/first.png\r\n/a/second.svg\n"), "file:///a/first.png")
assert.equal(DockIconModel.chosenFileSource("/a/first.jpg\n/a/second.svg\n"), "",
  "only the first chosen file is considered")
for (const empty of ["", "\n", "\n\n", null, undefined])
  assert.equal(DockIconModel.chosenFileSource(empty), "", "empty output " + JSON.stringify(empty))
assert.equal(DockIconModel.chosenFileSource("relative/app.png\n"), "", "relative paths are rejected")
assert.equal(DockIconModel.chosenFileSource("/a/app.gif\n"), "", "only PNG and SVG are accepted")

// Choose file lifecycle: hide while the out-of-process chooser runs, restore
// with the outcome, and ignore a result that outlives its dialog.
function dialogHarness() {
  const state = {
    DockIconModel, picking: false, visible: true, openAnchor: {}, inlineError: "old",
    chooserSerial: 0, chooserLaunchSerial: -1, chooserExitCode: -1, chooserOutputDone: false,
    imageSources: ["file:///a/recent.svg"], selectedSource: "file:///a/recent.svg", windows: [],
    fileChooser: { running: false }, chooserOutput: { text: "" }
  }
  const context = vm.createContext(state)
  context.root = context
  vm.runInContext(read("components/DockIconDialog.qml").match(/^  function [\s\S]*?^  }/gm).join("\n"),
    context)
  return context
}
function runChooser(dialog, exitCode, text = "") {
  dialog.chooseFile()
  assert.equal(dialog.picking, true)
  assert.equal(dialog.visible, false, "the dialog hides while the chooser is open")
  assert.equal(dialog.fileChooser.running, true)
  dialog.chooseFile()
  assert.equal(dialog.chooserLaunchSerial, dialog.chooserSerial, "a second launch is ignored")
  dialog.chooserOutput.text = text
  dialog.chooserExitCode = exitCode
  dialog.fileChooser.running = false
  dialog.settleChooser()
  if (exitCode === 0) {
    dialog.chooserOutputDone = true
    dialog.settleChooser()
  }
}
let dialog = dialogHarness()
runChooser(dialog, 0, "/home/u/new icon.png\n")
assert.equal(dialog.visible, true)
assert.equal(dialog.picking, false)
assert.equal(dialog.inlineError, "")
assert.equal(dialog.selectedSource, "file:///home/u/new%20icon.png")
assert.deepEqual([...dialog.imageSources], ["file:///home/u/new%20icon.png", "file:///a/recent.svg"])
runChooser(dialog, 0, "/a/recent.svg\n")
assert.deepEqual([...dialog.imageSources], ["file:///a/recent.svg", "file:///home/u/new%20icon.png"],
  "re-choosing a known file moves it to the front without duplicating it")

dialog = dialogHarness()
runChooser(dialog, 0, "/a/photo.jpg\n")
assert.equal(dialog.visible, true)
assert.equal(dialog.inlineError, "Choose a PNG or SVG file.")
assert.equal(dialog.selectedSource, "file:///a/recent.svg")

dialog = dialogHarness()
runChooser(dialog, 1)
assert.equal(dialog.visible, true)
assert.equal(dialog.inlineError, "", "nothing picked just restores the dialog")

for (const code of [2, 127, 6]) {
  dialog = dialogHarness()
  runChooser(dialog, code)
  assert.equal(dialog.visible, true)
  assert.equal(dialog.inlineError, "The file chooser could not be opened.", `exit ${code}`)
}

dialog = dialogHarness()
dialog.chooseFile()
dialog.closeDialog()
dialog.chooserOutput.text = "/a/late.png\n"
dialog.chooserExitCode = 0
dialog.chooserOutputDone = true
dialog.settleChooser()
assert.equal(dialog.visible, false, "a late chooser result does not reopen a closed dialog")
assert.equal(dialog.selectedSource, "file:///a/recent.svg")

console.log("icon dialog model tests passed")
