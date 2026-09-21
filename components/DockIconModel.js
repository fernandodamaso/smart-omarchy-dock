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

function faviconFileUrl(value) {
  var url = localFileUrl(value)
  return /\.(png|svg|ico|jpe?g|webp|gif)$/i.test(url) ? url : ""
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

function normalizeWindowAppId(value) {
  if (typeof value !== "string") return ""
  var id = value.trim().toLowerCase()
  return !id || /[\x00-\x1f\x7f]/.test(id) ? "" : id
}

function normalizeTitlePattern(value) {
  if (typeof value !== "string") return ""
  var pattern = value.trim()
  return !pattern || pattern.length > 200 || /[\x00-\x1f\x7f]/.test(pattern)
    ? "" : pattern
}

function windowRuleKey(appId, titlePattern) {
  var app = normalizeWindowAppId(appId)
  var pattern = normalizeTitlePattern(titlePattern)
  if (!app || !pattern) return ""
  pattern = pattern.toLowerCase()
  return app.length + ":" + app + "|" + pattern.length + ":" + pattern
}

function windowRulesError(value) {
  if (!Array.isArray(value)) return "Expected an array of window icon override rules"
  var seen = Object.create(null)
  for (var i = 0; i < value.length; ++i) {
    var rule = value[i]
    if (!rule || typeof rule !== "object" || Array.isArray(rule))
      return "Expected a window icon override object at index " + i
    var keys = Object.keys(rule).sort()
    if (keys.length !== 3 || keys[0] !== "appId" || keys[1] !== "source"
        || keys[2] !== "titlePattern")
      return "Window icon override entries require only appId, titlePattern and source at index " + i
    var appId = normalizeWindowAppId(rule.appId)
    if (!appId) return "Invalid raw Wayland appId at index " + i
    if (typeof rule.titlePattern !== "string" || !rule.titlePattern.trim())
      return "Title pattern must not be empty at index " + i
    if (rule.titlePattern.trim().length > 200)
      return "Title pattern must be at most 200 characters at index " + i
    if (/[\x00-\x1f\x7f]/.test(rule.titlePattern))
      return "Title pattern must not contain control characters at index " + i
    var pattern = normalizeTitlePattern(rule.titlePattern)
    if (!pattern) return "Invalid title pattern at index " + i
    if (!normalizeSource(rule.source))
      return "Expected a local PNG or SVG source at index " + i
    var key = windowRuleKey(appId, pattern)
    if (Object.prototype.hasOwnProperty.call(seen, key))
      return "Duplicate window icon override rule at index " + i
    seen[key] = true
  }
  return ""
}

function normalizeWindowRules(value) {
  if (windowRulesError(value)) return []
  return value.map(function(rule) {
    return {
      appId: normalizeWindowAppId(rule.appId),
      titlePattern: normalizeTitlePattern(rule.titlePattern),
      source: normalizeSource(rule.source)
    }
  })
}

// Only '*' is special. Matching is case-insensitive and anchored to the full
// title unless the pattern explicitly begins/ends with '*'. No regex is built,
// so adversarial wildcard input cannot trigger regex backtracking.
function titlePatternMatches(titlePattern, title) {
  var pattern = String(titlePattern || "").toLowerCase()
  var text = String(title === undefined || title === null ? "" : title).toLowerCase()
  if (!pattern) return false
  if (pattern === "*") return true
  var leadingWildcard = pattern.charAt(0) === "*"
  var trailingWildcard = pattern.charAt(pattern.length - 1) === "*"
  var parts = pattern.split("*").filter(function(part) { return part !== "" })
  if (parts.length === 0) return true
  var cursor = 0
  for (var i = 0; i < parts.length; ++i) {
    var position = text.indexOf(parts[i], cursor)
    if (position < 0) return false
    if (i === 0 && !leadingWildcard && position !== 0) return false
    cursor = position + parts[i].length
  }
  if (!trailingWildcard && cursor !== text.length) return false
  return true
}

function matchWindowRule(rules, appId, title) {
  var wanted = normalizeWindowAppId(appId)
  if (!wanted || !Array.isArray(rules)) return null
  for (var i = 0; i < rules.length; ++i) {
    var rule = rules[i]
    if (!rule || rule.appId !== wanted
        || !titlePatternMatches(rule.titlePattern, title)) continue
    return {
      appId: rule.appId,
      titlePattern: rule.titlePattern,
      source: rule.source,
      key: windowRuleKey(rule.appId, rule.titlePattern)
    }
  }
  return null
}

function candidates(windowUrl, profileUrl, overrideUrl, desktopUrl, genericUrl) {
  var result = []
  // Four arguments retain the historic profile -> app -> desktop -> generic
  // order. Five arguments opt into window -> profile -> app -> desktop -> generic.
  var sources = arguments.length >= 5
    ? [windowUrl, profileUrl, overrideUrl, desktopUrl, genericUrl]
    : [windowUrl, profileUrl, overrideUrl, desktopUrl]
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
