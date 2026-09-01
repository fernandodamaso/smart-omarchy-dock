.pragma library

function normalizedId(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "")
}

function normalizeApplicationIds(value) {
  if (!Array.isArray(value)) return []

  var normalized = []
  for (var i = 0; i < value.length; ++i) {
    var id = String(value[i] === undefined || value[i] === null
      ? "" : value[i]).trim()
    if (!id) continue

    var key = id.toLowerCase()
    var duplicate = false
    for (var j = 0; j < normalized.length; ++j) {
      if (normalized[j].toLowerCase() === key) {
        duplicate = true
        break
      }
    }
    if (!duplicate) normalized.push(id)
  }
  return normalized
}

function addHiddenApplication(ids, desktopId) {
  var normalized = normalizeApplicationIds(ids)
  var id = String(desktopId === undefined || desktopId === null
    ? "" : desktopId).trim()
  if (!id) return normalized

  var key = id.toLowerCase()
  for (var i = 0; i < normalized.length; ++i) {
    if (normalized[i].toLowerCase() === key) return normalized
  }

  normalized.push(id)
  return normalized
}

function removeHiddenApplication(ids, desktopId) {
  var normalized = normalizeApplicationIds(ids)
  var id = String(desktopId === undefined || desktopId === null
    ? "" : desktopId).trim().toLowerCase()
  if (!id) return normalized

  var remaining = []
  for (var i = 0; i < normalized.length; ++i) {
    if (normalized[i].toLowerCase() !== id) remaining.push(normalized[i])
  }
  return remaining
}

function reorderPinnedById(pinnedIds, sourceDesktopId, targetDesktopId) {
  if (!Array.isArray(pinnedIds)) return []

  var sourceKey = normalizedId(sourceDesktopId).trim()
  var targetKey = normalizedId(targetDesktopId).trim()
  var sourceIndex = -1
  var targetIndex = -1

  if (!sourceKey || !targetKey || sourceKey === targetKey)
    return pinnedIds.slice()

  for (var i = 0; i < pinnedIds.length; ++i) {
    var itemKey = normalizedId(pinnedIds[i]).trim()
    if (itemKey === sourceKey && sourceIndex < 0) sourceIndex = i
    if (itemKey === targetKey && targetIndex < 0) targetIndex = i
  }

  if (sourceIndex < 0 || targetIndex < 0) return pinnedIds.slice()

  var reordered = pinnedIds.slice()
  var moved = reordered.splice(sourceIndex, 1)[0]
  reordered.splice(Math.min(targetIndex, reordered.length), 0, moved)
  return reordered
}

function hiddenApplicationRows(ids, entries) {
  var normalized = normalizeApplicationIds(ids)
  var availableEntries = []
  if (Array.isArray(entries)) {
    availableEntries = entries
  } else if (entries && typeof entries.length === "number") {
    for (var entryIndex = 0; entryIndex < entries.length; ++entryIndex)
      availableEntries.push(entries[entryIndex])
  }
  var rows = []

  for (var i = 0; i < normalized.length; ++i) {
    var id = normalized[i]
    var entry = entryForDesktopId(id, availableEntries)
    var name = entry && String(entry.name || "").trim()
    var icon = entry && String(entry.icon || "").trim()
    rows.push({
      id: id,
      name: name || id,
      icon: icon || "application-x-executable"
    })
  }

  return rows
}

function controlCommand(settings) {
  var configured = settings && settings.controlCommand
  var command = String(configured === undefined || configured === null
    ? "" : configured).trim()
  return command || "omarchy-menu toggle apps"
}

function settingsDefaults() {
  return {
    iconSize: 42,
    magnification: 1.2,
    magnificationRadius: 95,
    hoverGlowEnabled: true,
    hoverGlowOpacity: 0.72,
    hoverGlowRadius: 28,
    backgroundOpacity: 0.88,
    backgroundColorEnabled: false,
    backgroundColor: "",
    borderColorEnabled: false,
    borderColor: "",
    borderWidthEnabled: false,
    borderWidth: 2,
    position: "bottom",
    fullLength: false,
    reserveSpace: true,
    autoHide: false,
    clickAction: "focus-or-launch",
    controlCommand: "omarchy-menu toggle apps",
    sortByWorkspace: false,
    groupWindows: true
  }
}

function shouldReserveSpace(reserveSpace, autoHide) {
  return Boolean(reserveSpace) && !Boolean(autoHide)
}

function dockControlIcon(action, autoHide) {
  switch (action) {
  case "launcher":
    return "rocket"
  case "settings":
    return "settings-2"
  case "add":
    return "plus"
  case "auto-hide":
    return autoHide ? "eye" : "eye-off"
  default:
    return ""
  }
}

function steppedNumber(value, minimum, maximum, step, fallback, precision) {
  var number = Number(value)
  if (!isFinite(number)) number = fallback
  number = Math.max(minimum, Math.min(maximum, number))
  number = minimum + Math.round((number - minimum) / step) * step
  return Number(number.toFixed(precision || 0))
}

function normalizedHexColor(value) {
  var color = String(value === undefined || value === null ? "" : value)
    .trim().toLowerCase()
  return /^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/.test(color) ? color : ""
}

// Surface color settings may be either a literal hex value or a symbolic
// Omarchy theme token such as "@accent" / "@menu.background". Keeping the
// token in the existing setting means it follows theme changes automatically.
function normalizedColorValue(value) {
  var hex = normalizedHexColor(value)
  if (hex !== "") return hex

  var token = String(value === undefined || value === null ? "" : value)
    .trim().toLowerCase()
  return /^@[a-z][a-z0-9_.-]*$/.test(token) ? token : ""
}

function resolveColorValue(value, tokens, fallback) {
  var normalized = normalizedColorValue(value)
  if (normalized === "") return fallback
  if (normalized.charAt(0) !== "@") return normalized

  var token = normalized.slice(1)
  var resolved = tokens && tokens[token]
  return resolved === undefined || resolved === null ? fallback : resolved
}

function colorChannelHex(value, fallback) {
  var channel = Number(value)
  if (!isFinite(channel)) channel = fallback
  channel = Math.max(0, Math.min(1, channel))
  var hex = Math.round(channel * 255).toString(16)
  return hex.length === 1 ? "0" + hex : hex
}

function colorToHex(color) {
  if (!color) return ""

  var red = colorChannelHex(color.r, 0)
  var green = colorChannelHex(color.g, 0)
  var blue = colorChannelHex(color.b, 0)
  var alpha = colorChannelHex(color.a, 1)
  return alpha === "ff"
    ? "#" + red + green + blue
    : "#" + alpha + red + green + blue
}

function effectiveColor(enabled, override, themeColor, tokens) {
  return Boolean(enabled)
    ? resolveColorValue(override, tokens, themeColor)
    : themeColor
}

function effectiveBorderWidth(enabled, override, themeWidth) {
  if (!Boolean(enabled)) return themeWidth
  return steppedNumber(override, 0, 8, 1, 2, 0)
}

function surfaceColorMode(enabled, value) {
  var normalized = String(value || "").trim()
  if (!enabled || normalized === "") return "default"
  return normalized.indexOf("@") === 0 ? "token" : "custom"
}

function surfaceColorPatch(enabledKey, valueKey, value) {
  var validPair = (enabledKey === "backgroundColorEnabled"
      && valueKey === "backgroundColor")
    || (enabledKey === "borderColorEnabled"
      && valueKey === "borderColor")
  if (!validPair) return ({})

  var raw = String(value === undefined || value === null ? "" : value).trim()
  var patch = {}
  if (raw === "") {
    patch[enabledKey] = false
    return patch
  }

  var normalized = normalizeSetting(valueKey, raw)
  if (normalized === "") return ({})
  patch[enabledKey] = true
  patch[valueKey] = normalized
  return patch
}

function normalizeSetting(key, value) {
  var defaults = settingsDefaults()
  switch (key) {
  case "iconSize":
    return steppedNumber(value, 24, 96, 1, defaults.iconSize, 0)
  case "magnification":
    return steppedNumber(value, 1, 2, 0.05, defaults.magnification, 2)
  case "magnificationRadius":
    return steppedNumber(value, 40, 240, 5, defaults.magnificationRadius, 0)
  case "hoverGlowOpacity":
    return steppedNumber(value, 0, 1, 0.05, defaults.hoverGlowOpacity, 2)
  case "hoverGlowRadius":
    return steppedNumber(value, 0, 100, 5, defaults.hoverGlowRadius, 0)
  case "backgroundOpacity":
    return steppedNumber(value, 0, 1, 0.05, defaults.backgroundOpacity, 2)
  case "hoverGlowEnabled":
  case "backgroundColorEnabled":
  case "borderColorEnabled":
  case "borderWidthEnabled":
    return typeof value === "boolean" ? value : defaults[key]
  case "backgroundColor":
  case "borderColor":
    return normalizedColorValue(value)
  case "borderWidth":
    return steppedNumber(value, 0, 8, 1, defaults.borderWidth, 0)
  case "position":
    return ["top", "bottom", "left", "right"].indexOf(value) >= 0
      ? value : defaults.position
  case "fullLength":
  case "reserveSpace":
  case "autoHide":
  case "sortByWorkspace":
  case "groupWindows":
    return typeof value === "boolean" ? value : defaults[key]
  case "clickAction":
    return ["focus-or-launch", "launch"].indexOf(value) >= 0
      ? value : defaults.clickAction
  case "controlCommand":
    return controlCommand({ controlCommand: value })
  case "hiddenApplications":
    return normalizeApplicationIds(value)
  default:
    return value
  }
}

function resetSettingsPatch() {
  return settingsDefaults()
}

function mergeSettings(settings, patch) {
  var merged = {}
  var source = settings || ({})
  var changes = patch || ({})
  for (var key in source) merged[key] = source[key]
  for (var changedKey in changes) merged[changedKey] = changes[changedKey]
  return merged
}

function centeredPopupAnchor(position, screenWidth, screenHeight,
                             parentWidth, parentHeight,
                             popupWidth, popupHeight, margin) {
  var screenW = Math.max(1, Number(screenWidth) || 1)
  var screenH = Math.max(1, Number(screenHeight) || 1)
  var parentW = Math.max(0, Number(parentWidth) || 0)
  var parentH = Math.max(0, Number(parentHeight) || 0)
  var popupW = Math.max(1, Number(popupWidth) || 1)
  var popupH = Math.max(1, Number(popupHeight) || 1)
  var inset = Math.max(0, Number(margin) || 0)
  var parentLeft = 0
  var parentTop = 0
  var vertical = position === "left" || position === "right"

  if (vertical) {
    parentLeft = position === "right" ? screenW - parentW : 0
    parentTop = parentH < screenH
      ? (screenH - parentH) / 2 : 0
  } else {
    parentLeft = parentW < screenW ? (screenW - parentW) / 2 : 0
    parentTop = position === "bottom" ? screenH - parentH : 0
  }

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(value, Math.max(minimum, maximum)))
  }

  var globalX = clamp((screenW - popupW) / 2,
    inset, screenW - popupW - inset)
  var globalY = clamp((screenH - popupH) / 2,
    inset, screenH - popupH - inset)
  return {
    x: Math.round(globalX - parentLeft),
    y: Math.round(globalY - parentTop)
  }
}

function workspaceGridPosition(position, parentWidth, parentHeight,
                               iconSize, gridWidth, gridHeight) {
  var width = Math.max(0, Number(parentWidth) || 0)
  var height = Math.max(0, Number(parentHeight) || 0)
  var gridW = Math.max(0, Number(gridWidth) || 0)
  var gridH = Math.max(0, Number(gridHeight) || 0)

  return {
    x: Math.round(width / 2 - gridW / 2),
    y: Math.round(height / 2 - gridH / 2)
  }
}

function ipcWorkspaceFromHandle(handle) {
  var ipc = handle && handle.lastIpcObject ? handle.lastIpcObject : null
  return ipc && ipc.workspace ? ipc.workspace : null
}

function workspaceFromHandle(handle) {
  // Quickshell's object-level workspace relationship can be stale; prefer
  // the authoritative IPC record carried by lastIpcObject.
  return ipcWorkspaceFromHandle(handle)
    || (handle && handle.workspace) || ({})
}

function workspaceIpcWindowCount(workspace) {
  if (!workspace) return -1
  var ipc = workspace.lastIpcObject || ({})
  var count = Number(ipc.windows)
  if (Number.isInteger(count) && count >= 0) return count
  return -1
}

function isCountableWorkspaceHandle(handle) {
  var workspace = ipcWorkspaceFromHandle(handle)
  if (!workspace) return false
  var workspaceId = Number(workspace.id)
  var workspaceName = String(workspace.name || "")
  if (workspaceName.indexOf("special:") === 0) return false
  if (Number.isInteger(workspaceId) && workspaceId < 0) return false
  return Number.isInteger(workspaceId) && workspaceId > 0
}

function parseWorkspaceWindowCounts(output) {
  var counts = {}
  try {
    var values = JSON.parse(String(output || "[]"))
    for (var i = 0; i < values.length; ++i) {
      var workspace = values[i]
      var id = Number(workspace ? workspace.id : NaN)
      if (!Number.isInteger(id) || id < 1) continue
      counts[String(id)] = Math.max(0, Number(workspace.windows) || 0)
    }
  } catch (error) {
    return null
  }
  return counts
}

function workspaceWindowCount(workspaceId, handles, workspaces, counts, countsReady) {
  var target = Number(workspaceId)
  if (!Number.isInteger(target) || target < 1) return 0

  if (countsReady && counts) {
    var mapped = counts[String(target)]
    if (mapped !== undefined) {
      var fromMap = Number(mapped)
      if (Number.isInteger(fromMap) && fromMap >= 0) return fromMap
    }
    return 0
  }

  var workspaceValues = workspaces || []
  for (var w = 0; w < workspaceValues.length; ++w) {
    var workspace = workspaceValues[w]
    if (Number(workspace ? workspace.id : -1) !== target) continue
    var fromWorkspace = workspaceIpcWindowCount(workspace)
    if (fromWorkspace >= 0) return fromWorkspace
    break
  }

  var count = 0
  var values = handles || []
  for (var i = 0; i < values.length; ++i) {
    var handle = values[i]
    if (!handle || !isCountableWorkspaceHandle(handle)) continue
    if (Number(ipcWorkspaceFromHandle(handle).id) === target) count++
  }
  return count
}

function workspaceOccupied(workspace, handles, counts, countsReady) {
  var id = Number(workspace ? workspace.id : -1)
  if (countsReady && Number.isInteger(id) && id > 0) {
    if (counts && counts[String(id)] !== undefined)
      return Number(counts[String(id)]) > 0
    return false
  }

  var fromWorkspace = workspaceIpcWindowCount(workspace)
  if (fromWorkspace >= 0) return fromWorkspace > 0

  if (handles && Number.isInteger(id) && id > 0)
    return workspaceWindowCount(id, handles) > 0

  if (!workspace || !workspace.toplevels) return false
  var toplevels = Array.isArray(workspace.toplevels)
    ? workspace.toplevels : workspace.toplevels.values
  return Boolean(toplevels && toplevels.length > 0)
}

function focusedWorkspaceIdFromMonitors(monitors, focusedWorkspace) {
  var values = monitors || []
  var hasMonitorIpc = false

  for (var i = 0; i < values.length; ++i) {
    var ipc = values[i].lastIpcObject || ({})
    if (!ipc.activeWorkspace) continue
    hasMonitorIpc = true
    if (ipc.focused === true) {
      var id = Number(ipc.activeWorkspace.id)
      if (Number.isInteger(id) && id > 0) return id
    }
  }

  if (hasMonitorIpc) return -1

  var fallback = focusedWorkspace ? Number(focusedWorkspace.id) : -1
  return Number.isInteger(fallback) && fallback > 0 ? fallback : -1
}

function visibleWorkspaceIds(workspaces, focusedWorkspaceId, handles, counts, countsReady) {
  var ids = [1, 2]
  var values = workspaces || []
  var focused = Number(focusedWorkspaceId)

  for (var i = 0; i < values.length; ++i) {
    var workspace = values[i]
    var id = Number(workspace ? workspace.id : -1)
    if (!Number.isInteger(id) || id < 1 || id > 10) continue
    if (id === 1 || id === 2 || id === focused
        || workspaceOccupied(workspace, handles, counts, countsReady)) {
      if (ids.indexOf(id) < 0) ids.push(id)
    }
  }

  if (Number.isInteger(focused) && focused >= 1 && focused <= 10
      && ids.indexOf(focused) < 0)
    ids.push(focused)

  ids.sort(function(left, right) { return left - right })
  return ids
}

function focusWorkspaceRequest(workspace, usingLua) {
  var id = Number(workspace)
  if (!Number.isInteger(id) || id < 1 || id > 10) return ""
  if (usingLua)
    return 'hl.dsp.focus({ workspace = "' + id + '" })'
  return "workspace " + id
}

function focusWindowRequest(address, usingLua) {
  var target = normalizeWindowAddress(address)
  if (!target) return ""
  if (usingLua)
    return 'hl.dsp.focus({ window = "address:' + target + '" })'
  return "focuswindow address:" + target
}

function trashItemCount(output) {
  var listing = String(output || "").trim()
  if (!listing) return 0
  var lines = listing.split(/\r?\n/)
  var count = 0
  for (var i = 0; i < lines.length; ++i) {
    if (lines[i].trim()) count++
  }
  return count
}

function trashTooltip(itemCount) {
  var count = Math.max(0, Math.floor(Number(itemCount) || 0))
  if (count === 0) return "Trash — empty"
  return "Trash — " + count + (count === 1 ? " item" : " items")
}

function surfaceOpacity(themeAlpha, configuredOpacity) {
  var theme = Number(themeAlpha)
  var configured = Number(configuredOpacity)
  if (!isFinite(theme)) theme = 1
  if (!isFinite(configured)) configured = 1
  theme = Math.max(0, Math.min(1, theme))
  configured = Math.max(0, Math.min(1, configured))
  return theme * configured
}

function normalizeWindowAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  if (address.slice(0, 2) === "0x") address = address.slice(2)
  return /^[0-9a-f]+$/.test(address) ? "0x" + address : ""
}

function moveWindowRequest(address, workspace, usingLua) {
  var target = normalizeWindowAddress(address)
  var workspaceNumber = Number(workspace)
  if (!target || !Number.isInteger(workspaceNumber)
      || workspaceNumber < 1 || workspaceNumber > 10)
    return ""

  if (usingLua)
    return 'hl.dsp.window.move({ window = "address:' + target
      + '", workspace = "' + workspaceNumber + '", follow = false })'
  return "movetoworkspacesilent " + workspaceNumber + ",address:" + target
}

function minimizeWindowRequest(address, usingLua) {
  var target = normalizeWindowAddress(address)
  if (!target) return ""

  var workspace = "special:smartdock-minimized"
  if (usingLua)
    return 'hl.dsp.window.move({ window = "address:' + target
      + '", workspace = "' + workspace + '", follow = false })'
  return "movetoworkspacesilent " + workspace + ",address:" + target
}

function normalizeWorkspaceTarget(value) {
  var workspace = String(value || "").trim()
  if (/^[1-9][0-9]*$/.test(workspace)) return workspace
  if (/^name:[a-zA-Z0-9._-]+$/.test(workspace)) return workspace
  return ""
}

function restoreWindowRequest(address, workspace, usingLua) {
  var target = normalizeWindowAddress(address)
  var workspaceTarget = normalizeWorkspaceTarget(workspace)
  if (!target || !workspaceTarget) return ""

  if (usingLua)
    return 'hl.dsp.window.move({ window = "address:' + target
      + '", workspace = "' + workspaceTarget + '", follow = true })'
  return "movetoworkspace " + workspaceTarget + ",address:" + target
}

function fakeFullscreenRequest(address, enabled, usingLua) {
  var target = normalizeWindowAddress(address)
  if (!target || !usingLua) return ""

  var state = enabled ? 1 : 0
  return 'hl.dsp.window.fullscreen_state({ internal = ' + state
    + ', client = 0, action = "set", window = "address:' + target + '" })'
}

function windowStateCounts(states) {
  var total = states ? states.length : 0
  var minimized = 0
  for (var i = 0; i < total; ++i) {
    if (states[i] && states[i].minimized === true) minimized++
  }
  return {
    total: total,
    minimized: minimized,
    visible: total - minimized
  }
}

function isFakeFullscreen(info) {
  return Boolean(info)
    && Number(info.fullscreen || 0) === 1
    && Number(info.fullscreenClient || 0) === 0
}

function isFullscreenWithBars(info) {
  return Boolean(info) && Number(info.fullscreen || 0) === 1
}

function fullscreenOwner(toplevels, handles, focusedWorkspaceId, activeToplevel) {
  var workspaceId = Number(focusedWorkspaceId)
  if (!Number.isInteger(workspaceId)) return null

  var windows = toplevels || []
  var hyprHandles = handles || []
  var owner = null
  var activeOnFocusedWorkspace = false
  for (var i = 0; i < hyprHandles.length; ++i) {
    var handle = hyprHandles[i]
    if (!handle || !handle.wayland || windows.indexOf(handle.wayland) < 0)
      continue

    // Quickshell's object-level workspace relationship can be stale; prefer
    // the authoritative IPC record carried by lastIpcObject.
    var ipc = handle.lastIpcObject || ({})
    var handleWorkspace = ipc.workspace || handle.workspace || ({})
    var handleWorkspaceId = Number(handleWorkspace.id)
    if (handleWorkspaceId !== workspaceId) continue
    if (handle.wayland === activeToplevel)
      activeOnFocusedWorkspace = true
    if (!owner && isFullscreenWithBars(ipc))
      owner = handle.wayland
  }
  return owner && activeOnFocusedWorkspace ? activeToplevel : owner
}

function fullscreenIconPresentation(modeActive, isOwner, hovered) {
  if (isOwner)
    return { scale: 1.15, opacity: 1.0 }
  if (!modeActive || hovered)
    return { scale: 1.0, opacity: 1.0 }
  return { scale: 0.9, opacity: 0.45 }
}

function shouldRefreshFullscreenPresentation(eventName) {
  return [
    "activewindow",
    "activewindowv2",
    "fullscreen",
    "workspace",
    "workspacev2",
    "openwindow",
    "closewindow",
    "movewindow",
    "movewindowv2"
  ].indexOf(String(eventName || "")) >= 0
}

function shouldRefreshWorkspaceState(eventName) {
  return [
    "openwindow",
    "closewindow",
    "movewindow",
    "movewindowv2",
    "workspace",
    "workspacev2",
    "createworkspace",
    "createworkspacev2",
    "destroyworkspace",
    "destroyworkspacev2",
    "focusedmon",
    "activewindow",
    "activewindowv2"
  ].indexOf(String(eventName || "")) >= 0
}

function workspaceBadgeText(toplevels, handles) {
  var windows = toplevels || []
  var hyprHandles = handles || []
  var labels = []

  for (var i = 0; i < windows.length; ++i) {
    var window = windows[i]
    var label = ""
    for (var j = 0; j < hyprHandles.length; ++j) {
      var handle = hyprHandles[j]
      if (!handle || handle.wayland !== window) continue

      // Quickshell's object-level workspace relationship can be stale; prefer
      // the authoritative IPC record carried by lastIpcObject.
      var ipc = handle.lastIpcObject || ({})
      var workspace = ipc.workspace || handle.workspace || ({})
      var workspaceId = Number(workspace.id)
      var workspaceName = String(workspace.name || "")
      if (workspaceName.indexOf("special:") === 0
          || (Number.isInteger(workspaceId) && workspaceId < 0))
        continue
      else if (Number.isInteger(workspaceId) && workspaceId > 0)
        label = String(workspaceId)
      break
    }

    if (label && labels.indexOf(label) < 0)
      labels.push(label)
  }

  labels.sort(function(left, right) {
    return Number(left) - Number(right)
  })

  if (labels.length > 3)
    return labels.slice(0, 2).join("·") + "+"
  return labels.join("·")
}

function windowStatusLabel(state) {
  if (!state) return ""
  if (state.minimized === true) return "[minimized]"

  var workspace = String(state.workspace || "").trim()
  if (!workspace) return ""
  if (workspace.indexOf("name:") === 0)
    workspace = workspace.slice(5)
  return "[" + workspace + "]"
}

function floatWindowRequest(address, action, usingLua) {
  var target = normalizeWindowAddress(address)
  if (!target || ["toggle", "enable", "disable"].indexOf(action) < 0)
    return ""

  if (usingLua)
    return 'hl.dsp.window.float({ window = "address:' + target
      + '", action = "' + action + '" })'
  if (action === "enable") return "setfloating address:" + target
  if (action === "disable") return "settiled address:" + target
  return "togglefloating address:" + target
}

function pinWindowRequest(address, usingLua) {
  var target = normalizeWindowAddress(address)
  if (!target) return ""

  if (usingLua)
    return 'hl.dsp.window.pin({ window = "address:' + target
      + '", action = "toggle" })'
  return "pin address:" + target
}

function nextToplevelIndex(currentIndex, count) {
  if (count <= 0) return -1
  if (currentIndex < 0 || currentIndex >= count - 1) return 0
  return currentIndex + 1
}

function entryForDesktopId(desktopId, entries) {
  var wanted = normalizedId(desktopId)
  for (var i = 0; i < entries.length; ++i) {
    if (normalizedId(entries[i].id) === wanted)
      return entries[i]
  }
  return null
}

function entryForAppId(appId, entries) {
  var wanted = normalizedId(appId)
  for (var i = 0; i < entries.length; ++i) {
    var entry = entries[i]
    if (normalizedId(entry.id) === wanted
        || normalizedId(entry.startupClass) === wanted)
      return entry
  }
  return null
}

function webAppId(entry) {
  if (!entry || !entry.command) return ""

  for (var i = 0; i < entry.command.length; ++i) {
    var match = String(entry.command[i]).match(/https?:\/\/[^?#\s]+/i)
    if (!match) continue

    var url = match[0].replace(/^https?:\/\//i, "").replace(/\/$/, "")
    try {
      url = decodeURIComponent(url)
    } catch (error) {
      // The encoded URL can still match a generated browser app ID.
    }
    return url.toLowerCase().replace(/[^a-z0-9]/g, "")
  }
  return ""
}

function entryMatchesAppId(desktopId, entry, appId) {
  var wanted = normalizedId(appId)
  if (!wanted) return false

  if (normalizedId(desktopId) === wanted
    || (entry && normalizedId(entry.id) === wanted)
    || (entry && normalizedId(entry.startupClass) === wanted))
    return true

  var generatedId = webAppId(entry)
  return generatedId.length >= 6
    && wanted.replace(/[^a-z0-9]/g, "").indexOf(generatedId) >= 0
}

function itemWorkspaceId(item, handles) {
  if (!item || !item.toplevels || item.toplevels.length === 0)
    return Infinity

  var values = Array.isArray(item.toplevels)
    ? item.toplevels : item.toplevels.values
  var ids = []

  for (var i = 0; i < values.length; ++i) {
    var window = values[i]
    if (!window) continue
    for (var j = 0; j < handles.length; ++j) {
      var handle = handles[j]
      if (!handle || handle.wayland !== window) continue

      // Quickshell's object-level workspace relationship can be stale; prefer
      // the authoritative IPC record carried by lastIpcObject.
      var ipc = handle.lastIpcObject || ({})
      var workspace = ipc.workspace || handle.workspace || ({})
      var id = Number(workspace.id)
      if (Number.isInteger(id) && id > 0 && ids.indexOf(id) < 0)
        ids.push(id)
      break
    }
  }

  if (ids.length === 0) return Infinity
  ids.sort(function(a, b) { return a - b })
  return ids[0]
}

function buildVisibleItems(pinnedIds, toplevels, entries, handles, sortByWorkspace,
                           groupWindows, hiddenApplicationIds) {
  var items = []
  var runningByKey = {}
  var nextOriginalIndex = 0
  var mergeWindows = groupWindows !== false

  for (var i = 0; i < pinnedIds.length; ++i) {
    var pinnedId = pinnedIds[i]
    var pinnedItem = {
      desktopId: pinnedId,
      pinned: true,
      toplevels: [],
      originalIndex: nextOriginalIndex++
    }
    items.push(pinnedItem)
  }

  for (var topIndex = 0; topIndex < toplevels.length; ++topIndex) {
    var toplevel = toplevels[topIndex]
    var matchedPinned = false

    if (mergeWindows) {
      for (var pinnedIndex = 0; pinnedIndex < items.length; ++pinnedIndex) {
        var item = items[pinnedIndex]
        var pinnedEntry = entryForDesktopId(item.desktopId, entries)
        if (!entryMatchesAppId(item.desktopId, pinnedEntry, toplevel.appId))
          continue

        item.toplevels.push(toplevel)
        matchedPinned = true
        break
      }

      if (matchedPinned) continue
    }

    var runningEntry = entryForAppId(toplevel.appId, entries)
    var desktopId = runningEntry && runningEntry.id
      ? runningEntry.id
      : String(toplevel.appId || "unknown-application")

    if (!mergeWindows) {
      var attachedPinned = false
      for (var pinIndex = 0; pinIndex < items.length; ++pinIndex) {
        var pinnedItem = items[pinIndex]
        if (pinnedItem.toplevels.length > 0) continue
        var pinnedEntry = entryForDesktopId(pinnedItem.desktopId, entries)
        if (!entryMatchesAppId(pinnedItem.desktopId, pinnedEntry, toplevel.appId))
          continue
        pinnedItem.toplevels.push(toplevel)
        attachedPinned = true
        break
      }
      if (attachedPinned) continue

      items.push({
        desktopId: desktopId,
        pinned: false,
        toplevels: [toplevel],
        originalIndex: nextOriginalIndex++
      })
      continue
    }

    var key = normalizedId(desktopId)
    var runningItem = runningByKey[key]
    if (!runningItem) {
      runningItem = {
        desktopId: desktopId,
        pinned: false,
        toplevels: [],
        originalIndex: nextOriginalIndex++
      }
      runningByKey[key] = runningItem
      items.push(runningItem)
    }
    runningItem.toplevels.push(toplevel)
  }

  if (sortByWorkspace) {
    items.sort(function(a, b) {
      // Closed pinned apps stay at the front in their configured order.
      var aClosedPinned = a.pinned && a.toplevels.length === 0
      var bClosedPinned = b.pinned && b.toplevels.length === 0
      if (aClosedPinned && !bClosedPinned) return -1
      if (!aClosedPinned && bClosedPinned) return 1

      // Everything else is ordered by the lowest workspace id it occupies.
      var aWorkspace = itemWorkspaceId(a, handles)
      var bWorkspace = itemWorkspaceId(b, handles)
      if (aWorkspace !== bWorkspace) return aWorkspace - bWorkspace

      // Pinned items precede unpinned items on the same workspace.
      if (a.pinned && !b.pinned) return -1
      if (!a.pinned && b.pinned) return 1

      // Preserve the original construction order for a stable layout.
      return a.originalIndex - b.originalIndex
    })
  }

  var hiddenIds = normalizeApplicationIds(hiddenApplicationIds)
  var visibleItems = []
  for (var itemIndex = 0; itemIndex < items.length; ++itemIndex) {
    var itemKey = normalizedId(items[itemIndex].desktopId)
    var hidden = false
    for (var hiddenIndex = 0; hiddenIndex < hiddenIds.length; ++hiddenIndex) {
      if (normalizedId(hiddenIds[hiddenIndex]) === itemKey) {
        hidden = true
        break
      }
    }
    if (!hidden) visibleItems.push(items[itemIndex])
  }

  return visibleItems
}
