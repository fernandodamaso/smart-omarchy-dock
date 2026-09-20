.pragma library
.import "DockHerdrModel.js" as HerdrModel

// Geometry is supplied by the actual clipped ListView delegates. Indices are
// never action identities, and offscreen/utility/footer rectangles are not hits.
function contains(rect, point) {
  return !!rect && !!point && isFinite(point.x) && isFinite(point.y)
    && rect.width > 0 && rect.height > 0
    && point.x >= rect.x && point.x < rect.x + rect.width
    && point.y >= rect.y && point.y < rect.y + rect.height
}

// Intersect a painted monitor-card rect with the visible hierarchy viewport.
// Gaps, footer/header, and fully offscreen cards yield null.
function clipRect(rect, viewport) {
  if (!rect || !viewport) return null
  if (!(rect.width > 0) || !(rect.height > 0)) return null
  if (!(viewport.width > 0) || !(viewport.height > 0)) return null
  var x1 = Math.max(Number(rect.x), Number(viewport.x))
  var y1 = Math.max(Number(rect.y), Number(viewport.y))
  var x2 = Math.min(Number(rect.x) + Number(rect.width),
    Number(viewport.x) + Number(viewport.width))
  var y2 = Math.min(Number(rect.y) + Number(rect.height),
    Number(viewport.y) + Number(viewport.height))
  if (!(x2 > x1) || !(y2 > y1)) return null
  if (!isFinite(x1) || !isFinite(y1) || !isFinite(x2) || !isFinite(y2)) return null
  return { x: x1, y: y1, width: x2 - x1, height: y2 - y1 }
}

function hitTarget(point, hits, viewport, sourceKind) {
  if (!contains(viewport, point)) return ""
  for (var i = 0; i < (hits || []).length; ++i) {
    var hit = hits[i]
    if (!contains(hit, point)) continue
    if (sourceKind === "workspace")
      return hit.kind === "monitor" && hit.monitorIdentity ? hit.key : ""
    return ["workspace", "application", "window"].indexOf(hit.kind) >= 0
      && hit.workspaceIdentity ? hit.key : ""
  }
  return ""
}

function autoScrollStep(y, height) {
  if (!isFinite(y) || height <= 0 || y < 0 || y >= height) return 0
  var band = Math.min(32, height / 3)
  if (y < band) return -Math.ceil(12 * (1 - y / band))
  if (y > height - band) return Math.ceil(12 * (1 - (height - y) / band))
  return 0
}

// Drag-ghost offset: the pointer-anchored proxy (+12 cursor offset applied by
// the caller) follows the cursor across the panel. Clamp by the leading
// visible extent — the 22px artwork for horizontal travel — not the full
// proxy width, which otherwise pins the ghost near the left edge.
function dragProxyOffset(pointer, viewportExtent, visibleExtent) {
  var p = Number(pointer)
  if (!isFinite(p)) return 0
  var view = Number(viewportExtent)
  if (!isFinite(view) || view <= 0) return 0
  var keep = Number(visibleExtent)
  if (!isFinite(keep) || keep < 0) keep = 0
  return Math.max(0, Math.min(Math.max(0, view - keep), p))
}

function focusable(row) {
  return !!row && ["workspace", "application", "window", "launcher", "browser-tab"].indexOf(row.kind) >= 0
}

function nextKey(rows, key, direction) {
  var keys = (rows || []).filter(focusable).map(function(row) { return row.key })
  if (!keys.length) return ""
  if (direction === "home") return keys[0]
  if (direction === "end") return keys[keys.length - 1]
  var index = keys.indexOf(key)
  if (index < 0) return direction < 0 ? keys[keys.length - 1] : keys[0]
  return keys[Math.max(0, Math.min(keys.length - 1, index + (direction < 0 ? -1 : 1)))]
}

// Canonical workspace badge label. Prefer the shared model display label when
// present (id:10 named Work → "Work"); otherwise id:3→3, name:Work→Work.
// Explicit prefixes only — never first-digits regex or slice(0, 2).
function workspaceBadgeLabel(identity, displayLabel) {
  var label = String(displayLabel || "").trim()
  if (label) return label
  var raw = String(identity || "")
  if (raw.indexOf("id:") === 0) return raw.slice(3)
  if (raw.indexOf("name:") === 0) return raw.slice(5)
  return raw
}

// Collapsed rail keeps a compact token: full numerics preserved, other labels
// abbreviated to two Unicode code points without splitting surrogate pairs.
// Original case preserved; no ellipsis. Expanded labels/tooltips keep full name.
function compactWorkspaceBadgeLabel(fullLabel) {
  var label = String(fullLabel || "").trim()
  if (/^[0-9]+$/.test(label)) return label
  return Array.from(label).slice(0, 2).join("")
}

// Index of the currently focused physical monitor in topology-strip order
// (physical x/y via physicalMonitorStrip). Same on every header — not sectionIndex.
function focusedMonitorStripIndex(strip) {
  var list = strip || []
  for (var i = 0; i < list.length; ++i) {
    if (list[i] && list[i].focused === true) return i
  }
  return -1
}

// Shared >4 fallback: focused physical ordinal N/M (identical on every header).
function focusedMonitorStripOrdinal(strip) {
  var list = strip || []
  var count = list.length
  if (!(count > 0)) return ""
  var index = focusedMonitorStripIndex(list)
  if (index < 0) return ""
  return (index + 1) + "/" + count
}

// Topology miniature strip width for label-elide estimates (13×9, gap 3).
function topologyStripWidth(count) {
  var n = Number(count) || 0
  if (!(n > 0)) return 0
  if (n > 4) return 24
  return n * 13 + Math.max(0, n - 1) * 3
}

// Tree guide columns relative to workspace card left (viewport.workspaceCardInset).
// Badge at left+8, min-24 center at left+20 = guide0; depth-1 icon at guide0+12;
// each deeper depth +24.
function sidebarTreeGuideLayout(workspaceCardInset) {
  var left = Number(workspaceCardInset)
  if (!isFinite(left)) left = 0
  return {
    workspaceLeft: left,
    badgeLeft: left + 8,
    guide0: left + 20,
    depthStep: 24,
    iconOffset: 12
  }
}

function sidebarTreeStemX(workspaceCardInset, depth) {
  var layout = sidebarTreeGuideLayout(workspaceCardInset)
  var d = Number(depth)
  if (!isFinite(d) || d < 1) return layout.guide0
  return layout.guide0 + (d - 1) * layout.depthStep
}

function sidebarTreeIconX(workspaceCardInset, treeDepth) {
  var layout = sidebarTreeGuideLayout(workspaceCardInset)
  var d = Math.max(1, Number(treeDepth) || 1)
  return layout.guide0 + layout.iconOffset + (d - 1) * layout.depthStep
}

// Horizontal insets for fillLayer / focus rail. Expanded window/application/
// browser-tab / herdr child rows start 3 logical px before artX so parent tree
// guides stay visible; workspace headers keep the whole-card inset; collapsed
// rail keeps centered/compact card geometry. Right edge always matches card inset.
function sidebarSelectionInsets(input) {
  var o = input || {}
  var inset = Number(o.workspaceCardInset)
  if (!isFinite(inset)) inset = 0
  var card = o.insideWorkspaceCard === true
  var right = card ? inset : 0
  var left = right
  if (o.collapsed === true)
    return { left: left, right: right }
  if (o.kind === "workspace")
    return { left: inset, right: right }
  if (o.kind === "window" || o.kind === "application" || o.kind === "browser-tab"
      || o.kind === "herdr-agent" || o.kind === "herdr-state") {
    var artX = Number(o.artX)
    if (!isFinite(artX)) artX = inset
    return { left: artX - 3, right: right }
  }
  return { left: left, right: right }
}

// Pure fill priority used by DockSidebarRow.rowFill. Transient drop/press/hover
// compose over persistent selection/context instead of early-returning past them.
function composeRowFill(state) {
  var s = state || {}
  if (s.dropTarget) return s.dropFill
  if (s.pressed) return s.pressedFill
  if (s.activeFocus && !s.persistentSelected) return s.focusFill
  if (s.hovered && s.navigable) {
    if (s.persistentSelected) return s.selectedHoverFill
    if (s.persistentContext) return s.contextHoverFill
    return s.hoverFill
  }
  return s.persistentFill
}

// Numeric attention tokens are `count:<n>[:severity]` (see DockApplicationBadge).
function isNumericBadgeToken(severity) {
  var parts = String(severity || "").split(":")
  return parts.length >= 2 && parts[0] === "count"
    && isFinite(Number(parts[1])) && Number(parts[1]) > 0
}

// Rail-only: taller window/app row when attentionForRow.countVisible is true.
// Accepts a boolean countVisible (preferred) or a legacy badge token string.
function sidebarRowHasNumericAlert(collapsed, countVisibleOrToken) {
  if (collapsed !== true) return false
  if (countVisibleOrToken === true) return true
  if (countVisibleOrToken === false || countVisibleOrToken === undefined
      || countVisibleOrToken === null) return false
  return isNumericBadgeToken(countVisibleOrToken)
}

// Persistent window-name attention motion: expanded WINDOW rows only, using
// the already-aggregated included numeric attention count (mute eye zeros it).
function attentionNameMotionEligible(kind, collapsed, countVisible, count,
    animationsEnabled, rowDragActive) {
  return kind === "window"
    && collapsed !== true
    && countVisible === true
    && Number(count) > 0
    && animationsEnabled !== false
    && rowDragActive !== true
}

// Shared row geometry for delegates and ListView estimators.
// sidebarRowMetrics(row, collapsed, rowHeight, space, hasAlert=false)
// → { contentHeight, gapBefore, gapAfter, height, contentY }
//
// Baselines (logical, then Style.space): monitor 48 expanded / 32 rail;
// workspace 30 both; app/window/tab 28 expanded; rail window 36 or 58 when
// hasAlert; section 22. Font floor = max(0, rowHeight - space(12)). Default
// viewport rowHeight≈34 → floor 22, so expanded 28 is NOT forced back to 34.
//
// Gap tokens from annotateTreeAndSpans: layoutGapBefore "monitor"|8,
// "workspace"|4, "children"|4 (or numeric). End padding via
// layoutPadWorkspaceEnd / layoutPadMonitorEnd (+5 each) or numeric
// layoutGapAfter. Inter-section gaps stay on the following row and are
// excluded from sectionSpans ranges (spans carry endPadding only).
function layoutGapBeforeUnits(row) {
  if (!row) return 0
  var token = row.layoutGapBefore
  if (token === "monitor") return 8
  if (token === "workspace" || token === "children") return 4
  if (token !== undefined && token !== null && token !== "") {
    var numbered = Number(token)
    if (isFinite(numbered)) return numbered
  }
  if (row.kind === "monitor" && Number(row.sectionIndex || 0) > 0) return 8
  return 0
}

function layoutGapAfterUnits(row) {
  if (!row) return 0
  if (row.layoutGapAfter !== undefined && row.layoutGapAfter !== null && row.layoutGapAfter !== "") {
    var numbered = Number(row.layoutGapAfter)
    if (isFinite(numbered)) return numbered
  }
  var pad = 0
  if (row.layoutPadWorkspaceEnd === true) pad += 5
  if (row.layoutPadMonitorEnd === true) pad += 5
  return pad
}

function sidebarRowMetrics(row, collapsed, rowHeight, space, hasAlert) {
  var sp = typeof space === "function" ? space : function(n) { return n }
  var fontFloor = Math.max(0, (Number(rowHeight) || 0) - sp(12))
  var alert = hasAlert === true
  var kind = row && row.kind
  var baseline = sp(28)
  if (!row) {
    baseline = sp(28)
  } else if (collapsed) {
    if (kind === "monitor") baseline = sp(32)
    else if (kind === "workspace") baseline = sp(30)
    else if (kind === "section") baseline = sp(22)
    else if (kind === "browser-tab" || kind === "herdr-agent"
        || kind === "herdr-state") baseline = sp(28)
    else baseline = alert ? sp(58) : sp(36)
  } else if (kind === "monitor") {
    baseline = sp(48)
  } else if (kind === "section") {
    baseline = sp(22)
  } else if (kind === "workspace") {
    baseline = sp(30)
  } else {
    baseline = sp(28)
  }
  var contentHeight = Math.max(baseline, fontFloor)
  var gapBefore = sp(layoutGapBeforeUnits(row))
  var gapAfter = sp(layoutGapAfterUnits(row))
  return {
    contentHeight: contentHeight,
    gapBefore: gapBefore,
    gapAfter: gapAfter,
    height: gapBefore + contentHeight + gapAfter,
    contentY: gapBefore
  }
}

function estimatedSidebarRowHeight(row, collapsed, rowHeight, space, hasAlert) {
  return sidebarRowMetrics(row, collapsed, rowHeight, space, hasAlert).height
}

// Drag-only monitor-footer drop targets for window-to-new-workspace drops.
// Footers are view-layer trailing space on each monitor's final visible row,
// never synthetic workspace rows, so row keys and delegates stay stable.
function newWorkspaceFooterTargetHeight(collapsed) {
  return collapsed === true ? 36 : 32
}

function newWorkspaceFooterExtra(collapsed, space) {
  var sp = typeof space === "function" ? space : function(n) { return n }
  return newWorkspaceFooterTargetHeight(collapsed) + sp(5)
}

function newWorkspaceFooterKey(monitorIdentity) {
  return JSON.stringify(["new-workspace", String(monitorIdentity || "")])
}

function parseNewWorkspaceFooterKey(key) {
  try {
    var parsed = JSON.parse(key)
    if (Array.isArray(parsed) && parsed.length === 2
        && parsed[0] === "new-workspace"
        && typeof parsed[1] === "string" && parsed[1] !== "")
      return parsed[1]
  } catch (error) {}
  return ""
}

function isNewWorkspaceFooterKey(key) {
  return parseNewWorkspaceFooterKey(key) !== ""
}

function isMonitorFinalKey(key, sectionSpans) {
  var spans = sectionSpans || []
  for (var i = 0; i < spans.length; ++i) {
    var span = spans[i]
    if (span && span.kind === "monitor" && span.lastKey === key) return true
  }
  return false
}

function heightMapChanged(previousMap, nextMap) {
  return String(previousMap || "") !== String(nextMap || "")
}

function shouldRestoreScroll(previous, next) {
  var prev = previous || {}
  var cur = next || {}
  if (JSON.stringify(prev.keys || []) !== JSON.stringify(cur.keys || [])) return true
  if (prev.rowHeight !== cur.rowHeight) return true
  if (prev.collapsed !== cur.collapsed) return true
  if (Math.round(prev.contentHeight || 0) !== Math.round(cur.contentHeight || 0)) return true
  return heightMapChanged(prev.heightMap, cur.heightMap)
}

// Classic top/bottom clamps x into the panel window. Side left/right only clamp
// y so a 380px picker can sit beside a ~280px sidebar instead of collapsing to x=8.
function clampPopupAnchor(position, point, windowSize, popupSize) {
  var next = { x: Number(point && point.x) || 0, y: Number(point && point.y) || 0 }
  var win = windowSize || {}
  var pop = popupSize || {}
  var winW = Number(win.width) || 0
  var winH = Number(win.height) || 0
  var popW = Number(pop.width) || 0
  var popH = Number(pop.height) || 0
  if (position === "top" || position === "bottom")
    next.x = Math.max(8, Math.min(next.x, winW - popW - 8))
  else
    next.y = Math.max(8, Math.min(next.y, winH - popH - 8))
  return next
}

// ListView inline anchors dismiss on leave/destroy; footer anchors may reanchor.
function pickerAnchorDecision(anchor, options) {
  var opts = options || {}
  if (!anchor) return { action: "dismiss", reason: "missing" }
  if (opts.footer === true) {
    if (opts.visible === false) return { action: "dismiss", reason: "footer-hidden" }
    return { action: "reanchor", reason: "footer" }
  }
  if (opts.visible === false || !(opts.width > 0))
    return { action: "dismiss", reason: "destroyed" }
  var y = Number(opts.y)
  var height = Number(opts.height) || 0
  var viewportHeight = Number(opts.viewportHeight) || 0
  if (!isFinite(y) || y + height <= 0 || y >= viewportHeight)
    return { action: "dismiss", reason: "scrolled-out" }
  return { action: "reanchor", reason: "in-view" }
}

// Pin-shelf icons are shortcuts: never attach live window members. Hierarchy
// window/app rows keep their represented toplevels for the full app menu.
function contextMenuMembers(target, anchor) {
  if (anchor && anchor.pinStripOwned === true) return []
  if (!target) return []
  if (target.kind === "window")
    return target.toplevel ? [target.toplevel] : []
  return Array.isArray(target.members) ? target.members.slice() : []
}

// Browser window parents show the desktop-entry application name; selected-tab
// titles stay on browser-tab children and in the parent tooltip only.
// Associated Herdr parents show "Herdr"; the original window title stays in the
// tooltip. Agent activation is wired in a later task.
function sidebarWindowDisplayTitle(input) {
  var source = input || ({})
  var kind = String(source.kind || "")
  if (kind === "browser-tab")
    return String(source.tabTitle || "").trim() || "Tab"
  if (kind === "herdr-agent" || kind === "herdr-state")
    return String(source.title || "").trim() || (kind === "herdr-state" ? "Herdr" : "Coding agent")
  var windowTitle = String(source.windowTitle || "").trim() || "Untitled window"
  if (kind === "window" && source.isHerdr === true)
    return "Herdr"
  if (kind === "window" && source.isBrowser === true) {
    var entryName = String(source.entryName || "").trim()
    if (entryName) return entryName
  }
  if (kind === "window") return windowTitle
  return String(source.label || "")
}

function sidebarWindowTooltipTitle(input) {
  var source = input || ({})
  var display = String(source.displayTitle || "").trim()
  var windowTitle = String(source.windowTitle || "").trim()
  if (source.kind === "window" && (source.isBrowser === true || source.isHerdr === true)
      && display && windowTitle && display !== windowTitle)
    return display + " · " + windowTitle
  return display || windowTitle
}

// Familiar agent-kind capitalization for compact rows (Codex / Claude / Cursor).
function herdrAgentKindLabel(input) {
  var source = input || ({})
  var kind = source.agentKind !== undefined ? source.agentKind : source.kind
  return HerdrModel.displayAgentKind(kind)
}

function herdrStatusAccessibleText(status) {
  return HerdrModel.statusLabel(status)
}

// Reserve kind / counters / fold control width first; name receives the remainder.
function herdrCompactLabelWidths(input) {
  var o = input || ({})
  var available = Math.max(0, Number(o.availableWidth) || 0)
  var kindWidth = Math.max(0, Number(o.kindWidth) || 0)
  var countersWidth = Math.max(0, Number(o.countersWidth) || 0)
  var controlsWidth = Math.max(0, Number(o.controlsWidth) || 0)
  var gap = Math.max(0, Number(o.gap) || 0)
  var trailing = 0
  var gaps = 0
  if (kindWidth > 0) {
    trailing += kindWidth
    gaps += 1
  }
  if (countersWidth > 0) {
    trailing += countersWidth
    gaps += 1
  }
  if (controlsWidth > 0) {
    trailing += controlsWidth
    gaps += 1
  }
  var reserved = trailing + gap * gaps
  return {
    nameWidth: Math.max(0, available - reserved),
    kindWidth: kindWidth,
    countersWidth: countersWidth,
    controlsWidth: controlsWidth,
    reserved: reserved
  }
}
