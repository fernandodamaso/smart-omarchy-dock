.pragma library
.import "DockModel.js" as DockModel
.import "DockSidebarModel.js" as SidebarModel

// Pure per-screen presentation resolution shared by the host renderer owners,
// the sidebar controller and CLI diagnostics. Only settings and connected
// screens enter this file: dry-run and readback paths resolve without any
// renderer instance, so host rendering and CLI readback cannot drift.
//
// Per connector the effective mode is presentationModeByMonitor[connector]
// when present, otherwise the inherited presentationMode. Classic always maps
// a surface. Sidebar maps when the explicit "sidebar" override says so, or
// when the connector is part of the legacy sidebarMonitor/workspaceMonitorOrder
// selection — so an empty override map reproduces legacy behavior exactly.
function resolve(input) {
  var value = input || ({})
  var screens = value.screens || []
  var monitors = value.monitors || []
  var defaultMode = DockModel.normalizeSetting("presentationMode", value.presentationMode)
  var overrides = DockModel.normalizeSetting(
    "presentationModeByMonitor", value.presentationModeByMonitor)
  var order = DockModel.normalizeSetting("workspaceMonitorOrder", value.workspaceMonitorOrder)
  var legacySidebarScreens = SidebarModel.selectScreens(screens, monitors, order,
    DockModel.normalizeSetting("sidebarMonitor", value.sidebarMonitor),
    value.previousSidebarScreens || [], value.busy === true)
  var legacySelected = Object.create(null)
  legacySidebarScreens.forEach(function(screen) {
    if (screen && screen.name) legacySelected[screen.name] = true
  })

  var ordered = SidebarModel.monitorMetadata(screens, monitors, order).map(function(meta) {
    return meta.screen
  })
  var seen = Object.create(null)
  var entries = []
  ordered.forEach(function(screen) {
    if (!screen || !screen.name || seen[screen.name]) return
    seen[screen.name] = true
    var connector = screen.name
    var hasOverride = Object.prototype.hasOwnProperty.call(overrides, connector)
    var mode = hasOverride ? overrides[connector] : defaultMode
    var sidebarSelected = legacySelected[connector] === true
    entries.push({
      connector: connector,
      screen: screen,
      mode: mode,
      source: hasOverride ? "override" : "inherited",
      mapped: mode === "classic" ? true : (hasOverride || sidebarSelected),
      sidebarSelected: sidebarSelected
    })
  })

  var sidebarScreens = []
  var classicScreens = []
  var modeByMonitor = ({})
  var sourceByMonitor = ({})
  var mappedByMonitor = ({})
  entries.forEach(function(entry) {
    modeByMonitor[entry.connector] = entry.mode
    sourceByMonitor[entry.connector] = entry.source
    mappedByMonitor[entry.connector] = entry.mapped
    if (entry.mode === "classic") classicScreens.push(entry.screen)
    else if (entry.mapped) sidebarScreens.push(entry.screen)
  })

  return {
    defaultMode: defaultMode,
    overrides: overrides,
    entries: entries,
    screens: entries,
    modeByMonitor: modeByMonitor,
    sourceByMonitor: sourceByMonitor,
    mappedByMonitor: mappedByMonitor,
    sidebarScreens: sidebarScreens,
    classicScreens: classicScreens,
    legacySidebarScreens: legacySidebarScreens,
    mixed: classicScreens.length > 0 && sidebarScreens.length > 0
  }
}

function entryFor(presentation, connector) {
  var name = String(connector || "")
  if (!name) return null
  var entries = (presentation && presentation.entries) || []
  for (var i = 0; i < entries.length; ++i)
    if (entries[i].connector === name) return entries[i]
  return null
}

// Flatten the live sidebar panel lists owned by each per-screen surface owner.
// Owners without a sidebar surface (classic, unmapped) contribute nothing, so a
// local change on one screen never manufactures panels for another.
function aggregateSidebarPanels(owners) {
  var panels = []
  ;(owners || []).forEach(function(owner) {
    if (!owner) return
    var source = owner.panels !== undefined && owner.panels !== null
      ? owner.panels
      : (owner.surface ? owner.surface.panels : null)
    if (!source || typeof source.length !== "number") return
    for (var i = 0; i < source.length; ++i) panels.push(source[i])
  })
  return panels
}

// A mode-switch gesture captures this token at press time. The host re-checks
// it at release so a gesture started before a settings/topology change commits
// nothing, and a stale gesture can never write another monitor's override.
function modeGestureToken(presentation, connector) {
  var entry = entryFor(presentation, connector)
  if (!entry) return null
  return {
    connector: entry.connector,
    mode: entry.mode,
    source: entry.source,
    hasOverride: entry.source === "override",
    overrideValue: entry.source === "override" ? entry.mode : null,
    inheritedMode: presentation ? presentation.defaultMode : entry.mode
  }
}

function modeGestureTokenCurrent(token, presentation, connector) {
  if (!token || !presentation) return false
  var entry = entryFor(presentation, connector || token.connector)
  if (!entry) return false
  if (token.connector !== entry.connector) return false
  if (token.mode !== entry.mode) return false
  if (token.hasOverride !== (entry.source === "override")) return false
  if (token.hasOverride && token.overrideValue !== entry.mode) return false
  if (token.inheritedMode !== presentation.defaultMode) return false
  return true
}
