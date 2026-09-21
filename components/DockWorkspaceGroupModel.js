.pragma library
.import "DockModel.js" as DockModel

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function applicationKey(value) {
  if (typeof value !== "string" || /[\x00-\x1f\x7f/\\]/.test(value)) return ""
  var trimmed = value.trim()
  if (!trimmed) return ""
  var key = DockModel.normalizedId(trimmed)
  if (!key || key === "unknown-application" || key === "__proto__"
      || key === "prototype" || key === "constructor") return ""
  return key
}

function persistedApplicationId(value) {
  if (typeof value !== "string" || value !== value.trim()
      || /\.desktop$/i.test(value)) return ""
  return applicationKey(value) ? value : ""
}

function canonicalWorkspaceTarget(value) {
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || value <= 0) return ""
    return "id:" + value
  }
  if (typeof value !== "string") return ""
  var raw = value.trim()
  if (!raw || /[\x00-\x1f\x7f;,]/.test(raw)
      || raw.indexOf("special:") === 0) return ""
  if (/^[1-9][0-9]*$/.test(raw)) {
    var numeric = Number(raw)
    return Number.isSafeInteger(numeric) ? "id:" + numeric : ""
  }
  var idMatch = /^id:([1-9][0-9]*)$/.exec(raw)
  if (idMatch) {
    var id = Number(idMatch[1])
    if (!Number.isSafeInteger(id) || String(id) !== idMatch[1]) return ""
    return "id:" + id
  }
  if (raw.indexOf("name:") === 0) {
    var name = raw.slice(5)
    if (!name || name !== name.trim()) return ""
    return "name:" + name
  }
  return ""
}

function persistedWorkspaceTarget(value) {
  if (typeof value !== "string" || value !== value.trim()) return ""
  var canonical = canonicalWorkspaceTarget(value)
  return canonical && canonical === value ? canonical : ""
}

function workspaceGroupsError(value) {
  if (!Array.isArray(value)) return "Expected an array of workspace group pairs"
  var seen = Object.create(null)
  for (var i = 0; i < value.length; ++i) {
    var entry = value[i]
    if (!entry || typeof entry !== "object" || Array.isArray(entry))
      return "Expected a workspace group object at index " + i
    var keys = Object.keys(entry).sort()
    if (keys.length !== 2 || keys[0] !== "desktopId" || keys[1] !== "workspace")
      return "Workspace group entries require only desktopId and workspace at index " + i
    var desktopId = persistedApplicationId(entry.desktopId)
    if (!desktopId) return "Invalid canonical desktopId at index " + i
    var workspace = persistedWorkspaceTarget(entry.workspace)
    if (!workspace) return "Invalid canonical workspace identity at index " + i
    var pair = applicationKey(desktopId) + "\u001f" + workspace
    if (own(seen, pair)) return "Duplicate application/workspace pair at index " + i
    seen[pair] = true
  }
  return ""
}

function normalizeWorkspaceGroups(value) {
  if (workspaceGroupsError(value)) return []
  return value.map(function(entry) {
    return { desktopId: entry.desktopId, workspace: entry.workspace }
  })
}

function workspaceGroupEnabled(groups, desktopId, workspace) {
  var key = applicationKey(desktopId)
  var target = canonicalWorkspaceTarget(workspace)
  if (!key || !target || workspaceGroupsError(groups)) return false
  for (var i = 0; i < groups.length; ++i) {
    if (applicationKey(groups[i].desktopId) === key
        && groups[i].workspace === target) return true
  }
  return false
}

function legacyGroupingActive(value) {
  return false
}

function recordFor(records, toplevel) {
  for (var i = 0; i < (records || []).length; ++i)
    if (records[i] && records[i].toplevel === toplevel) return records[i]
  return null
}

function recordWorkspace(record) {
  if (!record || record.workspaceKnown !== true) return ""
  return canonicalWorkspaceTarget(record.workspace)
}

function cloneItem(item, members) {
  var result = Object.assign({}, item)
  result.toplevels = (members || []).slice()
  return result
}

function windowRuleDiscriminator(item) {
  var key = String(item && item.windowRuleKey || "")
  return key ? "rule:" + key : "unmatched"
}

function groupedPresentationId(item, workspace) {
  return workspace + "/" + item.desktopId + "/window-rule:" + windowRuleDiscriminator(item)
}

function individualPresentationId(item, record, ordinal) {
  var workspace = recordWorkspace(record) || "other"
  var address = record && typeof record.address === "string"
    ? DockModel.normalizeWindowAddress(record.address) : ""
  return workspace + "/" + item.desktopId + "/" + (address || "pending:" + ordinal)
}

// Start from DockModel's individual-window output. Only exact configured
// app/workspace pairs are recombined; unknown/special membership stays individual.
function localizeItems(appItems, records, groups) {
  var policy = workspaceGroupsError(groups) ? [] : groups
  var result = []
  var buckets = Object.create(null)
  var ordinal = 0
  for (var i = 0; i < (appItems || []).length; ++i) {
    var item = appItems[i]
    var members = item && Array.isArray(item.toplevels) ? item.toplevels : []
    if (members.length === 0) {
      var launcher = cloneItem(item, [])
      launcher.workspaceGrouped = false
      launcher.localWorkspaceIdentity = ""
      launcher.presentationId = "global/" + item.desktopId
      launcher.identityToplevel = null
      result.push(launcher)
      continue
    }
    for (var m = 0; m < members.length; ++m) {
      var toplevel = members[m]
      var record = recordFor(records, toplevel)
      var workspace = recordWorkspace(record)
      if (workspace && workspaceGroupEnabled(policy, item.desktopId, workspace)) {
        var groupKey = applicationKey(item.desktopId) + "\u001f" + workspace
          + "\u001f" + windowRuleDiscriminator(item)
        var bucket = buckets[groupKey]
        if (!bucket) {
          bucket = cloneItem(item, [])
          bucket.workspaceGrouped = true
          bucket.localWorkspaceIdentity = workspace
          bucket.presentationId = groupedPresentationId(item, workspace)
          bucket.identityToplevel = null
          buckets[groupKey] = bucket
          result.push(bucket)
        } else if (item.pinned) {
          bucket.pinned = true
          if (item.originalIndex < bucket.originalIndex) bucket.originalIndex = item.originalIndex
        }
        bucket.toplevels.push(toplevel)
      } else {
        var individual = cloneItem(item, [toplevel])
        individual.workspaceGrouped = false
        individual.localWorkspaceIdentity = workspace
        individual.presentationId = individualPresentationId(item, record, ordinal++)
        individual.identityToplevel = toplevel
        result.push(individual)
      }
    }
  }
  return result
}

function workspaceSortKey(item) {
  var workspace = String(item.localWorkspaceIdentity || "")
  var match = /^id:([1-9][0-9]*)$/.exec(workspace)
  return match ? { known: true, numeric: Number(match[1]), text: "" }
    : workspace ? { known: true, numeric: Number.MAX_SAFE_INTEGER, text: workspace }
    : { known: false, numeric: Number.MAX_SAFE_INTEGER, text: "" }
}

function buildFlatPresentation(appItems, records, groups, sortByWorkspace) {
  var localized = localizeItems(appItems, records, groups)
  if (!sortByWorkspace) return localized
  return localized.slice().sort(function(a, b) {
    var aClosed = a.pinned && a.toplevels.length === 0
    var bClosed = b.pinned && b.toplevels.length === 0
    if (aClosed !== bClosed) return aClosed ? -1 : 1
    var aw = workspaceSortKey(a)
    var bw = workspaceSortKey(b)
    if (aw.known !== bw.known) return aw.known ? -1 : 1
    if (aw.numeric !== bw.numeric) return aw.numeric - bw.numeric
    if (aw.text !== bw.text) return aw.text < bw.text ? -1 : 1
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    return Number(a.originalIndex || 0) - Number(b.originalIndex || 0)
  })
}

function prepareWorkspaceItems(appItems, records, groups) {
  return localizeItems(appItems, records, groups)
}

function decorateScopedItem(item, workspaceIdentity, groups) {
  if (!item) return item
  var grouped = item.workspaceGrouped === true
    && item.localWorkspaceIdentity === workspaceIdentity
    && workspaceGroupEnabled(groups, item.desktopId, workspaceIdentity)
  if (grouped) {
    item.presentationId = groupedPresentationId(item, workspaceIdentity)
    item.identityToplevel = null
  }
  return item
}

// DockWorkspaceModel remains responsible for monitor/workspace ownership. This
// final pass restores group identity after that proven partitioner runs in
// individual mode, so configured pairs keep exact represented member lists.
function decorateWorkspacePresentation(presentation, groups) {
  var result = presentation || ({ groups: [], fallbackItems: [], globalLaunchers: [] })
  for (var g = 0; g < (result.groups || []).length; ++g) {
    var group = result.groups[g]
    for (var i = 0; i < (group.items || []).length; ++i)
      decorateScopedItem(group.items[i], group.identity, groups)
  }
  // Fallback membership is intentionally never promoted to a saved group.
  return result
}
