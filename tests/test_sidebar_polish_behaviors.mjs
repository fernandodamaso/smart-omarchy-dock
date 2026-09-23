import assert from 'node:assert/strict'
import { loadModel, plain, read } from './host_harness.mjs'
import { qmlMethods } from './sidebar_interaction_fixture.mjs'
import { sidebarFixture, desktopModel } from './sidebar_fixture.mjs'

const Interaction = loadModel('DockSidebarInteractionModel')
const SidebarModel = loadModel('DockSidebarModel')
const WindowModel = loadModel('DockWindowModel')
const FullscreenModel = loadModel('DockFullscreenModel')
const rowQml = read('components/DockSidebarRow.qml')
const controllerQml = read('components/DockSidebarController.qml')
const sidebarQml = read('components/DockSidebar.qml')
const viewportQml = read('components/DockSidebarViewport.qml')
const keyboardQml = read('components/DockSidebarKeyboard.qml')
const rowInputQml = read('components/DockSidebarRowInput.qml')
const pinnedStripQml = read('components/DockSidebarPinnedStrip.qml')

// rowFill / persistentFill composition priorities
assert.equal(Interaction.composeRowFill({
  dropTarget: true, pressed: true, hovered: true, navigable: true,
  persistentSelected: true, dropFill: 'drop', pressedFill: 'press',
  selectedHoverFill: 'sel-hover', persistentFill: 'persist'
}), 'drop', 'drop beats pressed/hover/persistent')

assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: true, hovered: true, navigable: true,
  persistentSelected: true, pressedFill: 'press', selectedHoverFill: 'sel-hover',
  persistentFill: 'persist'
}), 'press', 'pressed beats hover on focused window')

assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: false, hovered: true, navigable: true,
  persistentSelected: true, selectedHoverFill: 'sel-hover', persistentFill: 'persist'
}), 'sel-hover', 'focused window still receives hover feedback')

assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: false, hovered: true, navigable: true,
  persistentSelected: false, persistentContext: true,
  contextHoverFill: 'ctx-hover', hoverFill: 'hover', persistentFill: 'persist'
}), 'ctx-hover', 'active workspace / folded focused-app still hover')

assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: false, hovered: false, navigable: true,
  persistentSelected: true, persistentFill: 'persist'
}), 'persist', 'idle focused window keeps persistent fill')

// Passive hover is separate from activation: non-navigable rows (monitors)
// must not take hover fill via the navigable-gated compose path.
assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: false, hovered: true, navigable: false,
  persistentContext: true, contextHoverFill: 'ctx-hover', hoverFill: 'hover',
  persistentFill: 'persist'
}), 'persist', 'monitor hover fill stays persistent; tooltip uses passive HoverHandler')

// Herdr rows expose hover/focus affordance only when the authoritative
// per-server focus capability made the projected row actionable.
assert.equal(Interaction.rowHoverFillEligible('herdr-agent', true), true)
assert.equal(Interaction.rowHoverFillEligible('herdr-agent', false), false)
assert.equal(Interaction.rowHoverFillEligible('herdr-tab', true), true)
assert.equal(Interaction.rowHoverFillEligible('herdr-tab', false), false)
assert.equal(Interaction.rowHoverFillEligible('herdr-state'), false)
assert.equal(Interaction.rowHoverFillEligible('monitor'), false)
assert.equal(Interaction.rowHoverFillEligible('browser-tab'), true)
assert.equal(Interaction.composeRowFill({
  dropTarget: false, pressed: false, hovered: true,
  navigable: Interaction.rowHoverFillEligible('herdr-agent', true),
  hoverFill: 'hover', persistentFill: 'persist'
}), 'hover', 'actionable herdr-agent hover paints fill')
assert.match(rowQml, /navigable:\s*InteractionModel\.rowHoverFillEligible\(root\.kind/,
  'rowFill gates hover via rowHoverFillEligible')
assert.match(rowQml,
  /navigable:\s*\[["']window["'],\s*["']workspace["'],\s*["']application["'],\s*["']launcher["'],\s*["']browser-tab["']\]/,
  'herdr-agent activation stays outside the generic navigable kind list')

// Variable-height scroll restore uses heightMap; shared sidebarRowMetrics baselines
const monitor0 = { kind: 'monitor', sectionIndex: 0, layoutGapBefore: '' }
const monitor1 = { kind: 'monitor', sectionIndex: 1, layoutGapBefore: 'monitor' }
const windowRow = { kind: 'window', layoutGapBefore: '' }
const id = n => n
assert.equal(Interaction.estimatedSidebarRowHeight(monitor0, false, 34, id), 32)
assert.equal(Interaction.estimatedSidebarRowHeight(monitor1, false, 34, id), 32 + 8)
assert.equal(Interaction.estimatedSidebarRowHeight(windowRow, false, 34, id), 28)
assert.equal(Interaction.estimatedSidebarRowHeight(windowRow, true, 34, id), 36)
assert.equal(Interaction.estimatedSidebarRowHeight(windowRow, true, 34, id, true), 58)
assert.equal(Interaction.sidebarRowHasNumericAlert(true, true), true)
assert.equal(Interaction.sidebarRowHasNumericAlert(true, false), false)
assert.equal(Interaction.sidebarRowHasNumericAlert(false, true), false,
  'expanded never takes rail numeric alert height')
assert.equal(Interaction.sidebarRowHasNumericAlert(true, 'count:3:attention'), true,
  'legacy badge token still accepted')
assert.equal(Interaction.sidebarRowHasNumericAlert(true, 'none'), false)
assert.equal(Interaction.sidebarRowHasNumericAlert(true, 'urgent'), false)
assert.equal(Interaction.estimatedSidebarRowHeight(windowRow, true, 34, id,
  Interaction.sidebarRowHasNumericAlert(true, true)), 58,
  'estimator and row share sidebarRowHasNumericAlert + attention.countVisible')
// Phase 5: persistent window-name motion eligibility (included aggregate only).
assert.equal(Interaction.attentionNameMotionEligible(
  'window', false, true, 3, true, false), true,
  'expanded window with included count >0 animates')
assert.equal(Interaction.attentionNameMotionEligible(
  'window', false, true, 0, true, false), false,
  'muted-to-zero included aggregate stops motion')
assert.equal(Interaction.attentionNameMotionEligible(
  'window', false, false, 5, true, false), false,
  'countVisible false (no numeric badge) does not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'window', true, true, 3, true, false), false,
  'collapsed rail does not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'window', false, true, 3, true, true), false,
  'row drag halts and prevents start')
assert.equal(Interaction.attentionNameMotionEligible(
  'window', false, true, 3, false, false), false,
  'interfaceAnimationsEnabled/reduced motion disables motion')
assert.equal(Interaction.attentionNameMotionEligible(
  'browser-tab', false, true, 3, true, false), false,
  'browser tabs do not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'application', false, true, 3, true, false), false,
  'application group headers do not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'launcher', false, true, 3, true, false), false,
  'launchers do not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'monitor', false, true, 3, true, false), false,
  'monitor rows do not animate')
assert.equal(Interaction.attentionNameMotionEligible(
  'workspace', false, true, 3, true, false), false,
  'workspace rows do not animate')
const m = Interaction.sidebarRowMetrics(windowRow, false, 34, id)
assert.equal(m.contentHeight, 28)
assert.equal(m.height, Interaction.estimatedSidebarRowHeight(windowRow, false, 34, id))
assert.equal(Interaction.sidebarRowMetrics(windowRow, false, 40, id).contentHeight, 28,
  'rowHeight 40 → font floor 28; expanded window stays 28')
assert.equal(Interaction.sidebarRowMetrics(windowRow, false, 50, id).contentHeight, 38,
  'larger configured font floor can grow content above baseline')
assert.equal(
  Interaction.sidebarRowMetrics({ kind: 'herdr-agent' }, false, 34, id).contentHeight,
  36,
  'herdr-agent two-line rows stay compact at 36',
)

assert.equal(Interaction.shouldRestoreScroll({
  keys: ['a', 'b'], rowHeight: 40, collapsed: false, contentHeight: 200, heightMap: '28,34'
}, {
  keys: ['a', 'b'], rowHeight: 40, collapsed: false, contentHeight: 200, heightMap: '28,34'
}), false, 'identical geometry skips restore')

assert.equal(Interaction.shouldRestoreScroll({
  keys: ['a', 'b'], rowHeight: 40, collapsed: false, contentHeight: 200, heightMap: '28,34'
}, {
  keys: ['a', 'b'], rowHeight: 40, collapsed: false, contentHeight: 200, heightMap: '36,36'
}), true, 'heightMap change restores even when keys+rowHeight match')

assert.equal(Interaction.shouldRestoreScroll({
  keys: ['a', 'b'], rowHeight: 40, collapsed: false, contentHeight: 200, heightMap: '28,34'
}, {
  keys: ['a', 'b'], rowHeight: 40, collapsed: true, contentHeight: 200, heightMap: '28,34'
}), true, 'rail collapse restores')

assert.equal(Interaction.shouldRestoreScroll({
  keys: ['a', 'b'], rowHeight: 40, collapsed: true, contentHeight: 200, heightMap: '36,36'
}, {
  keys: ['a', 'b'], rowHeight: 40, collapsed: true, contentHeight: 222, heightMap: '36,58'
}), true, 'rail alert 36→58 contentHeight/heightMap change restores')

// Narrow sidebar picker clamp (classic vs side)
const side = Interaction.clampPopupAnchor('left', { x: 288, y: 100 },
  { width: 280, height: 1080 }, { width: 380, height: 420 })
assert.equal(side.x, 288, 'left sidebar must not clamp x into narrow panel')
assert.ok(side.y >= 8)

const classic = Interaction.clampPopupAnchor('bottom', { x: -40, y: -100 },
  { width: 1920, height: 64 }, { width: 380, height: 420 })
assert.equal(classic.x, 8, 'classic bottom still clamps x into the dock window')

// Picker anchor lifecycle decisions
const decide = (anchor, opts) => JSON.stringify(Interaction.pickerAnchorDecision(anchor, opts))
assert.equal(decide(null, {}), JSON.stringify({ action: 'dismiss', reason: 'missing' }))
assert.equal(decide({}, { footer: true, visible: true }),
  JSON.stringify({ action: 'reanchor', reason: 'footer' }))
assert.equal(decide({}, { footer: false, visible: false, width: 0 }),
  JSON.stringify({ action: 'dismiss', reason: 'destroyed' }))
assert.equal(decide({}, {
  footer: false, visible: true, width: 28, y: -40, height: 28, viewportHeight: 400
}), JSON.stringify({ action: 'dismiss', reason: 'scrolled-out' }))
assert.equal(decide({}, {
  footer: false, visible: true, width: 28, y: 120, height: 28, viewportHeight: 400
}), JSON.stringify({ action: 'reanchor', reason: 'in-view' }))

// Compact rail labels stay distinguishable
assert.equal(SidebarModel.compactMonitorRailLabel('Virtual-1', 0), 'V1')
assert.equal(SidebarModel.compactMonitorRailLabel('Virtual-2', 1), 'V2')
assert.notEqual(SidebarModel.compactMonitorRailLabel('Virtual-1', 0),
  SidebarModel.compactMonitorRailLabel('Virtual-2', 1))

// Workspace badge identity: prefer display label; id:/name: fallback only.
assert.equal(Interaction.workspaceBadgeLabel('id:3'), '3')
assert.equal(Interaction.workspaceBadgeLabel('name:Work'), 'Work')
assert.equal(Interaction.workspaceBadgeLabel('id:10'), '10', 'id:10 must not truncate to 1')
assert.equal(Interaction.workspaceBadgeLabel('id:10', 'Work'), 'Work',
  'Hyprland id:10 named Work shows Work, not 10')
assert.equal(Interaction.workspaceBadgeLabel('id:3', '3'), '3')
assert.equal(Interaction.workspaceBadgeLabel('name:Design work'), 'Design work')
assert.equal(Interaction.workspaceBadgeLabel('', 'Work'), 'Work')
assert.equal(Interaction.workspaceBadgeLabel(''), '')

// Collapsed rail abbreviation: full numerics preserved, others two code points.
assert.equal(Interaction.compactWorkspaceBadgeLabel('Work'), 'Wo')
assert.equal(Interaction.compactWorkspaceBadgeLabel('Development'), 'De')
assert.equal(Interaction.compactWorkspaceBadgeLabel('W'), 'W')
assert.equal(Interaction.compactWorkspaceBadgeLabel('10'), '10')
assert.equal(Interaction.compactWorkspaceBadgeLabel('100'), '100')
assert.equal(Interaction.compactWorkspaceBadgeLabel('2Work'), '2W')
assert.equal(Interaction.compactWorkspaceBadgeLabel(''), '')
assert.equal(Interaction.compactWorkspaceBadgeLabel('  Work  '), 'Wo',
  'surrounding whitespace trimmed before abbreviation')
assert.equal(Interaction.compactWorkspaceBadgeLabel('😀Work'), '😀W',
  'surrogate pairs must not split')
assert.equal(Array.from(Interaction.compactWorkspaceBadgeLabel('😀Work')).length, 2,
  'compact emoji label is two code points')
assert.match(rowQml, /workspaceRailLabel[\s\S]*?compactWorkspaceBadgeLabel/,
  'collapsed rail label uses the compact helper')

// Topology strip: physical order + shared focused index/ordinal (not sectionIndex).
assert.equal(Interaction.focusedMonitorStripIndex([
  { focused: false }, { focused: true }, { focused: false }
]), 1)
assert.equal(Interaction.focusedMonitorStripIndex([
  { focused: true }, { focused: false }
]), 0)
assert.equal(Interaction.focusedMonitorStripIndex([
  { focused: false }, { focused: false }
]), -1)
assert.equal(Interaction.focusedMonitorStripIndex([]), -1)
assert.equal(Interaction.focusedMonitorStripOrdinal([
  { focused: false }, { focused: true }, { focused: false }
]), '2/3')
assert.equal(Interaction.focusedMonitorStripOrdinal([
  { focused: false }, { focused: false }
]), '')
assert.equal(Interaction.topologyStripWidth(2), 13 * 2 + 3)
assert.equal(Interaction.topologyStripWidth(4), 13 * 4 + 9)
assert.equal(Interaction.topologyStripWidth(5), 24)
assert.match(rowQml, /physicalMonitorStrip/,
  'row builds miniatures from physicalMonitorStrip, not card section order')
assert.match(rowQml, /focusedMonitorStripOrdinal/,
  '>4 ordinal uses shared focused physical monitor on every header')
assert.doesNotMatch(rowQml, /monitorStripOrdinal:\s*\(monitorSectionIndex/,
  'ordinal must not be sectionIndex+1/N')
assert.doesNotMatch(rowQml, /index === root\.monitorSectionIndex/,
  'topology miniatures must not highlight sectionIndex')
assert.doesNotMatch(rowQml, /\(\s*"\s*\+\s*root\.attention\.text/,
  'numeric alert text must not wrap attention.text in parentheses')
assert.match(controllerQml, /ipc\.pinned === true/,
  'window pin indicator uses Hyprland IPC pinned, not settings.pinned')
assert.doesNotMatch(controllerQml, /pinnedIds\.indexOf\(DockModel\.normalizedId\(row\.desktopId\)\)/,
  'windowStateForRow must not treat launcher pins as window pins')
assert.doesNotMatch(controllerQml, /windowIpcPinned/,
  'no wrapper-only windowIpcPinned helper')
assert.doesNotMatch(sidebarQml, /activeMonitorBorder/,
  'active monitor card outline token removed')
assert.doesNotMatch(viewportQml, /activeMonitorBorder/,
  'viewport no longer paints active monitor border')

// Reversed configured card order + nonspatial Hyprland IDs must not reorder miniatures.
{
  const f = sidebarFixture()
  // HDMI id=2 at x=0, DP-1 id=9 at x=-1920 — IDs are not spatial.
  f.settings.workspaceMonitorOrder = ['USB-C-1', 'HDMI-A-1', 'DP-1']
  f.monitors[0].lastIpcObject.focused = true // HDMI
  f.monitors[1].lastIpcObject.focused = false // DP-1
  const registry = SidebarModel.reconcileHandles(null, f.toplevels)
  const projection = SidebarModel.project({
    desktop: desktopModel.build(f.input),
    screens: f.screens, monitors: f.monitors,
    monitorOrder: f.settings.workspaceMonitorOrder,
    pinned: f.settings.pinned, hiddenApplications: f.settings.hiddenApplications || [],
    registry, folds: {}, collapsed: false
  })
  assert.deepEqual(Array.from(projection.monitorSections, m => m.connector).filter(Boolean),
    ['USB-C-1', 'HDMI-A-1', 'DP-1'],
    'card/projection order follows reversed workspaceMonitorOrder')
  const strip = SidebarModel.physicalMonitorStrip(
    f.screens, f.monitors, projection.monitorSections)
  assert.deepEqual(Array.from(strip, m => m.connector),
    ['DP-1', 'HDMI-A-1', 'USB-C-1'],
    'miniatures stay physical x/y despite reversed configured order')
  assert.notDeepEqual(Array.from(strip, m => m.connector),
    Array.from(projection.monitorSections, m => m.connector).filter(Boolean),
    'strip order must diverge from configured card order in this fixture')
  assert.equal(Interaction.focusedMonitorStripIndex(strip), 1,
    'focus joins by connector/identity onto physical HDMI (index 1)')
  assert.equal(Interaction.focusedMonitorStripOrdinal(strip), '2/3',
    '>4 ordinal is the focused physical monitor on every header')
}

// Real windowStateForRow: settings.pinned must not light the window pin icon.
{
  const toplevel = { appId: 'chrome', title: 'Doc' }
  const handle = {
    wayland: toplevel,
    address: '0xpin',
    lastIpcObject: { pinned: false, fullscreen: 0, fullscreenClient: 0 }
  }
  const stateController = qmlMethods('DockSidebarController.qml', {
    DockModel: loadModel('DockModel'),
    WindowModel,
    FullscreenModel,
    settings: { pinned: ['chrome'] },
    hyprToplevels: [handle],
    scopeRevision: 0
  })
  const row = { kind: 'window', desktopId: 'chrome', toplevel, minimized: false }
  assert.equal(stateController.windowStateForRow(row).pinned, false,
    'launcher settings.pinned must not report window pinned')
  handle.lastIpcObject.pinned = true
  assert.equal(stateController.windowStateForRow(row).pinned, true,
    'Hyprland IPC pinned lights the window pin indicator')
  assert.equal(stateController.windowStateForRow(row).minimized, false)
  row.minimized = true
  assert.equal(stateController.windowStateForRow(row).minimized, true,
    'minimized stays independent of IPC pin')
}

// Tree guide columns: 4px group padding, badge-centered guide, 20px depth.
const guide = Interaction.sidebarTreeGuideLayout(5)
assert.equal(guide.workspaceLeft, 5)
assert.equal(guide.badgeLeft, 9)
assert.equal(guide.guide0, 21)
assert.equal(guide.iconHalf, 9, 'child columns center on the 18px window icon')
assert.equal(Interaction.sidebarTreeIconX(5, 1), 40)
assert.equal(Interaction.sidebarTreeIconX(5, 2), 60)
assert.equal(Interaction.sidebarTreeIconX(5, 3), 80)

// Rendered guide column: depth-1 stays on the badge column (stemOffset only);
// every deeper row branches from the parent's rendered icon *center*
// (parentArt + iconHalf) instead of the nominal left-edge ladder.
assert.equal(Interaction.sidebarTreeGuideColumnX(5, 1, 0, 0), 21,
  'depth-1 keeps the guide0 badge column with no badge shift')
assert.equal(Interaction.sidebarTreeGuideColumnX(5, 1, 19, 4), 25,
  'depth-1 tracks the measured badge center; guideOffset never leaks in')
assert.equal(Interaction.sidebarTreeGuideColumnX(5, 2, 0, 0),
  Interaction.sidebarTreeIconX(5, 1) + guide.iconHalf,
  'depth-2 branches from the parent icon center, not its left edge')
assert.equal(Interaction.sidebarTreeGuideColumnX(5, 3, 11, 4),
  Interaction.sidebarTreeIconX(5, 2) + 11 + guide.iconHalf,
  'every deeper depth is parentArt + iconHalf; stemOffset never leaks up')

// Inline workspace badge geometry: art sits after the real badge width + gap.
{
  const sp = n => n
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeMaxWidth(sp), 64)

  // One measured chip-width contract for every row of a workspace: real font
  // advance + padding, floored at 24, capped by the shared ceiling and by the
  // workspace-wide available slot. No per-row label estimate survives.
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(0, 0, sp), 24)
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(10, 0, sp), 24,
    '10px label + 8px padding stays on the 24px floor')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(24, 0, sp), 32)
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(56, 0, sp), 64,
    'padding can reach but never exceed the shared ceiling')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(400, 0, sp), 64,
    'long labels clamp to the ceiling instead of growing per row')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(NaN, undefined, sp), 24,
    'missing measurement keeps the stable floor')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(24, 40, sp), 32)
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(24, 28, sp), 28,
    'narrow panel clamps every row to the same available slot')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(24, 12, sp), 24,
    'available slot never drops below the floor')

  assert.equal(Interaction.sidebarInlineWorkspaceBadgeAvailableWidth(280, 5, sp), 280 - 9 - 8 - 56,
    'workspace-wide budget = content - badge left - padding - widest control stack')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeAvailableWidth(100, 5, sp), 27,
    'narrow content keeps only the remaining badge slot')
  assert.equal(Interaction.sidebarInlineWorkspaceBadgeAvailableWidth(0, 5, sp), 0,
    'unmapped content reports no budget so rows fall back together')

  // Two direct window rows of one workspace consume the identical measured
  // width, so artwork, label and hover/selection edges align exactly.
  const available = Interaction.sidebarInlineWorkspaceBadgeAvailableWidth(280, 5, sp)
  const workChip = Interaction.sidebarInlineWorkspaceBadgeLayoutWidth(24, available, sp)
  assert.equal(workChip, 32, 'measured chip keeps its real width (no 8px/glyph rounding up)')
  const leading = Interaction.sidebarInlineWorkspaceGeometry(5, sp, workChip)
  const following = Interaction.sidebarInlineWorkspaceGeometry(5, sp, workChip)
  assert.equal(following.badgeX, leading.badgeX)
  assert.equal(following.artX, leading.artX)
  assert.equal(following.labelX, leading.labelX)
  assert.equal(following.stemX, leading.stemX)
  assert.equal(leading.stemX, guide.badgeLeft + workChip / 2,
    'depth-1 stem stays on the badge center for a named badge')
  const leadingSel = Interaction.sidebarSelectionInsets({
    kind: 'window', collapsed: false, insideWorkspaceCard: true,
    workspaceCardInset: 5, artX: leading.artX
  })
  const followingSel = Interaction.sidebarSelectionInsets({
    kind: 'window', collapsed: false, insideWorkspaceCard: true,
    workspaceCardInset: 5, artX: following.artX
  })
  assert.equal(followingSel.left, leadingSel.left,
    'hover/selection backgrounds start at the same left edge')

  const tight = Interaction.sidebarInlineWorkspaceGeometry(5, sp, 24)
  assert.equal(tight.badgeX, 9)
  assert.equal(tight.artX, 9 + 24 + 8)
  assert.equal(tight.stemX, 9 + 12)
  assert.equal(tight.labelX, tight.artX + 18 + 4)
  assert.equal(tight.guideOffset, tight.artX - Interaction.sidebarTreeIconX(5, 1))
  assert.equal(tight.stemOffset, 0, '24px badge stem stays on guide0')
  assert.equal(Interaction.sidebarTreeGuideColumnX(5, 1, tight.guideOffset,
    tight.stemOffset), tight.stemX,
    'the rendered depth-1 column matches the measured badge stem')
  const wide = Interaction.sidebarInlineWorkspaceGeometry(5, sp, 64)
  assert.equal(wide.artX, 9 + 64 + 8)
  assert.equal(wide.stemOffset, wide.stemX - guide.guide0)
  assert.ok(wide.stemOffset !== wide.guideOffset,
    'wide badge: stem and icon offsets differ')
  assert.equal(wide.stemX, guide.badgeLeft + 32)
  const clamped = Interaction.sidebarInlineWorkspaceGeometry(5, sp, 200)
  assert.equal(clamped.artX, wide.artX, 'badge width clamps to max before artX')
  assert.equal(clamped.stemOffset, wide.stemOffset)
  const defaults = Interaction.sidebarInlineWorkspaceGeometry(5, sp)
  assert.equal(defaults.artX, tight.artX, 'missing badgeWidth uses the 24px minimum')
  assert.equal(defaults.stemOffset, 0)

  // Wide badge: deeper columns still center the (shifted) parent icon.
  assert.equal(Interaction.sidebarTreeGuideColumnX(5, 2, wide.guideOffset,
    wide.stemOffset), wide.artX + guide.iconHalf,
    'wide badge shifts the column with the icon, not with the badge center')

  // The compact group keeps nested guides under the parent icon centre.
  const live = Interaction.sidebarInlineWorkspaceGeometry(11, sp, 24)
  assert.equal(live.artX, 47)
  assert.equal(live.guideOffset, 1)
  assert.equal(Interaction.sidebarTreeGuideColumnX(11, 2, live.guideOffset,
    live.stemOffset), 56, 'live depth-2 guide sits on the parent icon center')
  assert.equal(Interaction.sidebarTreeGuideColumnX(11, 3, live.guideOffset,
    live.stemOffset), 76, 'live depth-3 guide uses the same center rule')
}

// Inline guide/alignment wiring: one viewport-owned measurement, badge-edge
// connectors, workspace-scoped stem continuation, no header connector text.
assert.doesNotMatch(rowQml, /sidebarInlineWorkspaceBadgeWidthForLabel/,
  'rows never re-estimate chip width from the label')
assert.match(rowQml, /viewport\.inlineWorkspaceBadgeWidths/,
  'rows read the viewport-owned per-workspace measurement')
assert.match(rowQml, /width: root\.inlineBadgeLayoutWidth/,
  'the rendered chip binds the shared measurement')
assert.match(viewportQml, /sidebarInlineWorkspaceBadgeLayoutWidth/,
  'the viewport owns the shared chip-width contract')
assert.match(viewportQml, /inlineBadgeProbe/,
  'the viewport measures the badge font independently of delegates')
assert.doesNotMatch(rowQml, /hasVisibleNestedTreeChildren/,
  'expanded descendants alone must not continue the badge stem')
assert.match(rowQml,
  /badgeStemExtendsDown: root\.leadingWorkspaceBadgeVisible\s*&&\s*!root\.isLastSibling/,
  'the badge stem continues only to another direct row of the workspace')
assert.match(rowQml, /sidebarTreeGuideColumnX\(root\.workspaceCardInset,/,
  'row stems read the icon-centered guide column helper')
assert.doesNotMatch(rowQml, /sidebarTreeStemX\(/,
  'no row still draws the old left-edge guide ladder')
assert.match(rowQml, /y: Math\.max\(treeGuides\.contentMid, treeGuides\.inlineBadgeBottom\)/,
  'the badge stem starts below the chip, never through it')
assert.match(rowQml,
  /x: leadingWorkspaceBadge\.x \+ leadingWorkspaceBadge\.width\n\s*y: treeGuides\.contentMid/,
  'the horizontal connector starts at the right edge of the chip')
assert.match(rowQml, /y: treeGuides\.workspaceBadgeBottom/,
  'workspace header stems also start below their chip')
assert.doesNotMatch(rowQml, /monitorConnectorLabel|sidebar-label-connector/,
  'monitor headers no longer render connector names')
assert.match(rowQml, /id: monitorTitleLabel[\s\S]{0,160}?width: parent\.width/,
  'the monitor title takes the freed header width')
assert.match(rowQml,
  /workspaceHeader: true\s+dragEnabled: true[\s\S]{0,180}?enabled: leadingWorkspaceBadge\.visible/,
  'the inline workspace badge keeps a live workspace drag source while busy state is owned internally')
assert.match(rowQml, /onDragMoved: point =>[\s\S]{0,100}?viewport\.moveDrag\(point\)/,
  'inline workspace drag motion reaches the viewport')
assert.match(rowQml, /onDragReleased: point =>[\s\S]{0,100}?viewport\.finishDrag\(point\)/,
  'inline workspace drag release reaches the viewport')
assert.doesNotMatch(rowQml,
  /enabled: leadingWorkspaceBadge\.visible && !root\.controller\.interactionBusy/,
  'workspace badge input must stay enabled after beginRowDrag owns interactionBusy')
assert.match(rowQml, /activeFocusOnTab: true/,
  'inline workspace badge is an explicit keyboard focus target')
assert.match(rowQml,
  /activeFocus: root\.activeFocus && root\.focusReason !== Qt\.MouseFocusReason/,
  'mouse focus does not produce the stale row focus fill')
assert.match(rowQml,
  /borderSpec: root\.activeFocus && root\.focusReason !== Qt\.MouseFocusReason/,
  'mouse focus does not produce the stale row focus border')
assert.match(rowInputQml,
  /id: hover[\s\S]{0,100}?cursorShape: Qt\.ArrowCursor/,
  'ordinary rows override the panel-wide drag cursor')
assert.match(sidebarQml,
  /id: headerBar[\s\S]{0,140}?HoverHandler \{ cursorShape: Qt\.ArrowCursor \}/,
  'header controls override the panel-wide drag cursor')
assert.match(pinnedStripQml, /HoverHandler \{ cursorShape: Qt\.ArrowCursor \}/,
  'the pinned area overrides the panel-wide drag cursor')
assert.match(viewportQml,
  /visible: isWorkspace && geom\.height > 0\s*&& !InteractionModel\.isMonitorFinalKey\(modelData\.lastKey, root\.sectionSpans\)/,
  'the final workspace in each monitor does not draw a trailing divider')
assert.match(rowQml,
  /id: leadingWorkspaceBadge[\s\S]{0,260}?readonly property string rowKey: root\.inlineWorkspaceBadgeKey/,
  'inline workspace badge exposes its workspace rowKey so context refresh keeps a valid menu open')
assert.match(rowQml, /Accessible\.onPressAction:[\s\S]{0,220}?captureTarget\(root\.inlineWorkspaceBadgeKey\)/,
  'assistive activation resolves the synthetic workspace target')
assert.match(viewportQml, /function focusRow\(key, preferInlineWorkspaceBadge\)/,
  'viewport can enter a row through its inline workspace badge')
assert.match(keyboardQml, /inlineWorkspaceBadgeFocused/,
  'keyboard adapter distinguishes workspace badge focus from the child row')
assert.match(keyboardQml, /focusInlineWorkspaceBadge\(Qt\.BacktabFocusReason\)/,
  'reverse tab navigation enters the inline workspace badge before leaving the row')
assert.match(keyboardQml, /captureTarget\(actionKey\)/,
  'keyboard activation/context resolves the workspace key while the badge owns focus')
assert.match(sidebarQml,
  /trashButton\.visible \? parent\.spacing : 0/,
  'launcher reserves utility spacing only when Trash is visible')

// Phase 4: tree-indented selection starts 3px before artX; guides stay left.
const depth1Art = Interaction.sidebarTreeIconX(5, 1)
const depth2Art = Interaction.sidebarTreeIconX(5, 2)
const depth1Sel = Interaction.sidebarSelectionInsets({
  kind: 'window', collapsed: false, insideWorkspaceCard: true,
  workspaceCardInset: 5, artX: depth1Art
})
assert.equal(depth1Sel.left, depth1Art - 3)
assert.equal(depth1Sel.right, 5)
assert.ok(depth1Sel.left > guide.guide0,
  'depth-1 selection leaves guide0 visible to the left')
const depth2Sel = Interaction.sidebarSelectionInsets({
  kind: 'browser-tab', collapsed: false, insideWorkspaceCard: true,
  workspaceCardInset: 5, artX: depth2Art
})
assert.equal(depth2Sel.left, depth2Art - 3)
assert.ok(depth2Sel.left > guide.guide0,
  'nested tab selection leaves parent stem visible')
assert.equal(String(JSON.stringify(Interaction.sidebarSelectionInsets({
  kind: 'workspace', collapsed: false, insideWorkspaceCard: true,
  workspaceCardInset: 5, artX: 13
}))), '{"left":5,"right":5}', 'workspace headers keep whole-card selection')
assert.equal(String(JSON.stringify(Interaction.sidebarSelectionInsets({
  kind: 'window', collapsed: true, insideWorkspaceCard: true,
  workspaceCardInset: 5, artX: 0
}))), '{"left":5,"right":5}', 'collapsed rail keeps compact card insets')
assert.equal(String(JSON.stringify(Interaction.sidebarSelectionInsets({
  kind: 'application', collapsed: false, insideWorkspaceCard: true,
  workspaceCardInset: 5, artX: depth1Art
}))), JSON.stringify({ left: depth1Art - 3, right: 5 }),
  'application rows share indented selection')

// Phase 4 static: compact alert badge after state / before fold; rail badge
// stays in the 16px metric slot under the icon.
assert.match(rowQml, /objectName:\s*"sidebar-alert-count"/,
  'expanded numeric alert uses compact badge objectName')
assert.match(rowQml, /objectName:\s*"sidebar-rail-alert-count"/,
  'rail numeric alert uses compact badge objectName')
assert.match(rowQml, /id:\s*alertCount[\s\S]*?radius:\s*Style\.space\(3\)/,
  'alert badge radius is Style.space(3)')
assert.match(rowQml, /id:\s*alertCount[\s\S]*?Style\.space\(4\)\s*\*\s*2/,
  'alert badge uses 4px horizontal padding')
assert.match(rowQml, /selectionLeft/,
  'fillLayer / focus rail consume shared selectionLeft')
assert.ok(rowQml.indexOf('id: stateStrip') < rowQml.indexOf('id: alertCount'),
  'window state icons precede the alert badge in source order')
assert.ok(rowQml.indexOf('id: alertCount') < rowQml.indexOf('id: fold'),
  'alert badge precedes the final fold chevron in source order')
assert.match(rowQml, /anchors\.leftMargin:\s*root\.selectionLeft/,
  'focus rail shares the indented selection left edge')

// Phase 6: exact-tab raw activity lookup vs window presentation dedup; mute
// affects window totals but not a tab's own count; non-browser severity preserved.
const Activity = loadModel('DockBrowserActivityModel')
const Badge = loadModel('DockBadgeModel')

const tidGmail = 'a'.repeat(32)
const tidGmailAlt = 'b'.repeat(32)
const tidWa = 'c'.repeat(32)
const gmailLow = {
  targetId: tidGmail, serviceId: 'gmail', label: 'Gmail', count: 2,
  profileKey: 'Profile 1', windowAddress: '0x1'
}
const gmailHigh = {
  targetId: tidGmailAlt, serviceId: 'gmail', label: 'Gmail', count: 9,
  profileKey: 'Profile 1', windowAddress: '0x1'
}
const whatsapp = {
  targetId: tidWa, serviceId: 'whatsapp', label: 'WhatsApp', count: 4,
  profileKey: 'Profile 1', windowAddress: '0x1'
}
const rawActivities = { '0x1': [gmailLow, gmailHigh, whatsapp] }

const exactTab = Activity.activityForTarget(rawActivities, tidGmail, '0x1')
assert.ok(exactTab, 'raw target+address lookup finds the exact tab')
assert.equal(exactTab.count, 2, 'exact tab keeps its own count, not the service winner')
assert.equal(Activity.activityForTarget(rawActivities, tidGmailAlt, '0x1').count, 9)

const windowDedup = Activity.rowsForAddresses(rawActivities, ['0x1'])
assert.equal(windowDedup.length, 2, 'window dedup keeps one row per service/profile')
assert.equal(windowDedup.find(r => r.serviceId === 'gmail').count, 9,
  'window aggregate picks the higher gmail count')
assert.notEqual(exactTab.count, windowDedup.find(r => r.serviceId === 'gmail').count,
  'tab raw lookup must not use window dedup winners')

const mutedTotal = Activity.presentation(
  Activity.rawRowsForAddresses(rawActivities, ['0x1']), ['gmail']).total
assert.equal(mutedTotal, 4, 'muting gmail drops it from window totals')
assert.equal(exactTab.count, 2, 'muted service does not clear the tab own-count')

const urgentOnly = Badge.decodeApplicationBadgeToken('urgent')
assert.equal(urgentOnly.kind, 'dot')
assert.equal(urgentOnly.countVisible, false)
assert.equal(urgentOnly.severity, 'urgent')
assert.equal(urgentOnly.count, 0, 'never manufacture numeric counts for urgent-only')
const countToken = Badge.decodeApplicationBadgeToken('count:120:attention')
assert.equal(countToken.countVisible, true)
assert.equal(countToken.text, '99+')
assert.equal(countToken.severity, 'attention')
const attention = Badge.attentionFromBadgeToken('urgent')
assert.equal(attention.countVisible, false)
assert.equal(attention.severity, 'urgent')
assert.equal(attention.serviceId, '')

// Expanded monitor labels include connector on first paint (no late prefix growth)
assert.equal(SidebarModel.compactMonitorRailLabel('DP-1', 0), 'DP1')
assert.equal(SidebarModel.compactMonitorRailLabel('HDMI-A-1', 1), 'HDA1')

// Production rowsByKey registers strip launchers (the prior P1 regression).
const empty = SidebarModel.emptyProjection()
assert.deepEqual(Object.keys(SidebarModel.indexRowsByKey(empty)), [])
const indexed = SidebarModel.indexRowsByKey({
  rows: [{ key: 'row-a', kind: 'window' }],
  launchers: [{ key: 'pin-a', kind: 'launcher' }]
})
assert.equal(indexed['row-a'].kind, 'window')
assert.equal(indexed['pin-a'].kind, 'launcher')

// emptyProjection carries sectionSpans for dual-projection clears
const emptySpans = SidebarModel.emptyProjection()
assert.deepEqual(Array.from(emptySpans.sectionSpans || ['missing']), [])

// Pin-shelf context menus are shortcuts: never attach live window members.
// Coerce out of the vm realm before assert (cross-realm values confuse node assert).
assert.equal(String(JSON.stringify(Interaction.contextMenuMembers({
  kind: 'launcher', members: [{ id: 'win' }]
}, { pinStripOwned: true }))), '[]', 'pin strip clears members')
assert.equal(String(JSON.stringify(Interaction.contextMenuMembers({
  kind: 'launcher', members: [{ id: 'win' }]
}, {}))), '[{"id":"win"}]', 'hierarchy launcher keeps members')
assert.equal(String(JSON.stringify(Interaction.contextMenuMembers({
  kind: 'window', toplevel: { id: 't' }
}, null))), '[{"id":"t"}]', 'window rows keep single toplevel')

// Phase 1 live correction: browser parent rows use desktop-entry name; tabs and
// non-browser windows keep their useful titles. Tooltip keeps the window title.
const chromeEntry = {
  id: 'google-chrome', name: 'Google Chrome', startupClass: 'google-chrome'
}
const ghosttyEntry = {
  id: 'com.mitchellh.ghostty', name: 'Ghostty', startupClass: 'com.mitchellh.ghostty'
}
assert.deepEqual(plain(Activity.effectiveBrowserClasses([])), ['google-chrome'],
  'provider-down still identifies Chrome via default classes')
assert.deepEqual(plain(Activity.effectiveBrowserClasses(['Chromium', ''])), ['Chromium'],
  'live provider classes win when present')
assert.equal(Badge.strictIdentityMatches(
  'google-chrome', chromeEntry, Activity.effectiveBrowserClasses([]), {}), true,
  'Chrome matches without tab provider classes')
assert.equal(Badge.strictIdentityMatches(
  'com.mitchellh.ghostty', ghosttyEntry, Activity.effectiveBrowserClasses([]), {}), false,
  'terminals are not treated as browsers')
assert.equal(Interaction.sidebarWindowDisplayTitle({
  kind: 'window', isBrowser: true,
  entryName: 'Google Chrome', windowTitle: 'Inbox - Gmail - Google Chrome'
}), 'Google Chrome', 'browser parent ignores selected-tab title')
assert.equal(Interaction.sidebarWindowDisplayTitle({
  kind: 'window', isBrowser: false,
  entryName: 'Ghostty', windowTitle: 'nvim main.rs'
}), 'nvim main.rs', 'terminals keep window titles')
assert.equal(Interaction.sidebarWindowDisplayTitle({
  kind: 'browser-tab', isBrowser: true,
  entryName: 'Google Chrome', windowTitle: 'Chrome', tabTitle: 'Linear'
}), 'Linear', 'tab children keep individual titles')
assert.equal(Interaction.sidebarWindowTooltipTitle({
  kind: 'window', isBrowser: true,
  displayTitle: 'Google Chrome', windowTitle: 'Inbox - Gmail - Google Chrome'
}), 'Google Chrome · Inbox - Gmail - Google Chrome',
  'tooltip retains the actual window title')
assert.equal(Interaction.sidebarWindowTooltipTitle({
  kind: 'window', isBrowser: false,
  displayTitle: 'nvim main.rs', windowTitle: 'nvim main.rs'
}), 'nvim main.rs', 'non-browser tooltip stays the window title')

// Phase 3: 13×9 topology strip still leaves positive elide room for monitor
// titles at the live ~271px and 300px content widths (glyph+gaps+strip).
const monitorPad = 8
const monitorGlyph = 24
const monitorGap = 8
for (const contentWidth of [271, 300]) {
  for (const count of [1, 2, 3, 4]) {
    const labelX = monitorPad + monitorGlyph + monitorGap
    const strip = Interaction.topologyStripWidth(count)
    const labelWidth = Math.max(0, contentWidth - labelX - monitorPad - (strip + monitorGap))
    assert.ok(labelWidth >= 80,
      `monitor label elide room at ${contentWidth}px with ${count} displays (${labelWidth}px)`)
  }
}

// Phase 5: only the window-name Text (id: label) carries attention Translate;
// fillLayer and content stay stationary (artwork, badges, guides, selection).
const translateHits = rowQml.match(/transform:\s*Translate\s*\{[^}]*\}/g) || []
assert.equal(translateHits.length, 1,
  'exactly one attention Translate in DockSidebarRow')
assert.match(rowQml, /id:\s*label[\s\S]*?transform:\s*Translate\s*\{\s*x:\s*root\.attentionNudgeX\s*\}/,
  'Translate is on the visible window-name label')
assert.doesNotMatch(rowQml,
  /id:\s*fillLayer\s*\n(?:[ \t]+\S[^\n]*\n)*[ \t]+transform:\s*Translate/,
  'fillLayer must not own a Translate')
assert.doesNotMatch(rowQml,
  /id:\s*content\s*\n(?:[ \t]+\S[^\n]*\n)*[ \t]+transform:\s*Translate/,
  'content item must not own a Translate')
assert.match(rowQml, /function syncAttentionNameMotion\s*\(/,
  'one QML sync function owns start/stop')
assert.doesNotMatch(rowQml, /attentionMotionPrimed|lastAttentionCount|considerAttentionMotion/,
  'obsolete count-increase priming removed')
assert.match(rowQml, /loops:\s*Animation\.Infinite/,
  'motion repeats while eligible')
assert.match(rowQml, /PauseAnimation\s*\{\s*duration:\s*2300\s*\}/,
  '2300ms pause between 700ms nudge cycles')

console.log('sidebar polish behaviors (rowFill/heightMap/picker/rail): PASS')
