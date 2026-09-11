.pragma library

function normalizeKey(value) {
  if (typeof value !== "string") return ""
  var key = value.trim().toLowerCase().replace(/\.desktop$/, "")
  var reserved = Object.getOwnPropertyNames(Object.prototype).map(function(name) {
    return name.toLowerCase()
  })
  return !key || key === "unknown-application" || key === "prototype"
    || reserved.indexOf(key) >= 0 ? "" : key
}

function localFileUrl(value) {
  if (typeof value !== "string" || !value) return ""
  var path = value
  if (/^file:/i.test(value)) {
    var match = /^file:\/\/(?:localhost)?(\/[^?#]*)$/i.exec(value)
    if (!match) return ""
    try {
      path = decodeURIComponent(match[1])
    } catch (error) {
      return ""
    }
  }
  if (path[0] !== "/" || /[\u0000-\u001f\u007f]/.test(path)) return ""
  var parts = []
  var segments = path.split("/")
  for (var i = 0; i < segments.length; i++) {
    if (segments[i] === "..") parts.pop()
    else if (segments[i] && segments[i] !== ".") parts.push(segments[i])
  }
  try {
    return "file:///" + parts.map(function(part) {
      return encodeURIComponent(part)
    }).join("/") + (path.endsWith("/") && parts.length ? "/" : "")
  } catch (error) {
    return ""
  }
}

function normalizeSource(value) {
  var url = localFileUrl(value)
  return /\.(png|svg)$/i.test(url) ? url : ""
}

function normalizeOverrides(value) {
  var result = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return result
  Object.keys(value).forEach(function(rawKey) {
    var key = normalizeKey(rawKey)
    var source = normalizeSource(value[rawKey])
    if (key && source) result[key] = source
  })
  return result
}

function applyOverride(overrides, desktopId, sourceOrNull) {
  var updated = normalizeOverrides(overrides)
  var key = normalizeKey(desktopId)
  var source = sourceOrNull === null ? null : normalizeSource(sourceOrNull)
  if (!key || source === "")
    return { ok: false, changed: false, overrides: updated,
      error: !key ? "Invalid application ID" : "Select a local PNG or SVG file" }
  var changed = source === null ? Object.prototype.hasOwnProperty.call(updated, key)
    : updated[key] !== source
  if (source === null) delete updated[key]
  else updated[key] = source
  return { ok: true, changed: changed, overrides: updated, error: "" }
}

function candidates(overrideUrl, desktopUrl, genericUrl) {
  var result = []
  var sources = [overrideUrl, desktopUrl, genericUrl]
  sources.forEach(function(source) {
    if (typeof source === "string" && source && result.indexOf(source) < 0)
      result.push(source)
  })
  return result
}
