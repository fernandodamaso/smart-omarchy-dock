pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel
import "DockTrashModel.js" as TrashModel

// Exactly one host-owned target, never one target per screen/Variants delegate.
Item {
  id: root
  required property var host
  readonly property var defaults: JSON.parse(defaultsFile.text())
  readonly property var metadata: JSON.parse(schemaFile.text())

  FileView {
    id: defaultsFile
    path: Qt.resolvedUrl("../config/dock.json")
    blockLoading: true
  }
  FileView {
    id: schemaFile
    path: Qt.resolvedUrl("../config/settings-schema.json")
    blockLoading: true
  }

  function success(data, warnings) {
    return { apiVersion: 1, ok: true, data: data, warnings: warnings || [] }
  }

  function failure(code, message, data) {
    return { apiVersion: 1, ok: false, error: { code: code, message: message },
      data: data || {}, warnings: [] }
  }

  function statusData() {
    return {
      runtime: { mode: root.host.runtimeMode, instanceId: String(Quickshell.processId) },
      configPath: root.host.configPath,
      loadState: root.host.settingsLoadState,
      loadError: root.host.settingsLoadError,
      loadPending: root.host.settingsReloadPending || !root.host.settingsLoaded,
      revision: root.host.settingsRevision,
      writeState: root.host.settingsWriteState,
      writeError: root.host.settingsWriteError,
      persisted: root.host.settingsPersisted,
      defaultsInUse: root.host.settingsDefaultsInUse
    }
  }

  function schemaSettings(key) {
    var result = {}
    var keys = key === undefined ? Object.keys(root.metadata.settings) : [key]
    for (var i = 0; i < keys.length; ++i) {
      var name = keys[i]
      if (!Object.prototype.hasOwnProperty.call(root.metadata.settings, name))
        throw new Error("Unknown setting: " + name)
      result[name] = Object.assign({}, root.metadata.settings[name], {
        default: root.defaults[name]
      })
    }
    return result
  }

  function effectiveSettings(requested) {
    var result = JSON.parse(JSON.stringify(requested))
    var keys = Object.keys(root.defaults)
    for (var i = 0; i < keys.length; ++i) {
      var key = keys[i]
      var value = requested[key] === undefined ? root.defaults[key] : requested[key]
      result[key] = DockModel.normalizeSetting(key, value)
    }
    result.showTrash = TrashModel.normalizeShowTrash(requested.showTrash)
    result.windowScope = DockWindowModel.normalizeWindowScope(requested.windowScope)
    result.showUrgentOutsideScope = DockWindowModel.normalizeShowUrgentOutsideScope(
      requested.showUrgentOutsideScope)
    result.attentionBadgesEnabled = typeof requested.attentionBadgesEnabled === "boolean"
      ? requested.attentionBadgesEnabled : true
    result.urgentWindowAnimationEnabled = typeof requested.urgentWindowAnimationEnabled === "boolean"
      ? requested.urgentWindowAnimationEnabled : true
    result.launcherBadgeMode = requested.launcherBadgeMode === "dots-only" ? "dots-only" : "automatic"
    result.reserveSpace = DockModel.shouldReserveSpace(result.reserveSpace, result.autoHide)
    if (result.position === "left" || result.position === "right") result.workspaceLayout = "flat"
    if (result.workspaceLayout === "flat") result.workspaceMonitorScope = "all"
    // Rendering resolves theme values in each dock. Null is deliberately not an
    // invented resolved color/width; requested overrides remain fully available.
    var colors = ["backgroundColor", "borderColor", "workspaceBadgeBackgroundColor", "workspaceBadgeTextColor"]
    for (var c = 0; c < colors.length; ++c) {
      var color = colors[c]
      if (!result[color + "Enabled"] || !result[color] || result[color].charAt(0) === "@")
        result[color] = null
    }
    if (!result.borderWidthEnabled) result.borderWidth = null
    return result
  }

  function handle(payload) {
    var request
    try {
      request = JSON.parse(payload)
    } catch (error) {
      return root.failure("E_USAGE", "Request must be a JSON object.")
    }
    if (!request || Array.isArray(request) || request.apiVersion !== 1
        || typeof request.command !== "string" || !request.arguments
        || typeof request.arguments !== "object" || Array.isArray(request.arguments))
      return root.failure("E_PROTOCOL", "Expected apiVersion=1, command and arguments object.")
    var args = request.arguments
    var command = request.command
    var allowed = command === "config.get" ? ["key", "effective"]
      : command === "config.schema" ? ["key"] : []
    if (Object.keys(args).some(function(key) { return allowed.indexOf(key) < 0 })
        || (args.key !== undefined && typeof args.key !== "string")
        || (args.effective !== undefined && typeof args.effective !== "boolean"))
      return root.failure("E_USAGE", "Invalid arguments for " + command)
    if (command === "status" || command === "doctor")
      return root.success(root.statusData())
    if (command !== "config.schema" && command !== "config.get")
      return root.failure("E_USAGE", "Unsupported command: " + command)
    var data = root.statusData()
    data.source = "runtime"
    if (command === "config.schema") {
      try {
        data.schemaVersion = root.metadata.schemaVersion
        data.commands = root.metadata.commands
        data.settings = root.schemaSettings(args.key)
        return root.success(data)
      } catch (error) {
        return root.failure("E_VALIDATION", String(error), data)
      }
    }
    if (args.key !== undefined && !Object.prototype.hasOwnProperty.call(root.host.settings, args.key))
      return root.failure("E_VALIDATION", "Unknown setting: " + args.key, data)
    var values = args.effective ? root.effectiveSettings(root.host.settings) : root.host.settings
    data.view = args.effective ? "effective" : "requested"
    data.settings = args.key === undefined ? values : ({})
    if (args.key !== undefined) data.settings[args.key] = values[args.key]
    data.themeResolution = "not-reported"
    var warnings = args.effective
      ? ["Theme-owned/token colors and theme-owned border width are null, not resolved by this headless host."] : []
    if (root.host.settingsLoadState === "invalid") warnings.push("Invalid disk config; showing last-good live settings.")
    if (!root.host.settingsPersisted) warnings.push("Live settings are not confirmed persisted.")
    return root.success(data, warnings)
  }

  IpcHandler {
    target: "smartdock"
    function request(payload: string): string {
      try {
        return JSON.stringify(root.handle(payload))
      } catch (error) {
        return JSON.stringify(root.failure("E_PROTOCOL", "Host could not process request: " + String(error)))
      }
    }
  }
}
