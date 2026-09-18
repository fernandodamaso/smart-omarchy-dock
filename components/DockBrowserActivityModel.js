.pragma library

var MAX_UNREAD_COUNT = 999999
// Matches provider --classes default so Chrome identity works when the tab
// provider is unavailable or has not published classes yet.
var DEFAULT_BROWSER_CLASSES = ["google-chrome"]

function normalizeClasses(values) {
  var result = []
  var source = Array.isArray(values) ? values : []
  for (var i = 0; i < source.length; ++i) {
    if (typeof source[i] !== "string") continue
    var value = source[i].trim()
    if (value && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function effectiveBrowserClasses(classes) {
  var normalized = normalizeClasses(classes)
  return normalized.length > 0 ? normalized : DEFAULT_BROWSER_CLASSES.slice()
}

function normalizePort(value) {
  if (typeof value === "boolean" || value === "") return 0
  var port = Number(value)
  return isFinite(port) && Math.floor(port) === port && port >= 1 && port <= 65535
    ? port : 0
}

function activationCommand(providerPath, targetId, port) {
  var executable = String(providerPath || "").trim()
  var target = String(targetId || "")
  var normalizedPort = normalizePort(port)
  if (!executable || !validTargetId(target) || !normalizedPort) return []
  return [executable, "--activate-target", target, "--port", String(normalizedPort)]
}

function validTargetId(value) {
  return /^[0-9a-f]{1,64}$/i.test(String(value || ""))
}

function normalizeRow(value) {
  var source = value && typeof value === "object" ? value : null
  if (!source || !validTargetId(source.targetId)) return null
  var serviceId = String(source.serviceId || "").trim().toLowerCase()
  var label = String(source.label || "").trim()
  var count = Number(source.count)
  if (!serviceId || !label || !isFinite(count)
      || Math.floor(count) !== count
      || count <= 0 || count > MAX_UNREAD_COUNT) return null
  count = Math.floor(count)
  return {
    targetId: String(source.targetId),
    serviceId: serviceId,
    label: label,
    profileKey: String(source.profileKey || "").trim(),
    domain: String(source.domain || "").trim(),
    count: count,
    windowAddress: String(source.windowAddress || "").trim().toLowerCase()
  }
}

function presentation(values, mutedServiceIds) {
  var muted = Object.create(null)
  var mutedSource = Array.isArray(mutedServiceIds) ? mutedServiceIds : []
  for (var m = 0; m < mutedSource.length; ++m) {
    var mutedId = String(mutedSource[m] || "").trim().toLowerCase()
    if (mutedId) muted[mutedId] = true
  }
  var byOwner = Object.create(null)
  var source = Array.isArray(values) ? values : []
  for (var i = 0; i < source.length; ++i) {
    var row = normalizeRow(source[i])
    if (!row) continue
    var key = row.profileKey
      ? JSON.stringify([row.serviceId, row.profileKey])
      : JSON.stringify([row.serviceId, "", row.windowAddress])
    var current = byOwner[key]
    if (!current || row.count > current.count
        || (row.count === current.count && row.targetId < current.targetId))
      byOwner[key] = row
  }
  var rows = Object.keys(byOwner).map(function(key) {
    var value = byOwner[key]
    return Object.assign({}, value, { muted: muted[value.serviceId] === true })
  })
  rows.sort(function(a, b) {
    return b.count - a.count || a.label.localeCompare(b.label)
      || a.targetId.localeCompare(b.targetId)
  })
  var total = 0
  for (var n = 0; n < rows.length; ++n) {
    if (!rows[n].muted) total += rows[n].count
  }
  return { rows: rows, total: total }
}

function rowsForAddresses(recordsByAddress, addresses) {
  var records = recordsByAddress && typeof recordsByAddress === "object"
    ? recordsByAddress : ({})
  var wanted = Array.isArray(addresses) ? addresses : []
  var normalizedRecords = Object.create(null)
  Object.keys(records).forEach(function(key) {
    normalizedRecords[String(key).trim().toLowerCase()] = records[key]
  })
  var rows = []
  for (var i = 0; i < wanted.length; ++i) {
    var address = String(wanted[i] || "").trim().toLowerCase()
    var values = Array.isArray(normalizedRecords[address])
      ? normalizedRecords[address] : []
    for (var n = 0; n < values.length; ++n)
      rows.push(Object.assign({}, values[n], { windowAddress: address }))
  }
  return presentation(rows).rows
}

// Exact tab → activity match against RAW per-address records (no service/profile
// dedup). Do not use rowsForAddresses / presentation winners to find a tab.
function activityForTarget(recordsByAddress, targetId, windowAddress) {
  var wantedTarget = String(targetId || "")
  var address = String(windowAddress || "").trim().toLowerCase()
  if (!validTargetId(wantedTarget) || !address) return null
  var records = recordsByAddress && typeof recordsByAddress === "object"
    ? recordsByAddress : ({})
  var values = null
  var keys = Object.keys(records)
  for (var i = 0; i < keys.length; ++i) {
    if (String(keys[i]).trim().toLowerCase() === address) {
      values = records[keys[i]]
      break
    }
  }
  if (!Array.isArray(values)) return null
  for (var n = 0; n < values.length; ++n) {
    var row = normalizeRow(Object.assign({}, values[n], { windowAddress: address }))
    if (row && row.targetId === wantedTarget) return row
  }
  return null
}

function rawRowsForAddresses(recordsByAddress, addresses) {
  var records = recordsByAddress && typeof recordsByAddress === "object"
    ? recordsByAddress : ({})
  var wanted = Array.isArray(addresses) ? addresses : []
  var normalizedRecords = Object.create(null)
  Object.keys(records).forEach(function(key) {
    normalizedRecords[String(key).trim().toLowerCase()] = records[key]
  })
  var rows = []
  for (var i = 0; i < wanted.length; ++i) {
    var address = String(wanted[i] || "").trim().toLowerCase()
    var values = Array.isArray(normalizedRecords[address])
      ? normalizedRecords[address] : []
    for (var n = 0; n < values.length; ++n)
      rows.push(Object.assign({}, values[n], { windowAddress: address }))
  }
  return rows
}

function accessibleName(row) {
  var value = normalizeRow(row)
  return value ? "Open " + value.label + " tab, " + value.count + " unread" : ""
}

var MAX_TABS_PER_WINDOW = 50
var MAX_TAB_TITLE = 120

function normalizeTabRow(value) {
  var source = value && typeof value === "object" ? value : null
  if (!source || !validTargetId(source.targetId)) return null
  var title = String(source.title || "").trim() || "Tab"
  if (title.length > MAX_TAB_TITLE)
    title = title.slice(0, MAX_TAB_TITLE - 1) + "…"
  var faviconPath = String(source.faviconPath || "").trim()
  // Local cache path only; never accept remote favicon URLs into the model.
  if (!faviconPath || faviconPath[0] !== "/" || faviconPath.indexOf("..") >= 0
      || /[\x00-\x1f\x7f]/.test(faviconPath)
      || !/\/smartdock\/tab-favicons\//.test(faviconPath))
    faviconPath = ""
  return {
    targetId: String(source.targetId),
    title: title,
    active: source.active === true,
    windowAddress: String(source.windowAddress || "").trim().toLowerCase(),
    faviconPath: faviconPath
  }
}

function presentationTabs(values) {
  var source = Array.isArray(values) ? values : []
  var rows = []
  var seen = Object.create(null)
  for (var i = 0; i < source.length; ++i) {
    var row = normalizeTabRow(source[i])
    if (!row || seen[row.targetId]) continue
    seen[row.targetId] = true
    rows.push(row)
  }
  // Keep provider/CDP order; do not promote active or sort by title.
  return rows.slice(0, MAX_TABS_PER_WINDOW)
}

function tabsForAddresses(recordsByAddress, addresses) {
  var records = recordsByAddress && typeof recordsByAddress === "object"
    ? recordsByAddress : ({})
  var wanted = Array.isArray(addresses) ? addresses : []
  var normalizedRecords = Object.create(null)
  Object.keys(records).forEach(function(key) {
    normalizedRecords[String(key).trim().toLowerCase()] = records[key]
  })
  var rows = []
  for (var i = 0; i < wanted.length; ++i) {
    var address = String(wanted[i] || "").trim().toLowerCase()
    var values = Array.isArray(normalizedRecords[address])
      ? normalizedRecords[address] : []
    for (var n = 0; n < values.length; ++n)
      rows.push(Object.assign({}, values[n], { windowAddress: address }))
  }
  return presentationTabs(rows)
}

function accessibleTabName(row) {
  var value = normalizeTabRow(row)
  if (!value) return ""
  return (value.active ? "Active tab: " : "Open tab: ") + value.title
}
