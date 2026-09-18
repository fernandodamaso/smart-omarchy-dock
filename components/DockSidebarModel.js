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

// Topology miniatures: physical x/y only (empty monitorOrder). Card/projection
// order may still follow settings.workspaceMonitorOrder. Focus joins by
// connector or monitorIdentity from projection.monitorSections.
function physicalMonitorStrip(screens, monitors, focusSections) {
  var focusByKey = Object.create(null)
  ;(focusSections || []).forEach(function(section) {
    if (!section) return
    var focused = section.focused === true
    if (section.connector)
      focusByKey["c:" + String(section.connector)] = focused
    if (section.monitorIdentity)
      focusByKey["i:" + String(section.monitorIdentity)] = focused
  })
  return monitorMetadata(screens, monitors, []).map(function(meta) {
    var focused = focusByKey["c:" + String(meta.connector || "")] === true
      || focusByKey["i:" + String(meta.identity || "")] === true
    return {
      connector: meta.connector,
      identity: meta.identity,
      focused: focused
    }
  })
}

function compactMonitorRailLabel(connector, sectionIndex) {
  var value = String(connector || "").trim()
  if (!value) return String(Number(sectionIndex || 0) + 1)
  if (/^Virtual-/i.test(value))
    return "V" + value.replace(/^Virtual-/i, "").replace(/-/g, "")
  // DP-1 → DP1, HDMI-A-1 → HA1 — short, distinguishable tokens.
  var parts = value.split("-").filter(Boolean)
  if (parts.length >= 2 && /\d/.test(parts[parts.length - 1])) {
    var head = parts[0].slice(0, 2)
    if (parts.length > 2) head += parts[1][0]
    return (head + parts[parts.length - 1]).slice(0, 4)
  }
  var compact = value.replace(/-/g, "")
  return compact.length <= 4 ? compact : compact.slice(0, 4)
}

// Empty preferred (or a disconnected preference) → every connected screen
// (mirrored hierarchy). Connected preference → that connector only. While busy,
// keep the previous mapping when it is still connected (defer adopting a new
// preferred or newly attached outputs); drop outputs that disappeared.
function selectScreens(screens, monitors, order, preferred, previousMapped, busy) {
  var connected = screens || []
  if (!connected.length) return []
  var pref = String(preferred || "")
  var hit = pref ? connected.find(function(screen) { return screen.name === pref }) : null
  var previous = []
  var seenPrevious = Object.create(null)
  ;(previousMapped || []).forEach(function(screen) {
    if (!screen || seenPrevious[screen.name]) return
    var live = connected.find(function(entry) { return entry.name === screen.name })
    if (!live) return
    seenPrevious[live.name] = true
    previous.push(live)
  })

  function allScreens() {
    var ordered = monitorMetadata(connected, monitors, order)
    var next = []
    var seen = Object.create(null)
    ordered.forEach(function(meta) {
      if (!meta.screen || seen[meta.screen.name]) return
      seen[meta.screen.name] = true
      next.push(meta.screen)
    })
    connected.forEach(function(screen) {
      if (!screen || seen[screen.name]) return
      seen[screen.name] = true
      next.push(screen)
    })
    return next
  }

  if (hit) {
    if (!busy || !previous.length) return [hit]
    return previous
  }

  var next = allScreens()
  if (!busy || !previous.length) return next
  var available = Object.create(null)
  next.forEach(function(screen) { available[screen.name] = screen })
  var retained = []
  previous.forEach(function(screen) {
    if (available[screen.name]) retained.push(available[screen.name])
  })
  return retained.length ? retained : next
}

// Primary screen for dockMonitor / CLI back-compat: first mapped output.
function selectScreen(screens, monitors, order, preferred, current, busy) {
  var previous = current
    ? [(screens || []).find(function(screen) { return screen && screen.name === current })].filter(Boolean)
    : []
  var mapped = selectScreens(screens, monitors, order, preferred, previous, busy)
  if (!mapped.length) return null
  if (current) {
    var retained = mapped.find(function(screen) { return screen.name === current })
    if (retained) return retained
  }
  return mapped[0]
}

function logicalScreenWidth(screen) {
  if (!screen) return 0
  var width = Number(screen.width)
  return isFinite(width) ? Math.max(0, width) : 0
}

function geometry(screenWidth, requestedWidth, collapsed) {
  var width = Math.max(0, Number(screenWidth) || 0)
  if (!isFinite(width)) width = 0
  // Preferred collapsed rail is 72; clamp to tiny screens. Expanded bounds use
  // the same floor so the rail never exceeds the expanded maximum envelope.
  var preferredRail = 72
  var railWidth = Math.min(preferredRail, width)
  var maximum = Math.min(width, Math.max(preferredRail, Math.min(480, Math.floor(0.40 * width))))
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

// Session-memory scroll key: one entry per panel connector × expanded|rail.
// Not persisted to filesystem/config.
function scrollMemoryKey(panelConnector, collapsed) {
  return JSON.stringify([String(panelConnector || ""), collapsed ? "rail" : "expanded"])
}

function emptyScrollState() {
  return { anchor: { key: "", offset: 0 }, keys: [] }
}

function readScrollState(states, panelConnector, collapsed) {
  var entry = states && states[scrollMemoryKey(panelConnector, collapsed)]
  if (!entry || typeof entry !== "object") return emptyScrollState()
  var anchor = entry.anchor || {}
  return {
    anchor: { key: String(anchor.key || ""), offset: Number(anchor.offset) || 0 },
    keys: Array.isArray(entry.keys) ? entry.keys.slice() : []
  }
}

function writeScrollState(states, panelConnector, collapsed, anchor, keys) {
  var next = Object.assign({}, states || {})
  next[scrollMemoryKey(panelConnector, collapsed)] = {
    anchor: {
      key: String(anchor && anchor.key || ""),
      offset: Number(anchor && anchor.offset) || 0
    },
    keys: Array.isArray(keys) ? keys.slice() : []
  }
  return next
}

function emptyProjection() {
  return {
    monitorSections: [], launchers: [], unassignedWindows: [], rows: [], badgeItems: [],
    sectionSpans: []
  }
}

// Annotate the final visible row list (after fold/collapse filtering) with tree
// guide metadata and sectionSpans. Sibling order is visible order only.
// sectionSpans endPadding is logical px before Style.space; inter-section gaps
// (monitor 8 / workspace 4) are NOT inside the span — they live on the next
// row's layoutGapBefore and are excluded from span geometry.
function annotateTreeAndSpans(result) {
  var rows = result.rows || []
  result.sectionSpans = []
  var rowByKey = Object.create(null)
  var monitorKey = ""
  var workspaceKey = ""
  var applicationKey = ""
  var sectionKey = ""
  var workspaceChildSeen = Object.create(null)
  var monitorWorkspaceSeen = Object.create(null)
  var i

  for (i = 0; i < rows.length; ++i) {
    var row = rows[i]
    rowByKey[row.key] = row
    row.layoutGapBefore = ""
    row.layoutPadWorkspaceEnd = false
    row.layoutPadMonitorEnd = false
    row.ancestorContinues = []
    row.isLastSibling = true
    row.monitorKey = ""
    row.workspaceKey = ""
    row.parentKey = ""
    row.treeDepth = 0

    if (row.kind === "monitor") {
      monitorKey = row.key
      workspaceKey = ""
      applicationKey = ""
      sectionKey = ""
      row.monitorKey = row.key
      if (Number(row.sectionIndex || 0) > 0) row.layoutGapBefore = "monitor"
      continue
    }
    if (row.kind === "section") {
      monitorKey = ""
      workspaceKey = ""
      applicationKey = ""
      sectionKey = row.key
      continue
    }
    if (row.kind === "workspace") {
      applicationKey = ""
      workspaceKey = row.key
      row.monitorKey = monitorKey
      row.workspaceKey = row.key
      row.parentKey = monitorKey
      row.treeDepth = 0
      if (monitorKey && monitorWorkspaceSeen[monitorKey]) row.layoutGapBefore = "workspace"
      if (monitorKey) monitorWorkspaceSeen[monitorKey] = true
      continue
    }
    if (row.kind === "application") {
      applicationKey = row.key
      row.monitorKey = monitorKey
      row.workspaceKey = workspaceKey
      row.parentKey = workspaceKey
      row.treeDepth = 1
      if (workspaceKey && !workspaceChildSeen[workspaceKey]) {
        row.layoutGapBefore = "children"
        workspaceChildSeen[workspaceKey] = true
      }
      continue
    }
    if (row.kind === "window") {
      row.monitorKey = monitorKey
      row.workspaceKey = workspaceKey
      if (row.nested === true && applicationKey) {
        row.parentKey = applicationKey
        row.treeDepth = 2
      } else if (sectionKey && !workspaceKey) {
        row.parentKey = sectionKey
        row.treeDepth = 1
        applicationKey = ""
      } else {
        // Sole window or rail: direct child of the workspace.
        row.parentKey = workspaceKey
        row.treeDepth = 1
        applicationKey = ""
      }
      if (row.treeDepth === 1 && workspaceKey && !workspaceChildSeen[workspaceKey]) {
        row.layoutGapBefore = "children"
        workspaceChildSeen[workspaceKey] = true
      }
      continue
    }
    if (row.kind === "browser-tab") {
      var windowParent = rowByKey[row.windowKey] || null
      row.monitorKey = monitorKey
      row.workspaceKey = workspaceKey
      row.parentKey = row.windowKey || ""
      row.treeDepth = windowParent ? Number(windowParent.treeDepth || 0) + 1 : 2
    }
  }

  var childrenOf = Object.create(null)
  for (i = 0; i < rows.length; ++i) {
    var child = rows[i]
    var parent = child.parentKey || ""
    if (!childrenOf[parent]) childrenOf[parent] = []
    childrenOf[parent].push(child)
  }
  for (i = 0; i < rows.length; ++i) {
    var node = rows[i]
    var siblings = childrenOf[node.parentKey || ""] || [node]
    node.isLastSibling = siblings[siblings.length - 1] === node
  }
  for (i = 0; i < rows.length; ++i) {
    var guide = rows[i]
    var continues = []
    var walk = rowByKey[guide.parentKey]
    var chain = []
    while (walk && Number(walk.treeDepth || 0) >= 1) {
      chain.push(walk)
      walk = rowByKey[walk.parentKey]
    }
    for (var c = chain.length - 1; c >= 0; --c)
      continues.push(chain[c].isLastSibling !== true)
    guide.ancestorContinues = continues
  }

  i = 0
  while (i < rows.length) {
    if (rows[i].kind === "monitor") {
      var mon = rows[i]
      var monStart = i
      var monLast = i
      i += 1
      while (i < rows.length && rows[i].kind !== "monitor" && rows[i].kind !== "section") {
        monLast = i
        i += 1
      }
      result.sectionSpans.push({
        kind: "monitor", key: mon.key, firstKey: mon.key, lastKey: rows[monLast].key,
        focused: mon.focused === true, endPadding: 5
      })
      rows[monLast].layoutPadMonitorEnd = true
      for (var j = monStart; j <= monLast; ++j) {
        if (rows[j].kind !== "workspace") continue
        var wsLast = j
        for (var k = j + 1; k <= monLast; ++k) {
          if (rows[k].kind === "workspace") break
          wsLast = k
        }
        result.sectionSpans.push({
          kind: "workspace", key: rows[j].key, firstKey: rows[j].key,
          lastKey: rows[wsLast].key, focused: rows[j].active === true, endPadding: 5
        })
        rows[wsLast].layoutPadWorkspaceEnd = true
      }
      continue
    }
    // Unassigned keeps the existing section row; do not invent a monitor span.
    if (rows[i].kind === "section") {
      i += 1
      while (i < rows.length && rows[i].kind !== "monitor" && rows[i].kind !== "section") i += 1
      continue
    }
    i += 1
  }
}

// Production rowsByKey index: hierarchy rows plus strip-owned pin launchers.
// Optional rail projection unions rows hidden by expanded folds; expanded wins duplicates.
function indexRowsByKey(expanded, optionalRail) {
  var result = Object.create(null)
  function absorb(source) {
    var projection = source || emptyProjection()
    ;(projection.rows || []).forEach(function(row) {
      if (!result[row.key]) result[row.key] = row
    })
    ;(projection.launchers || []).forEach(function(row) {
      if (!result[row.key]) result[row.key] = row
    })
  }
  absorb(expanded)
  if (optionalRail) absorb(optionalRail)
  return result
}

// Expanded-first row list for shared scroll/focus recovery across both modes.
function unionProjectionRows(expanded, rail) {
  var result = []
  var seen = Object.create(null)
  function pushAll(source) {
    ;(source && source.rows || []).forEach(function(row) {
      if (seen[row.key]) return
      seen[row.key] = true
      result.push(row)
    })
  }
  pushAll(expanded)
  pushAll(rail)
  return result
}

// Map a remembered focus key onto rows visible in the active projection.
function remapFocusKey(key, visibleRows, rowsByKey) {
  var rows = visibleRows || []
  if (!key) return ""
  if (rows.some(function(row) { return row.key === key })) return key
  var row = rowsByKey && rowsByKey[key]
  if (!row) return recoverAnchor({ key: key, offset: 0 }, [], rows).key
  if (row.kind === "browser-tab") {
    var windowKey = row.windowKey || ""
    if (windowKey && rows.some(function(candidate) { return candidate.key === windowKey }))
      return windowKey
  }
  if (row.kind === "application") {
    var windows = row.windows || []
    for (var i = 0; i < windows.length; ++i) {
      var child = windows[i]
      if (child && child.key && rows.some(function(candidate) { return candidate.key === child.key }))
        return child.key
    }
  }
  if (row.kind === "window" && row.applicationKey) {
    if (rows.some(function(candidate) { return candidate.key === row.applicationKey }))
      return row.applicationKey
  }
  return recoverAnchor({ key: key, offset: 0 }, [], rows).key
}

function project(input) {
  var native = input.desktop.workspacePresentation
  var result = emptyProjection()
  var records = input.desktop.records
  var folds = input.folds || ({})
  var browserTabsEnabled = input.sidebarBrowserTabsEnabled !== false
  var browserTabs = browserTabsEnabled && input.browserTabs
    && typeof input.browserTabs === "object" && !Array.isArray(input.browserTabs)
    ? input.browserTabs : ({})
  function tabsForWindow(window) {
    var address = String(window.address || "").trim().toLowerCase()
    if (!address || !browserTabsEnabled) return []
    var values = browserTabs[address]
    if (!Array.isArray(values) || !values.length) {
      // Address casing in snapshot keys may differ from Hyprland.
      var keys = Object.keys(browserTabs)
      for (var i = 0; i < keys.length; ++i) {
        if (String(keys[i]).trim().toLowerCase() === address) {
          values = browserTabs[keys[i]]
          break
        }
      }
    }
    if (!Array.isArray(values) || !values.length) return []
    return values.map(function(tab) {
      return {
        targetId: String(tab.targetId || ""),
        title: String(tab.title || "").trim() || "Tab",
        active: tab.active === true,
        windowAddress: address,
        faviconPath: String(tab.faviconPath || "").trim()
      }
    }).filter(function(tab) { return !!tab.targetId })
  }
  function attachTabs(window) {
    var tabs = tabsForWindow(window)
    var tabsKey = "tabs:" + window.key
    window.tabs = tabs
    window.tabsKey = tabsKey
    window.tabsExpandable = tabs.length > 0
    // Missing fold key => folded (default). folds[tabsKey] === true => expanded.
    window.tabsFolded = !window.tabsExpandable || folds[tabsKey] !== true
    return window
  }
  function emitWindow(window) {
    attachTabs(window)
    row(window)
    if (input.collapsed || !window.tabsExpandable || window.tabsFolded) return
    window.tabs.forEach(function(tab) {
      row({
        kind: "browser-tab",
        key: JSON.stringify(["browser-tab", window.key, tab.targetId]),
        targetId: tab.targetId,
        title: tab.title,
        active: tab.active === true,
        faviconPath: tab.faviconPath || "",
        windowAddress: tab.windowAddress,
        windowKey: window.key,
        toplevel: window.toplevel,
        address: window.address,
        desktopId: window.desktopId,
        workspaceIdentity: window.workspaceIdentity,
        monitorIdentity: window.monitorIdentity,
        nested: true,
        parentWindow: window
      })
    })
  }
  var pins = (input.pinned || []).map(DockModel.normalizedId)
  var sections = Object.create(null)
  var windowsByHandleKey = Object.create(null)
  var appsByKey = Object.create(null)
  var seen = Object.create(null)
  var rowByKey = Object.create(null)
  var metadata = monitorMetadata(input.screens, input.monitors, input.monitorOrder)
  var labelCounts = Object.create(null)
  metadata.forEach(function(meta) {
    var source = native.monitorGroups.find(function(m) { return m.identity === meta.identity })
    var base = source ? source.label : meta.label
    labelCounts[String(base || "")] = (labelCounts[String(base || "")] || 0) + 1
  })
  metadata.forEach(function(meta) {
    var source = native.monitorGroups.find(function(m) { return m.identity === meta.identity })
    var base = source ? source.label : meta.label
    // Prefer a short display name; keep connector for the second line / rail.
    // Always attach connector when it differs so first paint never grows the
    // shared prefix on a translucent layershell ("ASUS" → "ASUS · DP-1").
    var displayLabel = base
    var monitorTitle = base
    if (meta.connector && String(meta.connector) !== String(base || "")) {
      displayLabel = (base ? base + " · " : "") + meta.connector
      monitorTitle = base || meta.connector
    } else if ((labelCounts[String(base || "")] || 0) > 1 && meta.connector) {
      displayLabel = base + " · " + meta.connector
      monitorTitle = base
    }
    var section = { key: JSON.stringify(["monitor", meta.identity]), monitorIdentity: meta.identity,
      connector: meta.connector, label: displayLabel, title: monitorTitle,
      focused: source ? source.focused : false, workspaces: [] }
    sections[meta.identity] = section
    result.monitorSections.push(section)
  })
  function unknownSection() {
    if (!sections.unknown) {
      sections.unknown = { key: JSON.stringify(["monitor", ""]), monitorIdentity: "", connector: "",
        label: "Unknown monitor", title: "Unknown monitor", focused: false, workspaces: [] }
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
            urgent: false, primaryOwner: false, expandable: false, windowCount: 0 }
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
    workspace.applications.forEach(function(app) {
      app.windows.sort(function(a, b) { return a.order - b.order })
      app.windowCount = app.windows.length
      app.expandable = app.windowCount > 1
      // Single-window apps stay foldable in session state but are not shown as
      // a duplicate header; only multi-window groups earn an expandable row.
      if (!app.expandable) app.folded = false
    })
    section.workspaces.push(workspace)
  })
  native.fallbackItems.forEach(function(item) {
    item.toplevels.forEach(function(toplevel) {
      var window = member(item, toplevel, "", "")
      if (window) result.unassignedWindows.push(window)
    })
  })
  result.unassignedWindows.sort(function(a, b) { return a.order - b.order })
  // Pin shelf follows settings.pinned order and includes running apps (focus-or-launch).
  // Strip owns these rows; they never appear in the hierarchy ListView (expanded or rail).
  var windowsByDesktop = Object.create(null)
  Object.keys(windowsByHandleKey).forEach(function(key) {
    var window = windowsByHandleKey[key]
    var desk = DockModel.normalizedId(window.desktopId)
    if (!desk) return
    if (!windowsByDesktop[desk]) windowsByDesktop[desk] = []
    windowsByDesktop[desk].push(window)
  })
  var itemsByDesktop = Object.create(null)
  function rememberItem(item) {
    var id = DockModel.normalizedId(item && item.desktopId)
    if (id && !itemsByDesktop[id]) itemsByDesktop[id] = item
  }
  ;(native.renderedItems || []).forEach(rememberItem)
  ;(native.globalLaunchers || []).forEach(rememberItem)
  ;(native.fallbackItems || []).forEach(rememberItem)
  var hidden = (input.hiddenApplications || []).map(DockModel.normalizedId)
  var launchersByKey = Object.create(null)
  pins.forEach(function(id) {
    if (!id || hidden.indexOf(id) >= 0) return
    var item = itemsByDesktop[id] || null
    var wins = windowsByDesktop[id] || []
    if (!wins.length) {
      // Catalog pins may use a desktop-id spelling while live windows still carry
      // the compositor appId; attach by either identity so focus-or-launch works.
      Object.keys(windowsByHandleKey).forEach(function(key) {
        var window = windowsByHandleKey[key]
        var desk = DockModel.normalizedId(window.desktopId)
        var appId = DockModel.normalizedId(window.toplevel && window.toplevel.appId)
        if (desk === id || appId === id) {
          if (wins.indexOf(window) < 0) wins.push(window)
        }
      })
    }
    var label = item && item.entry && item.entry.name ? item.entry.name : id
    var launcher = {
      kind: "launcher",
      key: JSON.stringify(["launcher", id]),
      desktopId: item && item.desktopId ? item.desktopId : id,
      label: label,
      item: item || ({ desktopId: id, entry: null, toplevels: wins.map(function(w) { return w.toplevel }) }),
      windows: wins,
      running: wins.length > 0,
      members: wins.map(function(w) { return w.toplevel }),
      primaryOwner: false,
      urgent: wins.some(function(w) { return w.urgent === true })
    }
    result.launchers.push(launcher)
    launchersByKey[launcher.key] = launcher
  })
  function row(value) {
    if (rowByKey[value.key]) throw new Error("Duplicate sidebar row key: " + value.key)
    rowByKey[value.key] = value
    result.rows.push(value)
  }
  result.monitorSections.forEach(function(section, sectionIndex) {
    row({ kind: "monitor", key: section.key, label: section.label, title: section.title || section.label,
      connector: section.connector, monitorIdentity: section.monitorIdentity, focused: section.focused,
      target: section, sectionIndex: sectionIndex })
    section.workspaces.sort(WorkspaceModel.workspaceCompare)
    section.workspaces.forEach(function(workspace) {
      row({ kind: "workspace", key: workspace.key, label: workspace.label, workspaceIdentity: workspace.identity,
        monitorIdentity: workspace.owner, active: workspace.active, urgent: workspace.urgent, target: workspace })
      workspace.applications.forEach(function(app) {
        if (app.expandable) {
          if (!input.collapsed) row(app)
          if (input.collapsed || !app.folded) {
            app.windows.forEach(function(window) {
              window.nested = !input.collapsed
              emitWindow(window)
            })
          }
        } else {
          app.windows.forEach(function(window) {
            window.nested = false
            window.soleWindow = true
            emitWindow(window)
          })
        }
      })
    })
  })
  if (result.unassignedWindows.length) {
    row({ kind: "section", key: "section:unassigned", label: "Unassigned windows" })
    result.unassignedWindows.forEach(function(window) { emitWindow(window) })
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
    } else owner = launchersByKey[JSON.stringify(["launcher", identity])] || null
    if (owner && (rowByKey[owner.key] || launchersByKey[owner.key])) {
      owner.primaryOwner = true
      owned[identity] = true
    }
  })
  function pushBadge(value) {
    if (!value || !value.item) return
    var urgentAddresses = []
    var members = value.windows || (value.kind === "window" ? [value] : [])
    members.forEach(function(window) {
      if (window.urgent && window.address) urgentAddresses.push(window.address)
    })
    result.badgeItems.push({ presentationId: value.key, desktopId: value.desktopId,
      localUrgent: value.urgent === true, urgentAddresses: urgentAddresses })
  }
  result.rows.forEach(pushBadge)
  result.launchers.forEach(pushBadge)
  annotateTreeAndSpans(result)
  return result
}
