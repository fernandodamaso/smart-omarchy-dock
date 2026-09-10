import assert from "node:assert/strict"
import fs from "node:fs"

const settingsSource = fs.readFileSync("components/DockSettings.qml", "utf8")
const dockSource = fs.readFileSync("components/Dock.qml", "utf8")
const hostSource = fs.readFileSync("DockHost.qml", "utf8")

function includes(source, needle, message) {
  assert.ok(source.includes(needle), message || `Missing expected source contract: ${needle}`)
}

// DockSettings owns the selected-app workflow and emits only single-app intents.
includes(settingsSource, 'import "DockIconModel.js" as DockIconModel')
includes(settingsSource, 'property string settingsWriteState: "idle"')
includes(settingsSource, 'property string settingsWriteError: ""')
includes(settingsSource, 'signal iconOverrideRequested(string desktopId, string sourceUrl)')
includes(settingsSource, 'signal settingsWriteRetryRequested()')
includes(settingsSource, 'function openIconEditor(desktopId)')
includes(settingsSource, 'title: "Application icons"')
includes(settingsSource, 'text: "Right-click an app in the dock to change its icon."')
includes(settingsSource, 'DockIconOverrideEditor {')
includes(settingsSource, 'onApplyRequested: (desktopId, sourceUrl) =>')
includes(settingsSource, 'root.iconOverrideRequested(desktopId, sourceUrl)')
includes(settingsSource, 'onRestoreRequested: desktopId => root.iconOverrideRequested(desktopId, "")')

// The Settings-owned chooser is in-window and read-only. This verifies wiring only;
// real layering/focus/Escape behavior remains a local Omarchy runtime check.
includes(settingsSource, 'FileDialog {')
includes(settingsSource, 'fileMode: FileDialog.OpenFile')
includes(settingsSource, 'popupType: QQC.Popup.Item')
includes(settingsSource, 'FileDialog.DontUseNativeDialog | FileDialog.ReadOnly')
includes(settingsSource, 'property string capturedDesktopId: ""')
includes(settingsSource, 'property string capturedCurrentSource: ""')
includes(settingsSource, 'iconOverrideEditor.selectFile(selectedFile)')

// Whole-config write feedback/retry stays global and survives row removal.
includes(settingsSource, 'settingsWriteError')
includes(settingsSource, 'root.settingsWriteRetryRequested()')
includes(settingsSource, 'icon previews require Apply')

// Dock forwards the contract without owning an overrides snapshot.
includes(dockSource, 'property string settingsWriteState: "idle"')
includes(dockSource, 'property string settingsWriteError: ""')
includes(dockSource, 'signal iconOverrideRequested(string desktopId, string sourceUrl)')
includes(dockSource, 'signal settingsWriteRetryRequested()')
includes(dockSource, 'settingsWriteState: root.settingsWriteState')
includes(dockSource, 'settingsWriteError: root.settingsWriteError')
includes(dockSource, 'onIconOverrideRequested: (desktopId, sourceUrl) =>')
includes(dockSource, 'root.iconOverrideRequested(desktopId, sourceUrl)')
includes(dockSource, 'onSettingsWriteRetryRequested: root.settingsWriteRetryRequested()')

// DockHost remains the sole persistence owner.
includes(hostSource, 'settingsWriteState: root.settingsWriteState')
includes(hostSource, 'settingsWriteError: root.settingsWriteError')
includes(hostSource, 'onIconOverrideRequested: (desktopId, sourceUrl) =>')
includes(hostSource, 'root.saveIconOverride(desktopId, sourceUrl)')
includes(hostSource, 'onSettingsWriteRetryRequested: root.retrySettingsWrite()')

console.log("FDM-883 icon Settings integration contract passed")
