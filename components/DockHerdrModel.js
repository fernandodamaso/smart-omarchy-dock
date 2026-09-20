// Pure Herdr↔window association from process identity only.
// No title, focus, or row-index heuristics.
//
// Each client resolves to its closest ancestor identity that matches a
// compositor window. If that nearest identity is shared by multiple windows,
// the client stays unmatched (no farther fallback). Independently proven
// clients aggregate; conflicting servers for one window leave it unmatched.

.pragma library

function identityKey(pid, startTime) {
  if (typeof pid !== "number" || typeof startTime !== "number") return ""
  if (!isFinite(pid) || !isFinite(startTime)) return ""
  if (pid <= 0) return ""
  return String(pid) + ":" + String(startTime)
}

function clientChain(client) {
  var chain = []
  if (!client || typeof client !== "object") return chain
  if (identityKey(client.pid, client.startTime))
    chain.push({ pid: client.pid, startTime: client.startTime, depth: 0 })
  var ancestors = client.ancestors
  if (!ancestors || typeof ancestors.length !== "number") return chain
  for (var i = 0; i < ancestors.length; i++) {
    var ancestor = ancestors[i]
    if (!ancestor || typeof ancestor !== "object") continue
    if (!identityKey(ancestor.pid, ancestor.startTime)) continue
    chain.push({
      pid: ancestor.pid,
      startTime: ancestor.startTime,
      depth: chain.length
    })
  }
  return chain
}

function associateWindows(servers, windows) {
  var byWindowKey = ({})
  var unmatched = []
  var serverList = Array.isArray(servers) ? servers : []
  var windowList = Array.isArray(windows) ? windows : []

  var windowsByIdentity = ({})
  for (var w = 0; w < windowList.length; w++) {
    var win = windowList[w]
    if (!win || typeof win !== "object") continue
    var windowKey = typeof win.key === "string" ? win.key : ""
    if (!windowKey) continue
    var wKey = identityKey(win.pid, win.startTime)
    if (!wKey) continue
    if (!windowsByIdentity[wKey]) windowsByIdentity[wKey] = []
    windowsByIdentity[wKey].push(windowKey)
  }

  // Per client: closest matching identity only; aggregate proven window→server.
  var proven = []
  for (var s = 0; s < serverList.length; s++) {
    var server = serverList[s]
    if (!server || typeof server !== "object") continue
    var serverId = typeof server.id === "string" ? server.id : ""
    if (!serverId) continue
    var clients = Array.isArray(server.clients) ? server.clients : []
    if (clients.length === 0) {
      unmatched.push(serverId)
      continue
    }
    for (var c = 0; c < clients.length; c++) {
      var chain = clientChain(clients[c])
      var matchedIdentity = ""
      for (var a = 0; a < chain.length; a++) {
        var nodeKey = identityKey(chain[a].pid, chain[a].startTime)
        if (!nodeKey || !windowsByIdentity[nodeKey]) continue
        matchedIdentity = nodeKey
        break
      }
      if (!matchedIdentity) continue
      var matches = windowsByIdentity[matchedIdentity]
      // Shared nearest identity → unmatched client; do not fall back farther.
      if (!matches || matches.length !== 1) continue
      proven.push({ windowKey: matches[0], serverId: serverId })
    }
  }

  var claimsByWindow = ({})
  for (var p = 0; p < proven.length; p++) {
    var claim = proven[p]
    var existing = claimsByWindow[claim.windowKey]
    if (!existing) {
      claimsByWindow[claim.windowKey] = {
        serverId: claim.serverId,
        ambiguous: false
      }
      continue
    }
    if (existing.serverId !== claim.serverId)
      existing.ambiguous = true
  }

  var matchedServers = ({})
  for (var windowKey in claimsByWindow) {
    if (!Object.prototype.hasOwnProperty.call(claimsByWindow, windowKey)) continue
    var choice = claimsByWindow[windowKey]
    if (choice.ambiguous) continue
    byWindowKey[windowKey] = choice.serverId
    matchedServers[choice.serverId] = true
  }

  for (var si = 0; si < serverList.length; si++) {
    var row = serverList[si]
    if (!row || typeof row !== "object") continue
    var id = typeof row.id === "string" ? row.id : ""
    if (!id) continue
    if (matchedServers[id]) continue
    if (unmatched.indexOf(id) >= 0) continue
    unmatched.push(id)
  }

  return { byWindowKey: byWindowKey, unmatchedServerIds: unmatched }
}

function normalizeWindowProcessPids(pids) {
  if (!Array.isArray(pids)) return []
  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < pids.length; i++) {
    var pid = pids[i]
    if (typeof pid !== "number" || !isFinite(pid) || Math.floor(pid) !== pid || pid <= 0)
      continue
    var key = String(pid)
    if (seen[key]) continue
    seen[key] = true
    out.push(pid)
    if (out.length >= 256) break
  }
  return out
}

function windowProcessFingerprint(targets) {
  var rows = Array.isArray(targets) ? targets.slice() : []
  rows.sort(function(a, b) {
    var ak = a && typeof a.key === "string" ? a.key : ""
    var bk = b && typeof b.key === "string" ? b.key : ""
    if (ak < bk) return -1
    if (ak > bk) return 1
    return 0
  })
  var parts = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || typeof row !== "object") continue
    var key = typeof row.key === "string" ? row.key : ""
    var pid = row.pid
    if (!key) continue
    if (typeof pid !== "number" || !isFinite(pid) || Math.floor(pid) !== pid || pid <= 0)
      continue
    parts.push(key + ":" + String(pid))
  }
  return parts.join("|")
}

function buildAssociationWindows(targets, identities) {
  var byPid = Object.create(null)
  var idList = Array.isArray(identities) ? identities : []
  for (var i = 0; i < idList.length; i++) {
    var id = idList[i]
    if (!id || typeof id !== "object") continue
    if (typeof id.pid !== "number" || typeof id.startTime !== "number") continue
    if (!isFinite(id.pid) || !isFinite(id.startTime)) continue
    if (Math.floor(id.pid) !== id.pid || id.pid <= 0) continue
    if (Math.floor(id.startTime) !== id.startTime || id.startTime < 0) continue
    byPid[String(id.pid)] = id.startTime
  }
  var windows = []
  var targetList = Array.isArray(targets) ? targets : []
  for (var t = 0; t < targetList.length; t++) {
    var target = targetList[t]
    if (!target || typeof target !== "object") continue
    var key = typeof target.key === "string" ? target.key : ""
    var pid = target.pid
    if (!key) continue
    if (typeof pid !== "number" || !isFinite(pid) || Math.floor(pid) !== pid || pid <= 0)
      continue
    if (!Object.prototype.hasOwnProperty.call(byPid, String(pid))) continue
    windows.push({ key: key, pid: pid, startTime: byPid[String(pid)] })
  }
  return windows
}

function resolveAssociations(request, snapshot) {
  if (!request || typeof request !== "object") return null
  if (!snapshot || typeof snapshot !== "object") return null
  if (typeof request.revision !== "number" || !isFinite(request.revision)) return null
  if (typeof request.epoch !== "string") return null
  if (typeof snapshot.providerEpoch !== "string") return null
  if (snapshot.providerEpoch !== request.epoch) return null
  var windowProcesses = snapshot.windowProcesses
  if (!windowProcesses || typeof windowProcesses !== "object") return null
  if (windowProcesses.revision !== request.revision) return null
  var windows = buildAssociationWindows(request.targets, windowProcesses.identities)
  return associateWindows(snapshot.servers, windows)
}

// Compact appearance: shared status normalization, unique-ID counts, color roles.
var STATUS_ORDER = ["working", "idle", "done", "blocked", "unknown"]

function normalizeStatus(value) {
  if (typeof value !== "string") return "unknown"
  var status = value.replace(/^\s+|\s+$/g, "").toLowerCase()
  if (status === "working" || status === "idle" || status === "done"
      || status === "blocked" || status === "unknown")
    return status
  return "unknown"
}

function emptyStatusCounts() {
  return {
    working: 0,
    idle: 0,
    done: 0,
    blocked: 0,
    unknown: 0,
    agents: 0
  }
}

// Count unique live agent IDs. Duplicate IDs contribute once (first wins).
function countAgentStatuses(agents) {
  var counts = emptyStatusCounts()
  var seen = Object.create(null)
  var list = Array.isArray(agents) ? agents : []
  for (var i = 0; i < list.length; i++) {
    var agent = list[i]
    if (!agent || typeof agent !== "object") continue
    var id = typeof agent.id === "string" ? agent.id : String(agent.id || "")
    if (!id || seen[id]) continue
    seen[id] = true
    var status = normalizeStatus(agent.status)
    counts[status] += 1
    counts.agents += 1
  }
  return counts
}

function statusCounters(counts) {
  var source = counts && typeof counts === "object" ? counts : emptyStatusCounts()
  var out = []
  for (var i = 0; i < STATUS_ORDER.length; i++) {
    var status = STATUS_ORDER[i]
    var count = Number(source[status] || 0)
    if (!isFinite(count) || count <= 0) continue
    out.push({ status: status, count: count })
  }
  return out
}

// One status→paint role map. QML resolves roles to Omarchy Color tokens:
// accent (working), muted (idle), done/blocked via flatColor theme fallbacks,
// hollow/muted outline (unknown). "done" is Herdr state, not proven success.
function statusColorRole(status) {
  switch (normalizeStatus(status)) {
  case "working":
    return "accent"
  case "idle":
    return "muted"
  case "done":
    return "done"
  case "blocked":
    return "blocked"
  default:
    return "hollow"
  }
}

function statusLabel(status) {
  switch (normalizeStatus(status)) {
  case "working":
    return "Working"
  case "idle":
    return "Idle"
  case "done":
    return "Done"
  case "blocked":
    return "Blocked"
  default:
    return "Unknown"
  }
}

function displayAgentKind(kind) {
  if (typeof kind !== "string") return ""
  var raw = kind.replace(/^\s+|\s+$/g, "")
  if (!raw) return ""
  var lower = raw.toLowerCase()
  if (lower === "codex") return "Codex"
  if (lower === "claude") return "Claude"
  if (lower === "cursor") return "Cursor"
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function herdrFoldKeyForWindow(windowKey) {
  if (typeof windowKey !== "string" || !windowKey) return ""
  return "herdr:" + windowKey
}
