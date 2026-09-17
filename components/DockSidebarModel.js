.pragma library
.import "DockModel.js" as DockModel
.import "DockWindowModel.js" as WindowModel
.import "DockWorkspaceModel.js" as WorkspaceModel

// Pure, host-session identity. Never identify a window by title, index or address.
function reconcileHandles(previous, toplevels) {
  var state = previous || { nextToken: 1, entries: [] }
  var next = { nextToken: state.nextToken, entries: [] }
  ;(toplevels || []).forEach(function(toplevel) {
    if (!toplevel || next.entries.some(function(e) { return e.toplevel === toplevel })) return
    var entry = handleEntry(state, toplevel)
    if (!entry) {
      var token = next.nextToken++
      entry = { toplevel: toplevel, key: "window:" + token, order: token }
    }
    next.entries.push(entry)
  })
  return next
}

function handleEntry(registry, toplevel) {
  return (registry.entries || []).find(function(entry) { return entry.toplevel === toplevel }) || null
}

function monitorMetadata(screens, monitors, order) {
  return (screens || []).map(function(screen) {
    var descriptor = WindowModel.monitorForScreen(screen, monitors || [])
    var ipc = descriptor ? descriptor.lastIpcObject || descriptor : ({})
    var identity = descriptor ? WindowModel.canonicalMonitorIdentity(descriptor, monitors) : "name:" + screen.name
    return {
      screen: screen, identity: identity, connector: screen.name,
      label: WorkspaceModel.monitorLabel(identity, screen.name, descriptor, ipc),
      x: WorkspaceModel.finiteCoordinate(ipc.x, screen.x),
      y: WorkspaceModel.finiteCoordinate(ipc.y, screen.y)
    }
  }).sort(function(a, b) {
    return WorkspaceModel.monitorMetadataCompare(a, b, DockModel.normalizeMonitorConnectors(order))
  })
}

function selectScreen(screens, monitors, order, preferred, current, busy) {
  var connected = screens || []
  var retained = connected.find(function(screen) { return screen.name === current })
  var requested = connected.find(function(screen) { return screen.name === preferred })
  if (requested && (!busy || !retained)) return requested
  if (retained) return retained
  var ordered = monitorMetadata(connected, monitors, order)
  return ordered.length ? ordered[0].screen : null
}

function logicalScreenWidth(screen) {
  if (!screen) return 0
  var width = Number(screen.width)
  return isFinite(width) ? Math.max(0, width) : 0
}

function geometry(screenWidth, requestedWidth, collapsed) {
  var width = Math.max(0, Number(screenWidth) || 0)
  if (!isFinite(width)) width = 0
  var railWidth = Math.min(56, width)
  var maximum = Math.min(width, Math.max(56, Math.min(480, Math.floor(0.40 * width))))
  var minimum = Math.min(240, maximum)
  var requested = DockModel.normalizeSetting("sidebarExpandedWidth", requestedWidth)
  var expanded = Math.min(maximum, Math.max(minimum, requested))
  return { mapped: width > 0, width: collapsed ? railWidth : expanded,
    expandedWidth: expanded, minimum: minimum, maximum: maximum, railWidth: railWidth,
    screenWidth: width }
}

// Qt/Quickshell screen dimensions are already logical. Never divide by scale or
// use available/workarea width here: that can include this panel's own exclusive
// zone and create a shrinking feedback loop.
function screenGeometry(screen, requestedWidth, collapsed) {
  return geometry(logicalScreenWidth(screen), requestedWidth, collapsed)
}

// Resize from one captured pointer origin. The caller supplies screen-global
// logical coordinates, so a moving right-anchored panel origin cannot accumulate
// as extra pointer motion.
function resizeWidth(startWidth, startGlobalX, currentGlobalX, edge, screenWidth) {
  var width = Math.max(0, Number(screenWidth) || 0)
  var bounds = geometry(width, startWidth, false)
  if (!bounds.mapped) return 0
  var start = Number(startGlobalX)
  var current = Number(currentGlobalX)
  var delta = isFinite(start) && isFinite(current) ? current - start : 0
  var candidate = Number(startWidth)
  if (!isFinite(candidate)) candidate = bounds.expandedWidth
  candidate += edge === "right" ? -delta : delta
  candidate = Math.round(candidate)
  return Math.min(bounds.maximum, Math.max(bounds.minimum, candidate))
}

function recoverAnchor(anchor, oldKeys, rows) {
  var current = anchor || { key: "", offset: 0 }
  var keys = (rows || []).map(function(row) { return row.key })
  if (!keys.length) return { key: "", offset: 0 }
  if (keys.indexOf(current.key) >= 0) return { key: current.key, offset: current.offset || 0 }
  var previous = oldKeys || []
  var index = previous.indexOf(current.key)
  for (var distance = 1; index >= 0 && distance <= previous.length; ++distance) {
    if (keys.indexOf(previous[index + distance]) >= 0)
      return { key: previous[index + distance], offset: current.offset || 0 }
    if (keys.indexOf(previous[index - distance]) >= 0)
      return { key: previous[index - distance], offset: current.offset || 0 }
  }
  return { key: keys[0], offset: 0 }
}

function emptyProjection() {
  return { monitorSections: [], launchers: [], unassignedWindows: [], rows: [], badgeItems: [] }
}

function project(input) {
  var native = input.desktop.workspacePresentation
  var result = emptyProjection()
  var records = input.desktop.records
  var folds = input.folds || ({})
  var pins = (input.pinned || []).map(DockModel.normalizedId)
  var sections = Object.create(null)
  var windowsByHandleKey = Object.create(null)
  var appsByKey = Object.create(null)
  var seen = Object.create(null)
  var rowByKey = Object.create(null)
  var metadata = monitorMetadata(input.screens, input.monitors, input.monitorOrder)
  metadata.forEach(function(meta) {
    var source = native.monitorGroups.find(function(m) { return m.identity === meta.identity })
    var section = { key: JSON.stringify(["monitor", meta.identity]), monitorIdentity: meta.identity,
      connector: meta.connector, label: source ? source.label : meta.label,
      focused: source ? source.focused : false, workspaces: [] }
    sections[meta.identity] = section
    result.monitorSections.push(section)
  })
  function unknownSection() {
    if (!sections.unknown) {
      sections.unknown = { key: JSON.stringify(["monitor", ""]), monitorIdentity: "", connector: "",
        label: "Unknown monitor", focused: false, workspaces: [] }
      result.monitorSections.push(sections.unknown)
    }
    return sections.unknown
  }
  function applicationIdentity(item, toplevel, entry) {
    var id = DockModel.normalizedId(item.desktopId)
    // DockModel's fallback label is not evidence of a common application.
    return !id || (!String(toplevel.appId || "").trim() && id === "unknown-application") ? entry.key : id
  }
  function member(item, toplevel, workspace, owner) {
    var entry = handleEntry(input.registry, toplevel)
    if (!entry || seen[entry.key]) return null
    seen[entry.key] = true
    var record = records.find(function(r) { return r.toplevel === toplevel }) || ({})
    var appIdentity = applicationIdentity(item, toplevel, entry)
    var appKey = JSON.stringify(["app", workspace, appIdentity])
    var window = { kind: "window", key: entry.key, order: entry.order, toplevel: toplevel,
      address: record.address || "", title: String(toplevel.title || ""),
      workspaceIdentity: workspace, monitorIdentity: owner, applicationKey: appKey,
      desktopId: item.desktopId, item: item, minimized: record.minimized === true,
      sticky: record.sticky === true && !record.minimized, urgent: record.urgent === true,
      primaryOwner: false, members: [toplevel] }
    windowsByHandleKey[entry.key] = window
    return window
  }
  native.groups.forEach(function(group) {
    var section = sections[group.monitorIdentity] || unknownSection()
    var workspace = { key: JSON.stringify(["workspace", group.identity]), identity: group.identity,
      owner: section.monitorIdentity, label: group.label, active: group.active, urgent: group.urgent,
      applications: [] }
    var localApps = Object.create(null)
    group.items.forEach(function(item) {
      item.toplevels.forEach(function(toplevel) {
        var window = member(item, toplevel, group.identity, workspace.owner)
        if (!window) return
        var app = localApps[window.applicationKey]
        if (!app) {
          app = { kind: "application", key: window.applicationKey, desktopId: item.desktopId,
            label: item.entry && item.entry.name ? item.entry.name : item.desktopId,
            workspaceIdentity: group.identity, monitorIdentity: workspace.owner, item: item,
            folded: folds[window.applicationKey] === true, windows: [], members: [],
            urgent: false, primaryOwner: false }
          localApps[app.key] = app
          appsByKey[app.key] = app
          workspace.applications.push(app)
        }
        app.windows.push(window)
        app.members.push(toplevel)
        app.urgent = app.urgent || window.urgent
      })
    })
    workspace.applications.sort(function(a, b) {
      var left = pins.indexOf(DockModel.normalizedId(a.desktopId))
      var right = pins.indexOf(DockModel.normalizedId(b.desktopId))
      if (left >= 0 || right >= 0) {
        if (left < 0) return 1
        if (right < 0) return -1
        if (left !== right) return left - right
      }
      return WorkspaceModel.lexicalCompare(DockModel.normalizedId(a.desktopId), DockModel.normalizedId(b.desktopId))
        || a.windows[0].order - b.windows[0].order
    })
    workspace.applications.forEach(function(app) { app.windows.sort(function(a, b) { return a.order - b.order }) })
    section.workspaces.push(workspace)
  })
  native.fallbackItems.forEach(function(item) {
    item.toplevels.forEach(function(toplevel) {
      var window = member(item, toplevel, "", "")
      if (window) result.unassignedWindows.push(window)
    })
  })
  result.unassignedWindows.sort(function(a, b) { return a.order - b.order })
  var launcherIds = Object.create(null)
  native.globalLaunchers.forEach(function(item) {
    var identity = DockModel.normalizedId(item.desktopId)
    if (launcherIds[identity]) return
    launcherIds[identity] = true
    result.launchers.push({ kind: "launcher", key: JSON.stringify(["launcher", identity]),
      desktopId: item.desktopId, label: item.entry && item.entry.name ? item.entry.name : item.desktopId,
      item: item, members: [], primaryOwner: false, urgent: false })
  })
  function row(value) {
    if (rowByKey[value.key]) throw new Error("Duplicate sidebar row key: " + value.key)
    rowByKey[value.key] = value
    result.rows.push(value)
  }
  result.monitorSections.forEach(function(section) {
    row({ kind: "monitor", key: section.key, label: section.label, connector: section.connector,
      monitorIdentity: section.monitorIdentity, focused: section.focused, target: section })
    section.workspaces.sort(WorkspaceModel.workspaceCompare)
    section.workspaces.forEach(function(workspace) {
      row({ kind: "workspace", key: workspace.key, label: workspace.label, workspaceIdentity: workspace.identity,
        monitorIdentity: workspace.owner, active: workspace.active, urgent: workspace.urgent, target: workspace })
      workspace.applications.forEach(function(app) {
        if (!input.collapsed) row(app)
        if (input.collapsed || !app.folded) app.windows.forEach(row)
      })
    })
  })
  if (result.launchers.length) {
    row({ kind: "section", key: "section:pinned", label: "Pinned" })
    result.launchers.forEach(row)
  }
  if (result.unassignedWindows.length) {
    row({ kind: "section", key: "section:unassigned", label: "Unassigned windows" })
    result.unassignedWindows.forEach(row)
  }
  // Native traversal chooses the app-wide owner, never visual monitor order.
  var owned = Object.create(null)
  native.renderedItems.forEach(function(item) {
    var identity = DockModel.normalizedId(item.desktopId)
    if (!identity || owned[identity]) return
    var owner = null
    if (item.toplevels.length) {
      // Within the eligible workspace use stable first-seen order, not focus/source order.
      var candidates = item.toplevels.map(function(t) { return handleEntry(input.registry, t) })
        .filter(function(entry) { return entry && windowsByHandleKey[entry.key] })
      if (candidates.length) {
        var window = windowsByHandleKey[candidates[0].key]
        var app = appsByKey[window.applicationKey]
        if (app) window = app.windows[0]
        owner = !input.collapsed && app && app.folded ? app : window
      }
    } else owner = rowByKey[JSON.stringify(["launcher", identity])]
    if (owner && rowByKey[owner.key]) {
      owner.primaryOwner = true
      owned[identity] = true
    }
  })
  result.rows.forEach(function(value) {
    if (!value.item) return
    var urgentAddresses = []
    var members = value.windows || (value.kind === "window" ? [value] : [])
    members.forEach(function(window) {
      if (window.urgent && window.address) urgentAddresses.push(window.address)
    })
    result.badgeItems.push({ presentationId: value.key, desktopId: value.desktopId,
      localUrgent: value.urgent === true, urgentAddresses: urgentAddresses })
  })
  return result
}
