import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const read = name => fs.readFileSync(new URL(`../components/${name}`, import.meta.url), 'utf8')
function model(name, imports = {}) {
  const scope = vm.createContext(imports)
  vm.runInContext(read(name).replace(/^\.(pragma|import).*$/gm, ''), scope)
  return scope
}
const DockModel = model('DockModel.js')
const DockWindowModel = model('DockWindowModel.js', { DockModel })
function methods(file, properties) {
  const scope = vm.createContext(properties)
  scope.root = scope
  vm.runInContext((read(file).match(/^  function [\s\S]*?^  }/gm) || []).join('\n'), scope,
    { filename: file })
  return scope
}
function fixture(usingLua = false) {
  const windows = [{ appId: 'editor' }, { appId: 'editor' }, { appId: 'editor' }]
  const handles = windows.map((wayland, index) => ({ wayland, address: String(index + 1),
    lastIpcObject: { workspace: { id: index === 2 ? 9 : 1 }, monitor: 0, pinned: false } }))
  const requests = []
  const workspaces = [
    { id: 1, monitorID: 0 }, { id: 9, monitor: 'DP-1' }, { id: 12, monitor: 'DP-2' },
    { id: -1337, name: 'Design work', monitorID: 1 },
    { id: -1338, name: 'Criação', monitorID: 1 },
    { id: -1339, name: '*', monitorID: 0 },
    { id: -99, name: 'special:scratch', monitorID: 0 }
  ]
  const monitors = [{ id: 0, name: 'DP-1' }, { id: 1, name: 'DP-2' }]
  const actions = methods('DockWindowActions.qml', {
    DockModel, DockWindowModel,
    minimizedWorkspace: 'special:smartdock-minimized', minimizedOrigins: {},
    windowWorkspacePins: {}, workspaceMonitorPins: {},
    ToplevelManager: { toplevels: { values: windows } },
    Hyprland: { toplevels: { values: handles }, workspaces: { values: workspaces },
      monitors: { values: monitors }, usingLua, dispatch: request => requests.push(request) }
  })
  return { actions, windows, handles, requests, workspaces, monitors }
}

// Both production dispatch dialects, not a duplicate request builder.
for (const lua of [false, true]) {
  for (const target of [1, 2, 10, 12, 'name:Design work', 'name:Criação', 'name:*']) {
    assert.equal(DockModel.moveWindowRequest('ABC', target, lua), lua
      ? `hl.dsp.window.move({ window = "address:0xabc", workspace = "${target}", follow = false })`
      : `movetoworkspacesilent ${target},address:0xabc`)
  }
  for (const target of ['', 0, -1, 1.5, 'id:12', 'special:scratch', 'name:',
    'name:bad,dispatch', 'name:bad;dispatch', 'name:bad"', 'name:bad\\',
    'name:bad\n', 'name:bad\tname', 'name:bad\u0000name', 'name:bad\u001fname',
    'name:bad\u007fname', 'name:trailing ', ' name:leading'])
    assert.equal(DockModel.moveWindowRequest('abc', target, lua), '', String(target))
  assert.equal(DockModel.moveWindowRequest('0xabc;bad', 12, lua), '')

  const f = fixture(lua)
  const { actions: a, windows: w, handles: h, requests: r } = f
  const captured = a.captureWorkspaceMove([w[0], w[1], w[0]])
  assert.equal(captured.length, 2)
  assert.equal(captured[0].toplevel, w[0])
  assert.equal(captured[0].address, '0x1')
  assert.equal(a.moveCapturedToplevels(captured, 'id:12'), true)
  assert.equal(r.length, 2)
  assert.ok(r.every(request => !request.includes('address:0x3')),
    'same-app instance on a different card must not join the payload')
  assert.equal(r[0], DockModel.moveWindowRequest('1', 12, lua))
  assert.equal(a.resolveWorkspaceDropTarget('id:12').monitor, 'id:1')
  assert.equal(a.resolveWorkspaceDropTarget('name:Design work').target, 'name:Design work')
  assert.equal(a.resolveWorkspaceDropTarget('name:*').identity, 'name:*')
  r.length = 0
  assert.equal(a.moveCapturedToplevels(captured, 'id:1'), false)
  assert.equal(r.length, 0, 'same-workspace drop is a no-op')
  assert.equal(a.moveCapturedToplevels([captured[0]], 'name:Criação'), true)
  assert.equal(r.pop(), DockModel.moveWindowRequest('1', 'name:Criação', lua))

  // Only the physical IPC workspace proves minimization. A stale object-level
  // relationship or saved origin must not hide a currently visible member.
  h[0].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
  h[0].workspace = { id: 1 }
  h[1].workspace = { name: 'special:smartdock-minimized' }
  a.minimizedOrigins = { '0x1': { workspace: '1', monitor: '0' },
    '0x2': { workspace: '9', monitor: '0' } }
  r.length = 0
  assert.equal(a.moveCapturedToplevels(captured, 'id:12'), true)
  assert.equal(r.length, 1)
  assert.equal(r[0], DockModel.moveWindowRequest('2', 12, lua))
  assert.equal(a.minimizedOrigins['0x1'].workspace, '12')
  assert.equal(a.minimizedOrigins['0x1'].monitor, 'id:1')
  assert.equal(a.minimizedOrigins['0x2'], undefined)
  assert.equal(h[0].lastIpcObject.workspace.name, 'special:smartdock-minimized')
  r.length = 0
  assert.equal(a.moveCapturedToplevels([captured[0]], 'id:12'), false)
  assert.equal(r.length, 0)
  a.minimizedOrigins = {}
  assert.equal(a.moveCapturedToplevels([captured[0]], 'name:Design work'), true)
  assert.equal(a.minimizedOrigins['0x1'].monitor, 'id:1', 'explicit drop establishes missing origin')
  assert.equal(r.length, 0)
}

for (const invalid of ['other', '*', '12', 'id:999', 'id:0', 'id:01', 'special:scratch',
  'name:bad,dispatch', 'name:missing', 'id:12\n']) {
  const { actions: a, windows: w, requests: r } = fixture()
  assert.equal(a.resolveWorkspaceDropTarget(invalid), null)
  assert.equal(a.moveCapturedToplevels(a.captureWorkspaceMove([w[0]]), invalid), false)
  assert.equal(r.length, 0)
}
for (const mutate of [
  f => { f.handles[1].lastIpcObject.pinned = true },
  f => { f.handles[1].address = 'ff' },
  f => { f.handles[1].address = 'unsafe;' },
  f => { f.handles.splice(1, 1) },
  f => { f.workspaces.splice(2, 1) },
  f => { f.workspaces[2].monitor = 'missing-monitor' },
  f => { f.monitors.splice(1, 1) }
]) {
  const f = fixture()
  const captured = f.actions.captureWorkspaceMove(f.windows.slice(0, 2))
  mutate(f)
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), false)
  assert.equal(f.requests.length, 0, 'preflight rejects the whole unsafe surviving payload')
  assert.equal(Object.keys(f.actions.minimizedOrigins).length, 0)
}
{
  const f = fixture()
  f.handles[1].lastIpcObject.pinned = true
  assert.equal(f.actions.captureWorkspaceMove(f.windows.slice(0, 2)).length, 0)
  f.handles[1].lastIpcObject.pinned = false
  f.handles[1].address = f.handles[0].address
  assert.equal(f.actions.captureWorkspaceMove(f.windows.slice(0, 2)).length, 0,
    'ambiguous live address ownership is unsafe')
  assert.equal(f.actions.captureWorkspaceMove([]).length, 0)
  assert.equal(f.actions.captureWorkspaceMove([{}]).length, 0)
}
{
  const f = fixture()
  const captured = f.actions.captureWorkspaceMove(f.windows.slice(0, 2))
  const replacement = { appId: 'editor' }
  f.windows.splice(0, 1, replacement)
  f.handles[0].wayland = replacement
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), true)
  assert.deepEqual(f.requests, [DockModel.moveWindowRequest('2', 12, false)])
  f.windows.splice(1, 1)
  f.requests.length = 0
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), false)
  assert.equal(f.requests.length, 0)
}

// Exercise the production host methods with a bounded scene adapter: no copied
// hit-test or refresh algorithm, no Quickshell/QML module stubs.
{
  const f = fixture()
  let scheduled = 0
  let retargeted = 0
  const cards = [{ present: true, workspaceIdentity: 'id:12', dropCard: {
    visible: true, width: 150, height: 50,
    mapFromItem: (_item, x, y) => ({ x: x - 60, y: y - 20 }) } }]
  const dock = methods('Dock.qml', {
    DockWindowModel, windowActions: f.actions,
    grouped: true, workspaceDragActive: false, workspacePresentationDirty: false,
    workspaceMonitorScope: 'all', dockHyprMonitor: f.monitors[0], hyprMonitors: f.monitors,
    workspaceCards: { count: 1, itemAt: i => cards[i] },
    groupedLayout: { containsScenePoint: p => p.x >= 30 && p.x < 180 && p.y >= 0 && p.y < 100 },
    visibleItemsRefreshTimer: { restart: () => scheduled++ },
    workspaceDrag: { updatePointer: () => retargeted++, pointerScene: { x: 100, y: 30 } }
  })
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), 'id:12')
  assert.equal(dock.workspaceDropTargetAt({ x: 190, y: 30 }), '', 'clipped card region')
  assert.equal(dock.workspaceDropTargetAt({ x: 35, y: 30 }), '', 'gap')
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 80 }), '', 'outside card')
  dock.workspaceMonitorScope = 'current-monitor'
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'live monitor scope')
  dock.workspaceMonitorScope = 'all'
  cards[0].present = false
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'exiting card')
  cards[0].present = true
  f.workspaces.splice(2, 1)
  assert.equal(dock.workspaceDropTargetAt({ x: 100, y: 30 }), '', 'frozen card is not live inventory')
  dock.workspaceDragActive = true
  for (let i = 0; i < 5; i++) dock.scheduleVisibleItemsRefresh()
  dock.refreshVisibleItems()
  assert.equal(scheduled, 0)
  assert.equal(retargeted, 5, 'inventory changes still retarget the stationary pointer')
  assert.equal(dock.workspacePresentationDirty, true)
  dock.workspaceDragActive = false
  dock.finishWorkspacePresentation()
  assert.equal(scheduled, 1, 'one queued refresh after session end')
  assert.equal(dock.workspacePresentationDirty, false)
}

// Evaluate the real handler binding through the release latch. Actual native
// pointer delivery/arbitration remains the explicitly separate local gate.
{
  const expression = read('DockItem.qml').match(
    /id: workspaceDragHandler\s+enabled:([\s\S]*?)\n    target:/)?.[1]
  assert.ok(expression, 'workspace gesture binding is present')
  const root = { workspaceDragEnabled: true, presentationActive: true,
    workspaceGestureOwned: false, presentationVisible: true, runningCount: 1,
    sticky: false, workspaceInputSuppressed: false }
  const enabled = (patch = {}, active = false) => vm.runInNewContext(
    `Boolean(${expression})`, { root: { ...root, ...patch }, active })
  assert.equal(enabled(), true)
  assert.equal(enabled({ presentationVisible: false }), false)
  assert.equal(enabled({ sticky: true }), false)
  assert.equal(enabled({ runningCount: 0 }), false)
  assert.equal(enabled({ workspaceDragEnabled: false }, true), false)
  assert.equal(enabled({ presentationActive: false }, true), false)
  assert.equal(enabled({ presentationVisible: false, workspaceInputSuppressed: true }, true), true)
  assert.equal(enabled({ workspaceGestureOwned: true, workspaceInputSuppressed: true }), true,
    'active=false must not disable the handler before the release transition is delivered')

  const transitions = { UngrabExclusive: 1, CancelGrabExclusive: 2, CancelGrabPassive: 3 }
  for (const [transition, state, expected] of [[1, 1, 'finish'], [1, 0, 'cancel'],
    [2, 1, 'cancel'], [3, 1, 'cancel']]) {
    const calls = []
    const item = methods('DockItem.qml', { PointerDevice: transitions,
      EventPoint: { Released: 1 }, workspaceDrag: {
        finish: point => { calls.push(['finish', point]); item.workspaceDrag.sourceItem = null },
        cancel: () => { calls.push(['cancel']); item.workspaceDrag.sourceItem = null }
      } })
    // A vm context's external wrapper is not its in-context global identity.
    vm.runInContext('workspaceDrag.sourceItem = root', item)
    const point = { state, scenePosition: { x: 91, y: 37 } }
    item.workspaceGrabChanged(transition, point)
    item.workspaceGrabChanged(transition, point)
    assert.equal(calls.length, 1)
    assert.equal(calls[0][0], expected)
    if (expected === 'finish') assert.equal(calls[0][1], point.scenePosition)
  }
}

// Dock-local geometry is translated into Hyprland's logical virtual space.
{
  const Qt = {
    point: (x, y) => ({ x, y }),
    size: (width, height) => ({ width, height }),
    rect: (x, y, width, height) => ({ x, y, width, height })
  }
  const dock = methods('Dock.qml', {
    Qt,
    monitorOrigin: Qt.point(-1536, 240),
    monitorRect: Qt.rect(-1536, 240, 1536, 864),
    sceneOrigin: Qt.point(-1536, 900)
  })
  assert.deepEqual(dock.monitorLogicalOrigin({
    lastIpcObject: { x: -1536, y: 240 }
  }, { x: 12, y: 13 }), { x: -1536, y: 240 })
  assert.deepEqual(dock.monitorLogicalSize({
    lastIpcObject: { width: 1920, height: 1080, scale: 1.25 }
  }, { width: 999, height: 999 }), { width: 1536, height: 864 })
  assert.deepEqual(dock.workspaceMonitorVirtualRect({
    x: 600.5,
    y: 790.25,
    width: 720,
    height: 70
  }, 0, -780), { x: -935.5, y: 910.25, width: 720, height: 70 })
  assert.deepEqual(dock.workspaceMonitorVisibleRect({
    x: 600.5,
    y: 790.25,
    width: 720,
    height: 70
  }, 0, -600), { x: -935.5, y: 1090.25, width: 720, height: 13.75 },
  'drop geometry is clipped to the visible monitor while the dock animates')
  assert.deepEqual(dock.workspaceMonitorClipRect(
    Qt.rect(-1600, 200, 200, 120), Qt.rect(-1536, 240, 1536, 864)
  ), { x: -1536, y: 240, width: 136, height: 80 },
  'section hits clip overflowing cards to the visible monitor')
  assert.deepEqual(dock.workspaceMonitorClipRect(
    Qt.rect(0, 0, 10, 10), Qt.rect(20, 20, 10, 10)
  ), { x: 20, y: 20, width: 0, height: 0 },
  'cards wholly outside the visible bounds are not drop targets')
  const dockSource = read('Dock.qml')
  const sectionHits = dockSource.slice(
    dockSource.indexOf('function workspaceMonitorViewportRect'),
    dockSource.indexOf('function monitorDropSectionRect')
  )
  assert.match(sectionHits, /workspaceMonitorClipRect/,
    'section targets intersect card rectangles with visible bounds')
  assert.match(sectionHits, /groupedLayout/,
    'overflowing cards clip to the workspace viewport, not just the monitor')
  assert.match(sectionHits, /function workspaceMonitorViewportRect/,
    'the visible workspace strip is mapped once, not per overflowing card')
  assert.doesNotMatch(sectionHits, /visibleItemRect/,
    'pickup must not remap Flickable children; that can hide cards and disable drag')
  assert.match(read('DockWorkspaceGroup.qml'),
    /viewportWidth <= 0\) return/,
    'an unset workspace viewport must not mark headers unhittable')
}

// Workspace headers retain click activation while a threshold DragHandler owns
// only the cross-monitor gesture and commits only a released exclusive grab.
{
  const groupSource = read('DockWorkspaceGroup.qml')
  const handler = groupSource.match(
    /DragHandler \{\s+id: workspaceMonitorDragHandler([\s\S]*?)\n    \}/)?.[1] || ''
  assert.match(handler, /target: null/)
  assert.match(handler, /acceptedButtons: Qt\.LeftButton/)
  assert.doesNotMatch(handler, /acceptedModifiers:/,
    'ydotool and a stolen main keyboard can set phantom modifiers; header drag must still start')
  assert.match(handler, /dragThreshold: 0/,
    'layer-shell loses the grab on the first move unless the handler activates on press')
  assert.match(handler, /PointerHandler\.CanTakeOverFromItems/)
  assert.match(handler, /header\.forceActiveFocus\(Qt\.MouseFocusReason\)/)
  assert.doesNotMatch(groupSource, /focus: root.workspaceMonitorDragSource/,
    'taking focus on the card at drag start cancels the layer-shell pointer grab')
  assert.doesNotMatch(groupSource, /border\.width: activeFocus/,
    'workspace numbers never draw a mouse or keyboard focus accent ring')
  assert.match(groupSource, /header\.focus = false/,
    'release must drop header focus so hover does not restore the accent ring')
  assert.match(read('Dock.qml'),
    /WlrLayershell\.keyboardFocus: workspaceMonitorDragAvailable\s+\? WlrKeyboardFocus\.OnDemand : WlrKeyboardFocus\.None/,
    'keyboard mode must remain stable while the pointer handler owns its grab')
  assert.doesNotMatch(read('Dock.qml'),
    /keyboardFocus: workspaceMonitorDragSourceActive/,
    'starting a drag must not recommit layer-surface state and cancel its grab')
  assert.doesNotMatch(groupSource,
    /onWorkspace(?:Identity|OwnerMonitor)Changed: cancelWorkspaceMonitorDrag/,
    'delegate reuse must not cancel a host-owned drag; the coordinator validates live ownership')
  assert.match(read('Dock.qml'),
    /onDockShownChanged:[^\n]+hoveredTarget === root[^\n]+cancel/,
    'a destination disappearing under the pointer cancels the gesture')
  assert.match(read('Dock.qml'),
    /x: pointerLocal\.x - root\.workspaceMonitorDrag\.grabOffset\.x/,
    'the card ghost follows the pointer from the original grab offset')
  assert.match(read('Dock.qml'), /workspaceDragMapItem/,
    'card capture maps through a QQuickItem, not the PanelWindow')
  assert.match(groupSource,
    /TapHandler \{[\s\S]*?onTapped: \{[\s\S]*?root\.activated\(\)[\s\S]*?header\.focus = false/,
    'ordinary header clicks activate without retaining a mouse focus ring')
  assert.match(groupSource, /onPressedChanged: if \(pressed\)/,
    'header press must take layer focus before the drag threshold or the grab is lost on the first move')
  assert.match(groupSource, /Application\.styleHints\.startDragDistance/,
    'workspace monitor drag begins only after the platform distance threshold')
  assert.match(groupSource, /function updateWorkspaceMonitorGesture\(scenePoint, pressPoint\)/,
    'header threshold ownership is kept in one local gesture helper')
  assert.match(groupSource, /centroid\.scenePressPosition/,
    'header threshold distance starts at the actual pointer press')
  assert.doesNotMatch(groupSource, /workspaceMonitorPressPoint/,
    'header must not maintain a second press-point copy')
  assert.match(groupSource, /workspaceMonitorGestureStarted/,
    'press-time grab and threshold-crossing gesture state are separate')
  assert.match(groupSource,
    /active \|\| root\.workspaceMonitorGestureOwned[\s\S]*root\.switchable && root\.workspaceIdentity !== ""[\s\S]*root\.presentationVisible/,
    'an active gesture survives delegate reuse without making idle cards hittable')
  assert.match(groupSource,
    /workspaceMonitorDragSource: workspaceMonitorDrag[\s\S]*workspaceMonitorDrag\.sourceDock === workspaceMonitorDragDock[\s\S]*workspaceMonitorDrag\.sourceWorkspace === workspaceIdentity/,
    'source styling requires both dock and workspace identity')
  assert.doesNotMatch(groupSource, /workspaceMonitorDragSourceActive/,
    'unused duplicate source predicate is removed')
  assert.match(groupSource,
    /width: Math.min\(80, Math.max\(root\.slotSize, title\.implicitWidth \+ 16\)\)/,
    'the workspace number column must be at least one icon wide so card drag is hittable')
  assert.match(groupSource, /\n    DragHandler \{\s+id: workspaceMonitorDragHandler/,
    'monitor drag starts from the workspace number so window icons keep window-to-workspace drag')
  assert.doesNotMatch(groupSource, /\n  DragHandler \{\s+id: workspaceMonitorDragHandler/,
    'the full card must not steal window-icon drags')
  assert.match(read('Dock.qml'),
    /workspaceDragEnabled: root.grouped && appItem.originOnly\n/,
    'window icons move a window between workspace cards')
  assert.doesNotMatch(read('Dock.qml'),
    /workspaceDragEnabled: root.grouped && appItem.originOnly && !root.workspaceMonitorDragAvailable/,
    'grouped monitor drag must not disable window-icon workspace drag')
  assert.doesNotMatch(handler, /finish\(/,
    'DragHandler active=false must not commit; only UngrabExclusive+Released may finish')
  assert.match(read('Dock.qml'),
    /id: workspaceDrag\s+anchors\.fill: parent\s+z: 100\s+enabled: false\s+visible: active/,
    'the window-drag overlay must not steal clicks or drags from cards')

  const dragSource = read('DockWorkspaceMonitorDrag.qml')
  const updatePointer = dragSource.slice(
    dragSource.indexOf('function updatePointer'),
    dragSource.indexOf('function finish')
  )
  assert.doesNotMatch(updatePointer, /moveWorkspaceToMonitor/,
    'hovering a destination monitor must not dispatch the move')
  assert.match(updatePointer, /sectionHitAt/,
    'a covering section, including a rejected current-owner section, is detected before fallback')
  assert.match(updatePointer, /!covering/,
    'an explicit rejected section must block the physical-dock fallback')
  assert.doesNotMatch(updatePointer, /refreshTargetGeometry/,
    'pointer motion uses pickup-time geometry snapshots')
  assert.match(dragSource, /function refreshTargetGeometry/,
    'deliberate scrolling and completed reveal refresh target geometry')
  assert.match(read('Dock.qml'),
    /workspaceMonitorDrag\.updatePointer\(root\.workspaceMonitorDrag\.pointerScene\)/,
    'scrolling a destination dock must refresh monitor section targeting')
  assert.match(read('Dock.qml'),
    /workspaceMonitorDrag\.pointerVirtual\.x - root\.sceneOrigin\.x/,
    'monitor-drag coordinates are converted into each destination dock scene')
  assert.match(read('Dock.qml'),
    /workspaceMonitorDrag\.pointerVirtual\.y - root\.sceneOrigin\.y/,
    'monitor-drag vertical coordinates use the destination scene origin')
  assert.match(dragSource,
    /function finish\([\s\S]*moveWorkspaceToMonitor/,
    'the compositor move happens only after a released exclusive grab calls finish')
  assert.match(dragSource, /hoveredMonitor/,
    'same-dock foreign monitor sections must be first-class drop targets')
  assert.doesNotMatch(read('Dock.qml'),
    /anchors\.fill: parent\s+visible: root.workspaceMonitorDropHighlighted/,
    'a foreign monitor drop must not glow the entire dock')
  assert.match(read('Dock.qml'), /workspaceMonitorDropIdentity/,
    'drop glow follows the hovered monitor section')
  assert.match(read('Dock.qml'), /function monitorDropSectionRect/,
    'the accent overlay is clipped to the receiving monitor section')
  assert.match(read('Dock.qml'), /sectionMonitorIdentity/,
    'section hits include every card on the hovered monitor, not only the labeled first card')
  assert.match(read('Dock.qml'), /ghostUrl/,
    'the drag ghost must be the captured workspace card, not a number pill')
  assert.match(read('Dock.qml'), /workspaceDisplayPresentation/,
    'hover projection is display-only and leaves the live presentation authoritative')
  assert.match(read('Dock.qml'), /projectMonitorDrag/,
    'the dock uses the pure workspace projection helper')
  assert.match(read('Dock.qml'), /_monitorDragPlaceholder/,
    'destination placeholders are inert derived entries')
  const ghost = read('Dock.qml').slice(
    read('Dock.qml').indexOf('id: workspaceMonitorDragProxy'),
    read('Dock.qml').indexOf('id: hideTimer'))
  assert.doesNotMatch(ghost, /Behavior|scale:/,
    'the captured ghost follows the pointer directly without easing or scaling')
  assert.match(ghost, /enabled: false/,
    'the captured ghost cannot steal pointer input')
  assert.match(read('Dock.qml'), /cardForWorkspace/,
    'pickup must find the live workspace card so grabToImage can copy it')
  assert.match(dragSource, /grabToImage/,
    'the ghost is a pixel capture of the source card')
  assert.doesNotMatch(read('Dock.qml'), /mapToItem\(\s*root\s*,/,
    'section hits must map through an Item, not the PanelWindow')
  assert.match(read('Dock.qml'), /mapToItem\(\s*interactionArea\s*,/,
    'section hits use the dock Item that owns card geometry')
  assert.match(dragSource, /cancel\("capture failed"\)/,
    'a failed card snapshot aborts the gesture before dispatch')
  const pointerState = dragSource.slice(
    dragSource.indexOf('function clearPointerState'),
    dragSource.indexOf('function clearPending')
  )
  assert.doesNotMatch(pointerState, /ghostSize/,
    'pending confirmation retains the captured placeholder dimensions')
  const pendingState = dragSource.slice(
    dragSource.indexOf('function clearPending'),
    dragSource.indexOf('function reconcileCompositorOwnership')
  )
  assert.match(pendingState, /ghostSize = Qt\.size\(0, 0\)/,
    'terminal confirmation cleanup clears captured dimensions')
  assert.match(dragSource, /function resetBeginFailure\(\)[\s\S]*clearPointerState\(\)[\s\S]*clearPending\(\)/,
    'failed begin uses the same pointer and pending cleanup')
  assert.match(dragSource, /function endSession\(\)[\s\S]*clearPointerState\(\)[\s\S]*clearPending\(\)/,
    'session end uses the same pointer and pending cleanup')
  assert.match(dragSource,
    /var index = -1[\s\S]*if \(index < 0\) merged\.push\(snapshot\)[\s\S]*else merged\[index\] = snapshot/,
    'targeted refresh replaces or appends one dock snapshot')

  const transitions = { UngrabExclusive: 1, CancelGrabExclusive: 2, CancelGrabPassive: 3 }
  for (const [transition, state, expected] of [[1, 1, 'finish'], [1, 0, 'cancel'],
    [2, 1, 'cancel'], [3, 1, 'cancel']]) {
    const calls = []
    const dock = {}
    const group = methods('DockWorkspaceGroup.qml', { PointerDevice: transitions,
      EventPoint: { Released: 1 }, workspaceMonitorDragDock: dock,
      workspaceIdentity: 'id:3', workspaceMonitorGestureStarted: true,
      workspaceMonitorDrag: {
        sourceDock: dock,
        sourceWorkspace: 'id:3',
        finish: point => { calls.push(['finish', point]); group.workspaceMonitorDrag.sourceDock = null },
        cancel: () => { calls.push(['cancel']); group.workspaceMonitorDrag.sourceDock = null }
      } })
    const point = { state, scenePosition: { x: 143, y: 52 } }
    group.workspaceMonitorGrabChanged(transition, point)
    group.workspaceMonitorGrabChanged(transition, point)
    assert.equal(calls.length, 1)
    assert.equal(calls[0][0], expected)
    if (expected === 'finish') assert.equal(calls[0][1], point.scenePosition)
  }
}

// A known non-sticky fallback source is safe: the command uses its exact
// address and the destination is independently validated, never guessed.
for (const workspace of [{}, { id: -99, name: 'special:scratch' }]) {
  const f = fixture()
  f.handles[0].lastIpcObject.workspace = workspace
  const captured = f.actions.captureWorkspaceMove([f.windows[0]])
  assert.equal(captured.length, 1, 'resolvable Other windows source remains draggable')
  assert.equal(f.actions.moveCapturedToplevels(captured, 'id:12'), true)
  assert.deepEqual(f.requests, [DockModel.moveWindowRequest('1', 12, false)])
}
console.log('workspace dragging production actions, targets and refresh: PASS')
