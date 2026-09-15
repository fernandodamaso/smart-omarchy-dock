.pragma library

function normalizeWindowAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  if (address.slice(0, 2) === "0x") address = address.slice(2)
  return /^[0-9a-f]+$/.test(address) ? "0x" + address : ""
}

function mode(info) {
  var value = info || ({})
  var internal = Number(value.fullscreen || 0)
  var client = Number(value.fullscreenClient || 0)
  if (internal === 1 && client === 0) return "keep-bars"
  if (internal === 2 && client === 2) return "hide-bars"
  return "normal"
}

function targetMode(currentMode, selectedMode) {
  var current = String(currentMode || "normal")
  var selected = String(selectedMode || "")
  if (["keep-bars", "hide-bars"].indexOf(selected) < 0) return ""
  return current === selected ? "normal" : selected
}

function request(address, targetModeValue, usingLua) {
  var target = normalizeWindowAddress(address)
  var next = String(targetModeValue || "")
  if (!target || !usingLua) return ""

  var internal = -1
  var client = -1
  if (next === "normal") {
    internal = 0
    client = 0
  } else if (next === "keep-bars") {
    internal = 1
    client = 0
  } else if (next === "hide-bars") {
    internal = 2
    client = 2
  } else {
    return ""
  }

  return 'hl.dsp.window.fullscreen_state({ internal = ' + internal
    + ', client = ' + client
    + ', action = "set", window = "address:' + target + '" })'
}

function isManagedFullscreen(info) {
  return mode(info) !== "normal"
}
