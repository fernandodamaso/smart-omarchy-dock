var BADGE_NONE = "none"
var BADGE_ATTENTION = "attention"
var BADGE_URGENT = "urgent"
var BADGE_COUNT_MODE_AUTOMATIC = "automatic"
var BADGE_COUNT_MODE_DOTS_ONLY = "dots-only"
var LOCAL_ATTENTION_TTL_MS = 24 * 60 * 60 * 1000
var FOCUS_DWELL_MS = 800

function normalizeIdentity(value) {
  return String(value === undefined || value === null ? "" : value)
    .trim().toLowerCase().replace(/\.desktop$/, "")
}

function normalizeLauncherIdentity(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim()
  raw = raw.replace(/^application:\/\//i, "")
  try {
    raw = decodeURIComponent(raw)
  } catch (_) {
    return ""
  }
  if (!raw || raw === "." || raw === ".."
      || raw.indexOf("://") >= 0
      || raw.indexOf("/") >= 0
      || raw.indexOf("\\") >= 0) return ""
  return normalizeIdentity(raw)
}

function canonicalLauncherDesktopId(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim()
  if (/^application:\/\//i.test(raw)) return normalizeLauncherIdentity(raw)
  try {
    raw = decodeURIComponent(raw)
  } catch (_) {
    return ""
  }
  if (!raw || raw === "." || raw === ".."
      || raw.indexOf("://") >= 0
      || raw.indexOf("/") >= 0
      || raw.indexOf("\\") >= 0) return ""
  return raw.toLowerCase()
}

function normalizeLauncherBadgeMode(value) {
  return value === BADGE_COUNT_MODE_DOTS_ONLY
    ? BADGE_COUNT_MODE_DOTS_ONLY : BADGE_COUNT_MODE_AUTOMATIC
}

function normalizeLauncherCount(value) {
  if (typeof value === "boolean" || value === "") return null
  var count = Number(value)
  if (!isFinite(count)) return null
  return Math.max(0, Math.floor(count))
}

function appendIdentity(target, value) {
  var normalized = normalizeIdentity(value)
  if (normalized && target.indexOf(normalized) < 0) target.push(normalized)
}

function identityCandidates(desktopId, entry, aliases) {
  var candidates = []
  appendIdentity(candidates, desktopId)
  if (entry) {
    appendIdentity(candidates, entry.id)
    appendIdentity(candidates, entry.startupClass)
    appendIdentity(candidates, entry.name)
  }

  var explicit = aliases || ({})
  for (var key in explicit) {
    if (candidates.indexOf(normalizeIdentity(key)) < 0) continue
    var values = Array.isArray(explicit[key]) ? explicit[key] : [explicit[key]]
    for (var i = 0; i < values.length; ++i) appendIdentity(candidates, values[i])
  }
  return candidates
}

function strictIdentityMatches(desktopId, entry, sourceValues, aliases) {
  var candidates = identityCandidates(desktopId, entry, aliases)
  var sources = Array.isArray(sourceValues) ? sourceValues : [sourceValues]
  for (var i = 0; i < sources.length; ++i) {
    var source = normalizeIdentity(sources[i])
    if (source && candidates.indexOf(source) >= 0) return true
  }
  return false
}

function entryForStrictSource(sourceValues, entries, aliases) {
  var values = entries || []
  for (var i = 0; i < values.length; ++i) {
    var entry = values[i]
    if (!entry) continue
    if (strictIdentityMatches(entry.id, entry, sourceValues, aliases)) return entry
  }
  return null
}

function entryForDesktopId(desktopId, entries) {
  var wanted = normalizeIdentity(desktopId)
  var values = entries || []
  for (var i = 0; i < values.length; ++i) {
    var entry = values[i]
    if (entry && normalizeIdentity(entry.id) === wanted) return entry
  }
  return null
}

function severityRank(value) {
  if (value === BADGE_URGENT) return 2
  if (value === BADGE_ATTENTION) return 1
  return 0
}

function reduceSeverity(values) {
  var result = BADGE_NONE
  var list = values || []
  for (var i = 0; i < list.length; ++i) {
    if (severityRank(list[i]) > severityRank(result)) result = list[i]
  }
  return result
}

function notificationSeverity(urgency, criticalUrgency) {
  return Number(urgency) === Number(criticalUrgency)
    ? BADGE_URGENT : BADGE_ATTENTION
}

function notificationSourceValues(row) {
  var values = []
  var source = row || ({})
  appendIdentity(values, source.app)
  appendIdentity(values, source.appIcon)
  return values
}

function notificationKey(row) {
  var source = row || ({})
  var id = Number(source.originalId)
  if (isFinite(id) && id >= 0) return "id:" + String(id)
  return "event:" + String(Number(source.timestamp) || 0)
    + ":" + normalizeIdentity(source.app)
    + ":" + normalizeIdentity(source.appIcon)
}

function copyRecords(records) {
  var next = {}
  var source = records || ({})
  for (var key in source) next[key] = source[key]
  return next
}

function upsertNotification(records, row, criticalUrgency, now) {
  var source = row || ({})
  var timestamp = Number(source.timestamp)
  if (!isFinite(timestamp) || timestamp <= 0) timestamp = Number(now) || 0

  var next = copyRecords(records)
  next[notificationKey(source)] = {
    originalId: source.originalId,
    sourceValues: notificationSourceValues(source),
    severity: notificationSeverity(source.urgency, criticalUrgency),
    timestamp: timestamp
  }
  return next
}

function pruneExpired(records, now, ttlMs) {
  var current = Number(now) || 0
  var ttl = Number(ttlMs)
  if (!isFinite(ttl) || ttl <= 0) ttl = LOCAL_ATTENTION_TTL_MS
  var next = {}
  var source = records || ({})
  for (var key in source) {
    var record = source[key]
    var timestamp = Number(record && record.timestamp)
    if (!isFinite(timestamp) || timestamp <= 0) continue
    if (current - timestamp < ttl) next[key] = record
  }
  return next
}

function recordExpired(record, now, ttlMs) {
  if (now === undefined || now === null) return false
  var timestamp = Number(record && record.timestamp)
  if (!isFinite(timestamp) || timestamp <= 0) return true
  var ttl = Number(ttlMs)
  if (!isFinite(ttl) || ttl <= 0) ttl = LOCAL_ATTENTION_TTL_MS
  return Number(now) - timestamp >= ttl
}

function localSeverity(records, desktopId, entry, aliases, now, ttlMs) {
  var result = BADGE_NONE
  var source = records || ({})
  for (var key in source) {
    var record = source[key]
    if (!record || recordExpired(record, now, ttlMs)) continue
    if (!strictIdentityMatches(desktopId, entry, record.sourceValues, aliases))
      continue
    result = reduceSeverity([result, record.severity])
  }
  return result
}

function clearMatchingNotifications(records, desktopId, entry, aliases) {
  var next = {}
  var source = records || ({})
  for (var key in source) {
    var record = source[key]
    if (record && strictIdentityMatches(
        desktopId, entry, record.sourceValues, aliases)) continue
    next[key] = record
  }
  return next
}

function badgeSeverity(sniNeedsAttention, hyprUrgent, localAttention) {
  return reduceSeverity([
    sniNeedsAttention ? BADGE_ATTENTION : BADGE_NONE,
    hyprUrgent ? BADGE_URGENT : BADGE_NONE,
    localAttention || BADGE_NONE
  ])
}

function launcherCountState(records, desktopId, providerAvailable) {
  var none = { authoritative: false, count: 0, visible: false }
  if (!providerAvailable) return none

  // A canonical desktop-entry ID can legitimately end in `.desktop` (its
  // storage filename then ends in `.desktop.desktop`). Prefer the exact ID and
  // only then try storage-filename normalization, avoiding one suffix too many.
  var candidates = []
  var canonical = canonicalLauncherDesktopId(desktopId)
  if (canonical) candidates.push(canonical)
  var storageId = normalizeLauncherIdentity(desktopId)
  if (storageId && candidates.indexOf(storageId) < 0) candidates.push(storageId)

  for (var i = 0; i < candidates.length; ++i) {
    var record = records && records[candidates[i]]
    if (!record || typeof record !== "object") continue
    var count = normalizeLauncherCount(record.count)
    if (count === null) continue
    return {
      authoritative: true,
      count: count,
      visible: record.visible === true
    }
  }
  return none
}

function applicationBadgePresentation(enabled, mode, countState, severity) {
  var safeSeverity = severityRank(severity) > 0 ? severity : BADGE_NONE
  var none = {
    kind: "none",
    count: 0,
    countVisible: false,
    severity: BADGE_NONE,
    text: ""
  }
  if (!enabled) return none

  var state = countState || ({})
  var count = normalizeLauncherCount(state.count)
  if (normalizeLauncherBadgeMode(mode) === BADGE_COUNT_MODE_AUTOMATIC
      && state.authoritative === true && state.visible === true
      && count !== null && count > 0) {
    return {
      kind: "count",
      count: count,
      countVisible: true,
      severity: safeSeverity,
      text: count > 99 ? "99+" : String(count)
    }
  }

  if (safeSeverity !== BADGE_NONE) {
    return {
      kind: "dot",
      count: 0,
      countVisible: false,
      severity: safeSeverity,
      text: ""
    }
  }
  return none
}

function applicationBadgeToken(enabled, mode, countState, severity) {
  var presentation = applicationBadgePresentation(
    enabled, mode, countState, severity)
  if (presentation.kind === "count") {
    return "count:" + String(presentation.count) + ":" + presentation.severity
  }
  return presentation.severity
}

function shouldClearFocused(focusedSince, now, dwellMs) {
  var started = Number(focusedSince)
  var current = Number(now)
  var dwell = Number(dwellMs)
  if (!isFinite(dwell) || dwell <= 0) dwell = FOCUS_DWELL_MS
  return isFinite(started) && started > 0 && isFinite(current)
    && current - started >= dwell
}

function isPrimaryVisibleItem(items, index) {
  var values = items || []
  if (index < 0 || index >= values.length || !values[index]) return false
  var wanted = normalizeIdentity(values[index].desktopId)
  if (!wanted) return false
  for (var i = 0; i < index; ++i) {
    if (values[i] && normalizeIdentity(values[i].desktopId) === wanted)
      return false
  }
  return true
}
