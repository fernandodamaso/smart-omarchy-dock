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

function normalizeProfileSegment(value) {
  if (typeof value !== "string") return ""
  var segment = value.trim().replace(/\s+/g, " ")
  return !segment || /[\x00-\x1f\x7f/\\@]/.test(segment) ? "" : segment
}

// Profile-aware keys read "id@profile:Dir" (e.g. google-chrome@profile:Profile 1).
function profileOverrideKey(desktopId, profileKey) {
  var id = normalizeKey(desktopId)
  var profile = normalizeProfileSegment(profileKey)
  return id && profile ? id + "@profile:" + profile : ""
}

function splitProfileKey(value) {
  if (typeof value !== "string") return null
  var marker = value.indexOf("@profile:")
  if (marker < 0) return null
  var id = normalizeKey(value.slice(0, marker))
  var profile = normalizeProfileSegment(value.slice(marker + 9))
  return id && profile ? { id: id, profile: profile } : null
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
    var key = normalizeOverrideKey(rawKey)
    var source = normalizeSource(value[rawKey])
    if (key && source) result[key] = source
  })
  return result
}

// Override map keys are either plain desktop IDs or profile-aware keys.
function normalizeOverrideKey(value) {
  var profileKey = splitProfileKey(value)
  return profileKey ? profileKey.id + "@profile:" + profileKey.profile
    : normalizeKey(value)
}

function applyOverride(overrides, desktopId, sourceOrNull) {
  var updated = normalizeOverrides(overrides)
  var key = normalizeOverrideKey(desktopId)
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

function candidates(profileUrl, overrideUrl, desktopUrl, genericUrl) {
  var result = []
  var sources = [profileUrl, overrideUrl, desktopUrl, genericUrl]
  sources.forEach(function(source) {
    if (typeof source === "string" && source && result.indexOf(source) < 0)
      result.push(source)
  })
  return result
}

// Deterministic badge color for profiles without a photo.
function badgeColor(name) {
  var text = String(name || "").trim()
  var hash = 0
  for (var i = 0; i < text.length; i++)
    hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  return "hsl(" + (hash % 360) + ", 55%, 50%)"
}
