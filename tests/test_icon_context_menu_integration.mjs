import assert from "node:assert/strict"
import fs from "node:fs"

const menuSource = fs.readFileSync("components/DockContextMenu.qml", "utf8")
const itemSource = fs.readFileSync("components/DockItem.qml", "utf8")
const dockSource = fs.readFileSync("components/Dock.qml", "utf8")
const readme = fs.readFileSync("README.md", "utf8")
const changelog = fs.readFileSync("CHANGELOG.md", "utf8")

function includes(source, needle, message) {
  assert.ok(source.includes(needle), message || `Missing expected source contract: ${needle}`)
}

// The application context menu exposes only capability flags + primitive intents.
includes(menuSource, "property bool canCustomizeIcon: false")
includes(menuSource, "property bool hasIconOverride: false")
includes(menuSource, "signal changeIcon()")
includes(menuSource, "signal restoreIcon()")
includes(menuSource, 'text: "Change icon…"')
includes(menuSource, 'text: "Restore default icon"')
includes(menuSource, "visible: !root.controlItem && root.canCustomizeIcon")
includes(menuSource,
  "visible: !root.controlItem && root.canCustomizeIcon && root.hasIconOverride")
includes(menuSource, "root.changeIcon()")
includes(menuSource, "root.restoreIcon()")

// DockItem owns canonical app identity and captures it before menu dismissal.
includes(itemSource, 'import "DockIconModel.js" as DockIconModel')
includes(itemSource, "signal changeIconRequested(string desktopId)")
includes(itemSource, "signal restoreIconRequested(string desktopId)")
includes(itemSource,
  "readonly property string customizableDesktopId: DockIconModel.normalizeKey(root.desktopId)")
includes(itemSource, "canCustomizeIcon: root.customizableDesktopId !== \"\"")
includes(itemSource, "hasIconOverride: root.hasIconOverride")
includes(itemSource, "var targetId = root.customizableDesktopId")
includes(itemSource, "contextMenu.dismiss()")
includes(itemSource, "root.changeIconRequested(targetId)")
includes(itemSource, "root.restoreIconRequested(targetId)")

// Dock routes Change to the stable Settings owner and opens Settings before Restore.
includes(dockSource,
  "onChangeIconRequested: desktopId => dockSettings.openIconEditor(desktopId)")
includes(dockSource, "onRestoreIconRequested: desktopId => {")
includes(dockSource, "if (!dockSettings.openIconEditor(desktopId)) return")
includes(dockSource, 'root.iconOverrideRequested(desktopId, "")')

// User docs describe the actual UI workflow and its persistence semantics.
assert.ok(!readme.includes("currently configured in JSON, not an\nicon editor"),
  "README still describes icon overrides as JSON-only")
includes(readme, "**Change icon…**")
includes(readme, "**Restore default icon**")
includes(readme, "preview only")
includes(readme, "same path")
includes(readme, "Retry save")
includes(readme, "SmartDock-only")
includes(readme, "browser tab")

includes(changelog, "## Unreleased")
includes(changelog, "Change icon…")
includes(changelog, "Restore default icon")

console.log("FDM-884 icon context-menu integration contract passed")
