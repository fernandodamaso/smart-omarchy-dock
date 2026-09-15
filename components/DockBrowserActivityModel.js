.pragma library

var MAX_UNREAD_COUNT = 999999

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

function accessibleName(row) {
  var value = normalizeRow(row)
  return value ? "Open " + value.label + " tab, " + value.count + " unread" : ""
}
