.pragma library
.import "DockModel.js" as DockModel
.import "DockWindowModel.js" as DockWindowModel

function activationTarget(identity) {
  return DockModel.normalizeWorkspaceTarget(
    identity.indexOf("id:") === 0 ? identity.slice(3) : identity)
}

function buildWorkspacePresentation(appItems, records, workspaces, context) {
  var groups = []
  var globalLaunchers = []
  var fallbackItems = []
  var byWorkspace = Object.create(null)
  var active = context.activeWorkspace || ""
  var monitor = DockWindowModel.canonicalMonitorIdentity(context.monitor, context.monitors)
  var workspaceMonitors = Object.create(null)

  function addWorkspace(identity) {
    var target = activationTarget(identity)
    if (!target || byWorkspace[identity]) return
    var group = {
      identity: identity, label: identity.replace(/^(id:|name:)/, ""),
      activationTarget: target, active: identity === active, items: [], count: 0, urgent: false
    }
    byWorkspace[identity] = group
    groups.push(group)
  }

  for (var w = 0; w < workspaces.length; ++w) {
    var descriptor = workspaces[w]
    var ipc = descriptor.lastIpcObject || descriptor
    var owner = DockWindowModel.canonicalMonitorIdentity(
      ipc.monitorID !== undefined ? ipc.monitorID
        : ipc.monitor !== undefined ? ipc.monitor : descriptor.monitor, context.monitors)
    var identity = DockWindowModel.workspaceIdentity(descriptor)
    if (owner) workspaceMonitors[identity] = owner
    if (owner && owner === monitor) addWorkspace(identity)
  }
  addWorkspace(active)
  // Live workspace ownership wins over a saved minimized-origin connector.
  records = records.map(function(record) {
    var owner = record.minimized && workspaceMonitors[record.workspace]
      || DockWindowModel.canonicalMonitorIdentity(record.monitor, context.monitors)
    var workspace = record.sticky && !record.minimized && owner && owner === monitor
      ? active : record.minimized && record.originValid === false ? "" : record.workspace
    var resolved = Object.assign({}, record, { monitor: owner, monitorKnown: !!owner,
      workspace: workspace, workspaceKnown: workspace !== "",
      sticky: record.sticky === true && !record.minimized })
    if (resolved.minimized && owner && owner === monitor && resolved.workspaceKnown)
      addWorkspace(workspace)
    return resolved
  })
  groups.sort(function(a, b) {
    var an = a.identity.indexOf("id:") === 0
    var bn = b.identity.indexOf("id:") === 0
    if (an && bn) return Number(a.label) - Number(b.label)
    if (an !== bn) return an ? -1 : 1
    return a.identity < b.identity ? -1 : a.identity > b.identity ? 1 : 0
  })

  var pinnedIds = appItems.filter(function(item) { return item.pinned })
    .map(function(item) { return DockModel.normalizedId(item.desktopId) })
  var orderedItems = appItems.slice().sort(function(a, b) {
    var aPin = pinnedIds.indexOf(DockModel.normalizedId(a.desktopId))
    var bPin = pinnedIds.indexOf(DockModel.normalizedId(b.desktopId))
    return (aPin < 0 ? pinnedIds.length : aPin)
      - (bPin < 0 ? pinnedIds.length : bPin)
  })
  for (var i = 0; i < orderedItems.length; ++i) {
    var item = orderedItems[i]
    var partitions = Object.create(null)
    if (item.pinned && item.toplevels.length === 0)
      partitions.global = []
    for (var t = 0; t < item.toplevels.length; ++t) {
      var toplevel = item.toplevels[t]
      var record = records.find(function(value) { return value.toplevel === toplevel })
      if (record && record.monitorKnown && record.monitor !== monitor) continue
      var key = record && record.monitorKnown && record.workspaceKnown
        && byWorkspace[record.workspace] ? record.workspace : "other"
      if (!partitions[key]) partitions[key] = []
      partitions[key].push(toplevel)
    }
    for (var key in partitions) {
      var members = partitions[key]
      var identity = key + "/" + item.desktopId
      if (context.groupWindows === false && members.length) {
        var record = records.find(function(value) { return value.toplevel === members[0] })
        // Object identity remains available to preview lookup while a handle is pending.
        identity += "/" + (record && record.address || "pending")
      }
      var scoped = Object.assign({}, item, {
        pinned: pinnedIds.indexOf(DockModel.normalizedId(item.desktopId)) >= 0,
        toplevels: members, presentationId: identity,
        identityToplevel: context.groupWindows === false ? members[0] : null,
        localUrgent: false, sticky: false, urgentAddresses: []
      })
      for (var m = 0; m < members.length; ++m) {
        var member = records.find(function(value) { return value.toplevel === members[m] })
        if (!member) continue
        scoped.sticky = scoped.sticky || member.sticky === true
        if (member.urgent === true) {
          scoped.localUrgent = true
          scoped.urgentAddresses.push(member.address || "pending:" + m)
        }
      }
      if (key === "global") globalLaunchers.push(scoped)
      else if (key === "other") fallbackItems.push(scoped)
      else {
        byWorkspace[key].items.push(scoped)
        byWorkspace[key].count += members.length
        byWorkspace[key].urgent = byWorkspace[key].urgent || scoped.localUrgent
      }
    }
  }
  var renderedItems = []
  for (var g = 0; g < groups.length; ++g) {
    if (groups[g].active) renderedItems = renderedItems.concat(groups[g].items)
  }
  return { globalLaunchers: globalLaunchers, fallbackItems: fallbackItems,
    groups: groups, renderedItems: renderedItems.concat(globalLaunchers, fallbackItems) }
}

function scopedItemsEqual(a, b) {
  if (!DockModel.visibleItemsEqual(a, b)) return false
  for (var i = 0; i < a.length; ++i) {
    if (a[i].localUrgent !== b[i].localUrgent || a[i].sticky !== b[i].sticky
        || JSON.stringify(a[i].urgentAddresses) !== JSON.stringify(b[i].urgentAddresses))
      return false
  }
  return true
}

function presentationsEqual(a, b) {
  if (!scopedItemsEqual(a.globalLaunchers, b.globalLaunchers)
      || !scopedItemsEqual(a.fallbackItems, b.fallbackItems)
      || a.groups.length !== b.groups.length) return false
  for (var i = 0; i < a.groups.length; ++i) {
    var left = a.groups[i]
    var right = b.groups[i]
    if (left.identity !== right.identity || left.active !== right.active
        || left.count !== right.count || left.urgent !== right.urgent
        || !scopedItemsEqual(left.items, right.items))
      return false
  }
  return true
}
